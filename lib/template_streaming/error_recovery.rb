module TemplateStreaming
  module ErrorRecovery
    CONTROLLER_KEY = 'template_streaming.error_recovery.controller'.freeze
    EXCEPTIONS_KEY = 'template_streaming.error_recovery.exceptions'.freeze

    class Middleware
      def initialize(app)
        @app = app
      end

      def call(env)
        response = *@app.call(env)
        if env[TemplateStreaming::STREAMING_KEY]
          response[2] = BodyProxy.new(env, response[2])
          response
        else
          response
        end
      end

      class BodyProxy
        def initialize(env, body)
          @env = env
          @body = body
          @controller = @env[CONTROLLER_KEY]
        end

        def each(&block)
          if @controller && @controller.show_errors?
            exceptions = @env[EXCEPTIONS_KEY] = []
            @state = :start
            @body.each do |chunk|
              advance_state(chunk)
              if !exceptions.empty?
                try_to_insert_errors(chunk, exceptions)
              end
              yield chunk
            end
            if !exceptions.empty?
              yield uninserted_errors(exceptions)
            end
          else
            @body.each(&block)
          end
        end

        def advance_state(chunk, cursor=0)
          case @state
          when :start
            if index = chunk.index(%r'<!doctype\b.*?>'i, cursor)
              @state = :before_html
              advance_state(chunk, index)
            end
          when :before_html
            if index = chunk.index(%r'<html\b'i, cursor)
              @state = :before_head
              advance_state(chunk, index)
            end
          when :before_head
            if index = chunk.index(%r'<head\b'i, cursor)
              @state = :in_head
              advance_state(chunk, index)
            end
          when :in_head
            if index = chunk.index(%r'</head\b.*?>'i, cursor)
              @state = :between_head_and_body
              advance_state(chunk, index)
            end
          when :between_head_and_body
            if index = chunk.index(%r'<body\b'i, cursor)
              @state = :in_body
              advance_state(chunk, index)
            end
          when :in_body
            if index = chunk.index(%r'</body\b.*?>'i, cursor)
              @state = :after_body
              advance_state(chunk, index)
            end
          when :after_body
            if index = chunk.index(%r'</html\b.*?>'i, cursor)
              @state = :after_html
              advance_state(chunk, index)
            end
          end
        end

        def try_to_insert_errors(chunk, exceptions)
          if (index = chunk =~ %r'</body\s*>\s*(?:</html\s*>\s*)?\z'im)
            chunk.insert(index, render_exceptions(exceptions))
            exceptions.clear
          end
        end

        def uninserted_errors(exceptions)
          html = render_exceptions(exceptions)
          exceptions.clear
          case @state
          when :start
            head = "<head><title>Unhandled Exception</title></head>"
            body = "<body>#{html}</body>"
            "<!DOCTYPE html><html>#{head}#{body}</html>"
          when :before_html
            head = "<head><title>Unhandled Exception</title></head>"
            body = "<body>#{html}</body>"
            "<html>#{head}#{body}</html>"
          when :before_head
            head = "<head><title>Unhandled Exception</title></head>"
            body = "<body>#{html}</body>"
            "#{head}#{body}</html>"
          when :in_head
            "</head><body>#{html}</body></html>"
          when :between_head_and_body
            "<body>#{html}</body></html>"
          when :in_body
            "#{html}</body></html>"
          when :after_body
            # Errors aren't likely to happen at this point, as after the body
            # there should only be "</html>". Just stick our error html in there
            # - it's invalid HTML no matter what we do.
            "#{html}</html>"
          when :after_html
            html
          end
        end

        def render_exceptions(exceptions)
          template = @controller.response.template
          template.render_streaming_exceptions(exceptions)
        end
      end
    end

    module Controller
      def self.included(base)
        base.when_streaming_template :set_template_streaming_controller
        base.class_inheritable_accessor :streaming_error_callbacks
        base.class_inheritable_accessor :streaming_error_renderer
        base.streaming_error_callbacks = []
        base.extend ClassMethods
      end

      module ClassMethods
        #
        # Call the given block when an error occurs while streaming.
        #
        # The block is called with the controller instance and exception object.
        #
        # Hook in your exception notification system here.
        #
        def on_streaming_error(&block)
          streaming_error_callbacks << block
        end

        #
        # Call the give block to render errors injected into the page, when
        # uncaught exceptions are raised while streaming.
        #
        # The block is called with the view instance an list of exception
        # objects. It should return the HTML to inject into the page.
        #
        def render_streaming_errors_with(&block)
          self.streaming_error_renderer = block
        end
      end

      def set_template_streaming_controller
        request.env[CONTROLLER_KEY] = self
      end

      def show_errors?
        local_request?
      end
    end

    module View
      def self.included(base)
        base.class_eval do
          alias_method_chain :render, :template_streaming_error_recovery
        end
      end

      def render_with_template_streaming_error_recovery(*args, &block)
        if streaming_template?
          begin
            render_without_template_streaming_error_recovery(*args, &block)
          rescue ActionView::MissingTemplate => e
            # ActionView uses this as a signal to try another template format.
            raise e
          rescue Exception => e
            logger.error "#{e.class}: #{e.message}"
            logger.error e.backtrace.join("\n").gsub(/^/, '  ')
            controller.streaming_error_callbacks.each{|c| c.call(e)}
            exceptions = controller.request.env[EXCEPTIONS_KEY] and
              exceptions << e
            '"><script type="text/javascript">window.location = "/500.html"</script></html>'
          end
        else
          render_without_template_streaming_error_recovery(*args, &block)
        end
      end

      def render_streaming_exceptions(exceptions)
        controller.streaming_error_renderer.call(self, exceptions)
      end

      def render_default_streaming_exceptions(exceptions)
        # Ensure errors in the error rendering don't recurse.
        @rendering_default_streaming_exceptions = true
        begin
          @content = exceptions.map do |exception|
            template_path = ActionController::Rescue::RESCUES_TEMPLATE_PATH
            @exception = exception
            @rescues_path = template_path
            render :file => "#{template_path}/rescues/template_error.erb"
          end.join
          render :file => "#{File.dirname(__FILE__)}/templates/errors.erb"
        ensure
          @rendering_default_streaming_exceptions = false
        end
      end
    end

    DEFAULT_ERROR_RENDERER = lambda do |view, exceptions|
      view.render_default_streaming_exceptions(exceptions)
    end

    ActionController::Dispatcher.middleware.insert_after ActionController::Failsafe, Middleware
    ActionController::Base.send :include, Controller
    ActionView::Base.send :include, View

    ActionController::Base.streaming_error_renderer = DEFAULT_ERROR_RENDERER
  end
end
