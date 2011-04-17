module TemplateStreaming
  class << self
    def configure(config)
      config.each do |key, value|
        send "#{key}=", value
      end
    end
  end

  PROGRESSIVE_KEY = 'template_streaming.progressive'.freeze

  module Controller
    def self.included(base)
      base.class_eval do
        extend ClassMethods
        alias_method_chain :render, :template_streaming
        alias_method_chain :render_to_string, :template_streaming
        alias_method_chain :flash, :template_streaming
        helper_method :flush, :push

        include ActiveSupport::Callbacks
        define_callbacks :when_rendering_progressively
      end
    end

    module ClassMethods
      def render_progressively(options={})
        before_filter :action_renders_progressively, options
      end
    end

    def action_renders_progressively
      @action_progressively_renders = true
    end

    def action_renders_progressively?
      @action_progressively_renders
    end

    def render_with_template_streaming(*args, &block)
      options = args.first { |a| a.is_a?(Hash) }
      if options && options.size == 1 && options.key?(:progressive)
        # Need to set the default values, since the standard #render won't.
        options[:template] = default_template
        options[:layout] = true
      end
      push_render_stack_frame do |stack_height|
        if start_rendering_progressively?(stack_height, *args)
          @render_progressively = true
          @template.render_progressively = true
          @performed_render = true
          @streaming_body = StreamingBody.new(progressive_rendering_threshold) do
            @performed_render = false
            last_piece = render_without_template_streaming(*args, &block)
            # The original render will clobber our response.body, so
            # we must push the buffer ourselves.
            push last_piece
          end
          response.body = @streaming_body
          response.prepare!
          form_authenticity_token  # generate now

          # Normally, the flash is swept on first reference. This
          # means we need to ensure it's referenced before the session
          # is persisted. In the case of the cookie store, that's when
          # the headers are sent, so we force a reference now.
          #
          # But alas, that's not all. @_flash is removed after
          # #perform_action, which means calling #flash in the view
          # would cause the flash to be referenced again, sweeping the
          # flash a second time. To prevent this, we preserve the
          # flash in a separate ivar, and patch #flash to return this
          # if we're rendering progressively.
          #
          flash  # ensure sweep
          @template_streaming_flash = @_flash
          request.env[PROGRESSIVE_KEY] = true

          run_callbacks :when_rendering_progressively
        else
          render_without_template_streaming(*args, &block)
        end
      end
    end

    # Mark the case when it's a layout for a toplevel render. This is
    # done here, as it's called after the option wrangling in
    # AC::Base#render, and nowhere else.
    def pick_layout(options)
      result = super
      options[:toplevel_render_with_layout] = true if result
      result
    end

    # Override to ensure calling render_to_string from a helper
    # doesn't trigger template streaming.
    def render_to_string_with_template_streaming(*args, &block) # :nodoc
      push_render_stack_frame do
        render_to_string_without_template_streaming(*args, &block)
      end
    end

    #
    # Flush the current template's output buffer out to the client
    # immediately.
    #
    def flush
      if @streaming_body && !@template.output_buffer.nil?
        push @template.output_buffer.slice!(0..-1)
      end
    end

    #
    # Push the given data to the client immediately.
    #
    def push(data)
      if @streaming_body
        @streaming_body.push(data)
        flush_thin
      end
    end

    def template_streaming_flash # :nodoc:
      @template_streaming_flash
    end

    def render_progressively?
      @render_progressively
    end

    private # --------------------------------------------------------

    def push_render_stack_frame
      @render_stack_height ||= 0
      @render_stack_height += 1
      begin
        yield @render_stack_height
      ensure
        @render_stack_height -= 1
      end
    end

    def start_rendering_progressively?(render_stack_height, *render_args)
      render_stack_height == 1 or
        return false

      (render_options = render_args.last).is_a?(Hash) or
        render_options = {}

      if !(UNSTREAMABLE_KEYS & render_options.keys).empty? || render_args.first == :update
        false
      else
        explicit_option = render_options[:progressive]
        if explicit_option.nil?
          action_renders_progressively?
        else
          explicit_option
        end
      end
    end

    UNSTREAMABLE_KEYS = [:text, :xml, :json, :js, :update, :nothing]

    #
    # The number of bytes that must be received by the client before
    # anything will be rendered.
    #
    def progressive_rendering_threshold
      content_type = response.header['Content-type']
      content_type.nil? || content_type =~ %r'\Atext/html' or
        return 0

      case request.env['HTTP_USER_AGENT']
      when /MSIE/
        255
      when /Chrome/
        # Note: Chrome's UA string includes "Safari", so it must precede.
        2048
      when /Safari/
        1024
      else
        0
      end
    end

    #
    # Force EventMachine to flush its buffer when using Thin.
    #
    def flush_thin
      connection = request.env['template_streaming.thin_connection'] and
        EventMachineFlush.flush(connection)
    end

    def flash_with_template_streaming # :nodoc:
      if defined?(@template_streaming_flash)
        # Flash has been swept - don't use the standard #flash or it'll sweep again.
        @template_streaming_flash
      else
        flash_without_template_streaming
      end
    end
  end

  # Only prepare once.
  module Response
    def self.included(base)
      base.alias_method_chain :prepare!, :template_streaming
      base.alias_method_chain :set_content_length!, :template_streaming
    end

    def prepare_with_template_streaming!
      return if defined?(@prepared)
      prepare_without_template_streaming!
      @prepared = true
    end

    def set_content_length_with_template_streaming!
      if body.is_a?(StreamingBody)
        # pass
      else
        set_content_length_without_template_streaming!
      end
    end
  end

  module View
    def self.included(base)
      base.alias_method_chain :render, :template_streaming
      base.alias_method_chain :_render_with_layout, :template_streaming
    end

    def render_with_template_streaming(*args, &block)
      options = args.first
      if render_progressively? && options.is_a?(Hash)
        # These branches exist to handle the case where AC::Base#render calls
        # AV::Base#render for rendering a partial with a layout. AC::Base
        # renders the partial then the layout separately, but we need to render
        # them together, in the reverse order (layout first). We do this by
        # standard-rendering the layout with a block that renders the partial.
        if options[:toplevel_render_with_layout] && (partial = options[:partial])
          # Don't render yet - we need to do the layout first.
          options.delete(:toplevel_render_with_layout)
          return DeferredPartialRender.new(args)
        elsif options[:text].is_a?(DeferredPartialRender)
          render = options.delete(:text)
          # We patch the case of rendering :partial with :layout
          # progressively in _render_with_layout.
          return render(render.args.first.merge(:layout => options[:layout]))
        end
      end
      render_without_template_streaming(*args, &block)
    end

    DeferredPartialRender = Struct.new(:args)

    attr_writer :render_progressively

    def render_progressively?
      @render_progressively
    end

    def _render_with_layout_with_template_streaming(options, local_assigns, &block)
      if !render_progressively?
        _render_with_layout_without_template_streaming(options, local_assigns, &block)
      elsif block_given?
        # The standard method doesn't properly restore @_proc_for_layout. Do it ourselves.
        original_proc_for_layout = @_proc_for_layout
        begin
          _render_with_layout_without_template_streaming(options, local_assigns, &block)
        ensure
          @_proc_for_layout = original_proc_for_layout
        end
      elsif options[:layout].is_a?(ActionView::Template)
        # Toplevel render call, from the controller.
        layout = options.delete(:layout)
        with_render_proc_for_layout(options) do
          render(options.merge(:file => layout.path_without_format_and_extension))
        end
      else
        layout = options.delete(:layout)
        with_render_proc_for_layout(options) do
          if (options[:inline] || options[:file] || options[:text])
            render(:file => layout, :locals => local_assigns)
          else
            render(options.merge(:partial => layout))
          end
        end
      end
    end

    def with_render_proc_for_layout(options)
      original_proc_for_layout = @_proc_for_layout
      @_proc_for_layout = lambda do |*args|
        if args.empty?
          render(options)
        else
          instance_variable_get(:"@content_for_#{args.first}")
        end
      end
      begin
        # TODO: what is @cached_content_for_layout in base.rb ?
        yield
      ensure
        @_proc_for_layout = original_proc_for_layout
      end
    end
  end

  class StreamingBody
    def initialize(threshold, &block)
      @process = block
      @bytes_to_threshold = threshold
    end

    def each(&block)
      @push = block
      @process.call
    end

    def push(data)
      if @bytes_to_threshold > 0
        @push.call(data + padding(@bytes_to_threshold - data.length))
        @bytes_to_threshold = 0
      else
        @push.call(data)
      end
    end

    private  # -------------------------------------------------------

    def padding(length)
      return '' if length <= 0
      content_length = [length - 7, 0].max
      "<!--#{'+'*content_length}-->"
    end
  end

  ActionView::Base.send :include, View
  ActionController::Base.send :include, Controller
  ActionController::Response.send :include, Response
  ActionController::Dispatcher.middleware.insert 0, Rack::Chunked
end

# Please let there be a better way to do this...
#
# We need to force Thin (EventMachine, really) to flush its output
# buffer before ending the current EventMachine tick. We can't use
# EventMachine.defer or .next_tick, as that would require returning
# from the call to the response body's #each. I'm not convinced Thin
# could even be rearchitected to support this without resorting to
# Threads, Continuations, or Fibers.
#
# Here, we hack Thin to add a handle to the connection object to the
# request environment, which we pass to EventMachineFlush, a horrid
# C++ hack. In ruby 1.8.7 we could use env[async.callback].receiver,
# but we want to support 1.8.6 for now too.
if defined?(Thin)
  begin
    require 'event_machine_flush'
  rescue LoadError
    raise "Template Streaming on Thin requires the event_machine_flush gem."
  end

  Rails.configuration.after_initialize do
    Thin::Connection.class_eval do
      def pre_process_with_template_streaming(*args, &block)
        @request.env['template_streaming.thin_connection'] = self
        pre_process_without_template_streaming(*args, &block)
      end
      alias_method_chain :pre_process, :template_streaming
    end
  end
end

require 'template_streaming/error_recovery'
