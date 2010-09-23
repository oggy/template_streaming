module TemplateStreaming
  class << self
    #
    # Call the given block when an error occurs during rendering.
    #
    # The block is called with the exception object.
    #
    # This is where you should hook in your exception notification
    # system of choice (Hoptoad, Exceptional, etc.)
    #
    def on_render_error(&block)
      ErrorRecovery.callbacks << block
    end
  end

  module ErrorRecovery
    class << self
      attr_accessor :callbacks
    end
    self.callbacks = []

    EXCEPTIONS_KEY = 'template_streaming.exceptions'.freeze
    CONTROLLER_KEY = 'template_streaming.template'.freeze

    class Middleware
      def initialize(app)
        @app = app
      end

      def call(env)
        @env = env
        env[EXCEPTIONS_KEY] = []
        status, headers, @body = *@app.call(env)
        [status, headers, self]
      end

      def each(&block)
        controller = @env[CONTROLLER_KEY]
        if controller && controller.send(:local_request?)
          exceptions = @env[EXCEPTIONS_KEY]
          template = controller.response.template
          @body.each do |chunk|
            if !exceptions.empty? && (insertion_point = chunk =~ %r'</body\s*>\s*(?:</html\s*>\s*)?\z'im)
              chunk.insert(insertion_point, template.render_exceptions(exceptions))
              exceptions.clear
            end
            yield chunk
          end
          if !exceptions.empty?
            yield template.render_exceptions(exceptions)
          end
        else
          @body.each(&block)
        end
      end
    end

    module Controller
      def self.included(base)
        base.when_streaming_template :recover_from_errors
        base.helper Helper
        base.helper_method :recover_from_errors?
      end

      def recover_from_errors
        @recover_from_errors = true
        request.env[CONTROLLER_KEY] = self
      end

      def recover_from_errors?
        @recover_from_errors
      end
    end

    module Helper
      def render_partial(*)
        begin
          super
        rescue ActionView::MissingTemplate => e
          # ActionView uses this as a signal to try another template engine.
          raise e
        rescue Exception => e
          raise e if !recover_from_errors?
          Rails.logger.error("#{e.class}: #{e.message}")
          Rails.logger.error(e.backtrace.join("\n").gsub(/^/, '  '))
          callbacks = ErrorRecovery.callbacks and
            callbacks.each{|c| c.call(e)}
          request.env[EXCEPTIONS_KEY] << e
          ''
        end
      end

      def render_exceptions(exceptions)
        @content = exceptions.map do |exception|
          template_path = ActionController::Rescue::RESCUES_TEMPLATE_PATH
          @exception = exception
          @rescues_path = template_path
          render :file => "#{template_path}/rescues/template_error.erb"
        end.join
        render :file => "#{File.dirname(__FILE__)}/templates/errors.erb"
      end
    end

    ActionController::Base.send :include, Controller
    ActionController::Dispatcher.middleware.insert_after ActionController::Failsafe, Middleware
  end
end
