module TemplateStreaming
  module Caching
    CACHER_KEY = 'template_streaming.caching.cacher'.freeze

    module Controller
      def cache_page(content = nil, options = nil)
        if content
          super
        else
          request.env[CACHER_KEY] = lambda { |c| super(c, options) }
        end
      end
    end

    class Middleware
      def initialize(app)
        @app = app
      end

      def call(env)
        response = @app.call(env)
        path = env[CACHER_KEY] and
          response[2] = PageCachingBodyProxy.new(response[2], env[CACHER_KEY])
        response
      end

      class PageCachingBodyProxy
        def initialize(body, cacher)
          @body = body
          @cacher = cacher
        end

        def each
          chunks = []
          @body.each do |chunk|
            chunks << chunk
            yield chunk
          end
          @cacher.call(chunks.join)
        end
      end
    end

    ActionController::Base.send :include, Controller
    ActionController::Dispatcher.middleware.use Middleware
  end
end
