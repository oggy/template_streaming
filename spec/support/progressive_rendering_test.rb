module ProgressiveRenderingTest
  VIEW_PATH = "#{TMP}/views"
  COOKIE_SECRET = 'x'*30

  def self.included(base)
    base.before { setup_progressive_rendering_test }
    base.after { teardown_progressive_rendering_test }
  end

  def setup_progressive_rendering_test
    push_temporary_directory TMP

    ActionController::Base.session = {:key => "session", :secret => COOKIE_SECRET}
    ActionController::Routing::Routes.clear!
    ActionController::Routing::Routes.add_route('/', :controller => 'test', :action => 'action')

    push_constant_value Object, :TestController, Class.new(Controller)
    # Since we use Class.new, the class name is undefined in AC::Layout's
    # inherited hook, and so layout is not automatically called - do it now.
    TestController.layout('test', {}, true)
    TestController.view_paths = [VIEW_PATH]
    @log_buffer = ''
    TestController.logger = Logger.new(StringIO.new(@log_buffer))

    $current_spec = self
    @data = OpenStruct.new
  end

  def controller
    TestController
  end

  def teardown_progressive_rendering_test
    pop_constant_value Object, :TestController
    pop_temporary_directory
    FileUtils.rm_rf VIEW_PATH
    $current_spec = nil
  end

  def view(text)
    template("test/action", text)
  end

  def layout(text)
    template("layouts/layout", text)
  end

  def partial(text)
    template("test/_partial", text)
  end

  def template(template_path, text)
    path = "#{controller.view_paths.first}/#{template_path}.html.erb"
    FileUtils.mkdir_p File.dirname(path)
    open(path, 'w') { |f| f.print text }
  end

  def action(&block)
    TestController.class_eval do
      define_method(:action, &block)
    end
  end

  def run(env_overrides={})
    env = default_env.merge(env_overrides)
    app = ActionController::Dispatcher.new
    @data.received = ''
    @status, @headers, @body = app.call(env)
    @body.each do |chunk|
      @data.received << chunk
    end
  end

  attr_reader :status, :headers, :body, :data

  def session
    cookie_value = headers['Set-Cookie'].scan(/^session=([^;]*)/).first.first
    verifier = ActiveSupport::MessageVerifier.new(COOKIE_SECRET, 'SHA1')
    verifier.verify(CGI.unescape(cookie_value))
  end

  def default_env
    {
      'REQUEST_METHOD' => 'GET',
      'SCRIPT_NAME' => '',
      'PATH_INFO' => '/',
      'QUERY_STRING' => '',
      'SERVER_NAME' => 'test.example.com',
      'SERVER_PORT' => '',
      'rack.version' => [1, 1],
      'rack.url_scheme' => 'http',
      'rack.input' => StringIO.new,
      'rack.errors' => StringIO.new,
      'rack.multithread' => false,
      'rack.multiprocess' => false,
      'rack.run_once' => true,
      'rack.logger' => Logger.new(STDERR),
    }
  end

  class Controller < ActionController::Base
    def action
    end

    def rescue_action(exception)
      STDERR.puts "#{exception.class}: #{exception.message}"
      STDERR.puts exception.backtrace.join("\n").gsub(/^/, '  ')
      raise exception
    end
  end

  module Helpers
    def data
      $current_spec.data
    end

    def received
      data.received
    end

    def chunks(*chunks)
      options = chunks.last.is_a?(Hash) ? chunks.pop : {}
      content = ''
      chunks.each do |chunk|
        content << chunk.size.to_s(16) << "\r\n" << chunk << "\r\n"
      end
      content << "0\r\n\r\n" if options[:end]
      content
    end
  end

  include Helpers
  Controller.send :include, Helpers
  ActionView::Base.send :include, Helpers
end
