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
          response[2] = CachingBodyProxy.new(response[2], env[CACHER_KEY])
        response
      end

      class CachingBodyProxy
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

    module ActionCacheFilter
      def self.included(base)
        base.alias_method_chain :after, :template_streaming_caching
      end

      def after_with_template_streaming_caching(controller)
        if controller.render_progressively?
          # This flag is ass-backwards to me. It really means *don't* cache the layout...
          cache_layout? and
            raise NotImplementedError, "sorry, using caches_action with :layout => false is not yet supported by Template Streaming"
          controller.request.env[CACHER_KEY] = lambda do |content|
            # This is what the standard method does.
            controller.write_fragment(controller.action_cache_path.path, content, @options[:store_options])
          end
        else
          after_without_template_streaming_caching(controller)
        end
      end
    end

    ActionController::Base.send :include, Controller
    ActionController::Dispatcher.middleware.use Middleware
    ActionController::Caching::Actions::ActionCacheFilter.send :include, ActionCacheFilter
  end
end
