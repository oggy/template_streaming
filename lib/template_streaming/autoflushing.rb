module TemplateStreaming
  class << self
    #
    # If non-nil, #flush will automatically be called when rendering
    # progressively before and after each render call.
    #
    # The value of this attribute should be a number, which is the
    # number of milliseconds since the last flush that should elapse
    # for the autoflush to occur. 0 means force a flush every time.
    #
    attr_accessor :autoflush
  end

  module Autoflushing
    module View
      def self.included(base)
        base.alias_method_chain :render, :template_streaming_autoflushing
      end

      def render_with_template_streaming_autoflushing(*args, &block)
        with_autoflushing do
          render_without_template_streaming_autoflushing(*args, &block)
        end
      end

      def capture(*args, &block)
        if block == @_proc_for_layout
          # Rendering the content of a progressive layout - inject autoflushing.
          with_autoflushing do
            super
          end
        else
          super
        end
      end

      def with_autoflushing
        controller.flush if TemplateStreaming.autoflush
        fragment = yield
        if TemplateStreaming.autoflush
          controller.push(fragment)
          ''
        else
          fragment
        end
      end
    end

    class Middleware
      def initialize(app)
        @app = app
      end

      def call(env)
        response = @app.call(env)
        if env[PROGRESSIVE_KEY] && TemplateStreaming.autoflush
          response[2] = BodyProxy.new(response[2])
        end
        response
      end

      class BodyProxy
        def initialize(body)
          @body = body
        end

        def each
          buffered_chunks = []
          autoflush_due_at = Time.now.to_f
          @body.each do |chunk|
            buffered_chunks << chunk
            if Time.now.to_f >= autoflush_due_at
              yield buffered_chunks.join
              buffered_chunks.clear
              autoflush_due_at = Time.now.to_f + TemplateStreaming.autoflush
            end
          end
          unless buffered_chunks.empty?
            yield buffered_chunks.join
          end
        end
      end
    end

    ActionView::Base.send :include, View
    ActionController::Dispatcher.middleware.use Middleware
  end
end
