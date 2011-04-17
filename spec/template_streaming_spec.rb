require 'spec/spec_helper'

describe TemplateStreaming do
  include ProgressiveRenderingTest

  describe "#flush" do
    describe "when rendering progressively" do
      before do
        action do
          render :progressive => true, :layout => 'layout'
        end
      end

      it "should flush the rendered content immediately" do
        layout <<-'EOS'.gsub(/^ *\|/, '')
          |1
          |<% flush -%>
          |<% received.should == chunks("1\n") -%>
          |<%= yield -%>
          |<% flush -%>
          |<% received.should == chunks("1\n", "a\n", "b\n", "c\n") -%>
          |2
          |<% flush -%>
          |<% received.should == chunks("1\n", "a\n", "b\n", "c\n", "2\n") -%>
        EOS

        view <<-'EOS'.gsub(/^ *\|/, '')
          |a
          |<% flush -%>
          |<% received.should == chunks("1\n", "a\n") -%>
          |b
          |<% flush -%>
          |<% received.should == chunks("1\n", "a\n", "b\n") -%>
          |c
        EOS

        run
        received.should == chunks("1\n", "a\n", "b\n", "c\n", "2\n", :end => true)
      end
    end

    describe "when not rendering progressively" do
      before do
        action do
          render :progressive => false, :layout => 'layout'
        end
      end

      it "should do nothing" do
        view <<-'EOS'.gsub(/^ *\|/, '')
          |a
          |<% data.order << :view -%>
        EOS

        layout <<-'EOS'.gsub(/^ *\|/, '')
          |1
          |<% data.order << :layout1 -%>
          |<%= yield -%>
          |2
          |<% data.order << :layout2 -%>
        EOS

        data.order = []
        run
        data.order.should == [:view, :layout1, :layout2]
        received.should == "1\na\n2\n"
      end
    end
  end

  describe "#push" do
    describe "when rendering progressively" do
      before do
        action do
          render :progressive => true, :layout => 'layout'
        end
      end

      it "should send the given data to the client immediately" do
        layout <<-'EOS'.gsub(/^ *\|/, '')
          |<% push 'a' -%>
          |<% received.should == chunks("a") -%>
          |<% push 'b' -%>
          |<% received.should == chunks("a", "b") -%>
        EOS
        view ''
        run
        received.should == chunks("a", "b", :end => true)
      end
    end

    describe "when not rendering progressively" do
      before do
        action do
          render :progressive => false, :layout => 'layout'
        end
      end

      it "should do nothing" do
        layout <<-'EOS'.gsub(/^ *\|/, '')
          |<% push 'a' -%>
          |<% received.should == '' -%>
          |x
        EOS
        view ''
        run
        received.should == "x\n"
      end
    end
  end

  describe "response headers" do
    describe "when rendering progressively" do
      before do
        action do
          render :progressive => true, :layout => nil
        end
      end

      it "should not set a content length" do
        view ''
        run
        headers.key?('Content-Length').should be_false
      end

      it "should specify chunked transfer encoding" do
        view ''
        run
        headers['Transfer-Encoding'].should == 'chunked'
      end
    end

    describe "when not rendering progressively" do
      before do
        action do
          render :progressive => false, :layout => nil
        end
      end

      it "should not specify a transfer encoding" do
        view ''
        run
        headers.key?('Transfer-Encoding').should be_false
      end

      it "should set a content length" do
        view ''
        run
        headers['Content-Length'].should == '0'
      end
    end
  end

  describe ".render_progressively" do
    before do
      TestController.layout 'layout'
      layout "[<% flush %><%= yield %>]"
      view "a"
    end

    it "should render all actions progressively if no options are given" do
      TestController.render_progressively
      run
      received.should == chunks('[', 'a]', :end => true)
    end

    it "should render the action progressively if it is included with :only" do
      TestController.render_progressively :only => :action
      run
      received.should == chunks('[', 'a]', :end => true)
    end

    it "should not render the action progressively if it is excepted" do
      TestController.render_progressively :except => :action
      run
      received.should == "[a]"
    end

    it "should be overridden to true by an explicit :progressive => true when rendering" do
      TestController.render_progressively :except => :action
      action do
        render :progressive => true
      end
      run
      received.should == chunks('[', 'a]', :end => true)
    end

    it "should be overridden to false by an explicit :progressive => false when rendering" do
      TestController.render_progressively :only => :action
      action do
        render :progressive => false
      end
      run
      received.should == "[a]"
    end
  end

  describe "#render in the controller" do
    describe "when rendering progressively" do
      before do
        @render_options = {:progressive => true}
        view "(<% flush %><%= render :partial => 'partial' %>)"
        partial "a<% flush %>b"
      end

      describe "with a layout" do
        before do
          @render_options[:layout] = 'layout'
          layout "[<% flush %><%= yield %>]"
        end

        it "should render templates specified with :action progressively" do
          render_options = @render_options
          action do
            render render_options.merge(:action => 'action')
          end
          run
          received.should == chunks('[', '(', 'a', 'b)]', :end => true)
        end

        it "should render templates specified with :partial progressively" do
          render_options = @render_options
          action do
            render render_options.merge(:partial => 'partial')
          end
          run
          received.should == chunks('[', 'a', 'b]', :end => true)
        end

        it "should render :inline templates progressively" do
          render_options = @render_options
          action do
            render render_options.merge(:inline => "a<% flush %>b")
          end
          run
          received.should == chunks('[', 'a', 'b]', :end => true)
        end
      end

      describe "without a layout" do
        before do
          @render_options[:layout] = nil
        end

        it "should render templates specified with :action progressively" do
          render_options = @render_options
          action do
            render render_options.merge(:action => 'action')
          end
          run
          received.should == chunks('(', 'a', 'b)', :end => true)
        end

        it "should render templates specified with :partial progressively" do
          render_options = @render_options
          action do
            render render_options.merge(:partial => 'partial')
          end
          run
          received.should == chunks('a', 'b', :end => true)
        end

        it "should render :inline templates progressively" do
          render_options = @render_options
          action do
            render render_options.merge(:inline => "a<% flush %>b")
          end
          run
          received.should == chunks('a', 'b', :end => true)
        end
      end

      it "should not affect the :text option" do
        layout "[<%= yield %>]"
        render_options = @render_options
        action do
          render render_options.merge(:text => 'test')
        end
        run
        headers['Content-Type'].should == 'text/html; charset=utf-8'
        received.should == 'test'
      end

      it "should not affect the :xml option" do
        layout "[<%= yield %>]"
        render_options = @render_options
        action do
          render render_options.merge(:xml => {:key => 'value'})
        end
        run
        headers['Content-Type'].should == 'application/xml; charset=utf-8'
        received.gsub(/\n\s*/, '').should == '<?xml version="1.0" encoding="UTF-8"?><hash><key>value</key></hash>'
      end

      it "should not affect the :js option" do
        layout "[<%= yield %>]"
        render_options = @render_options
        action do
          render render_options.merge(:js => "alert('hi')")
        end
        run
        headers['Content-Type'].should == 'text/javascript; charset=utf-8'
        received.gsub(/\n\s*/, '').should == "alert('hi')"
      end

      it "should not affect the :json option" do
        layout "[<%= yield %>]"
        render_options = @render_options
        action do
          render render_options.merge(:json => {:key => 'value'})
        end
        run
        headers['Content-Type'].should == 'application/json; charset=utf-8'
        received.should == '{"key":"value"}'
      end

      it "should not affect the :update option" do
        layout "[<%= yield %>]"
        render_options = @render_options
        action do
          render :update, render_options do |page|
            page << "alert('hi')"
          end
        end
        run
        headers['Content-Type'].should == 'text/javascript; charset=utf-8'
        received.should == "alert('hi')"
      end

      it "should not affect the :nothing option" do
        layout "[<%= yield %>]"
        render_options = @render_options
        action do
          render render_options.merge(:nothing => true)
        end
        run
        headers['Content-Type'].should == 'text/html; charset=utf-8'
        received.should == ' '
      end

      it "should set the given response status" do
        layout "[<%= yield %>]"
        render_options = @render_options
        action do
          render render_options.merge(:nothing => true, :status => 418)
        end
        run
        status.should == 418
      end
    end

    describe "when not rendering progressively" do
      before do
        @render_options = {:progressive => false}
        view "(<%= render :partial => 'partial' %>)"
        partial "ab"
      end

      describe "with a layout" do
        before do
          @render_options[:layout] = 'layout'
          layout "[<%= yield %>]"
        end

        it "should render templates specified with :action unprogressively" do
          render_options = @render_options
          action do
            render render_options.merge(:action => 'action')
          end
          run
          received.should == '[(ab)]'
        end

        it "should render templates specified with :partial unprogressively" do
          render_options = @render_options
          action do
            render render_options.merge(:partial => 'partial')
          end
          run
          received.should == '[ab]'
        end

        it "should render :inline templates unprogressively" do
          render_options = @render_options
          action do
            render render_options.merge(:inline => 'ab')
          end
          run
          received.should == '[ab]'
        end
      end

      describe "without a layout" do
        before do
          @render_options[:layout] = nil
        end

        it "should render templates specified with :action unprogressively" do
          render_options = @render_options
          action do
            render render_options.merge(:action => 'action')
          end
          run
          received.should == '(ab)'
        end

        it "should render templates specified with :partial unprogressively" do
          render_options = @render_options
          action do
            render render_options.merge(:partial => 'partial')
          end
          run
          received.should == 'ab'
        end

        it "should render :inline templates unprogressively" do
          render_options = @render_options
          action do
            render render_options.merge(:inline => 'ab')
          end
          run
          received.should == 'ab'
        end
      end

      it "should render a given :text string unprogressively" do
        render_options = @render_options
        action do
          render render_options.merge(:text => 'ab')
        end
        run
        received.should == 'ab'
      end
    end

    it "should use the standard defaults when only a :progressive option is given" do
      template 'layouts/controller_layout', "[<%= yield %>]"
      TestController.layout 'controller_layout'
      view 'a'
      action do
        render :progressive => false
      end
      run
      received.should == '[a]'
    end
  end

  describe "#render in the view" do
    describe "when rendering progressively" do
      before do
        action do
          render :progressive => true, :layout => 'layout'
        end
        layout "[<% flush %><%= yield %>]"
        template 'test/_partial_layout', "{<% flush %><%= yield %>}"
      end

      it "should render partials with layouts correctly" do
        partial 'x'
        view "(<% flush %><%= render :partial => 'partial', :layout => 'partial_layout' %>)"
        run
        received.should == chunks('[', '(', '{', 'x})]', :end => true)
      end

      it "should render blocks with layouts correctly" do
        template 'test/_partial_layout', "{<% flush %><%= yield %>}"
        view "(<% flush %><% render :layout => 'partial_layout' do %>x<% end %>)"
        run
        received.should == chunks('[', '(', '{', 'x})]', :end => true)
      end
    end

    describe "when not rendering progressively" do
      before do
        action do
          render :progressive => false, :layout => 'layout'
        end
        layout "[<%= yield %>]"
        template 'test/_partial_layout', "{<%= yield %>}"
      end

      it "should render partials with layouts correctly" do
        partial 'x'
        view "(<%= render :partial => 'partial', :layout => 'partial_layout' %>)"
        run
        received.should == '[({x})]'
      end

      it "should render blocks with layouts correctly" do
        template 'test/_partial_layout', "{<%= yield %>}"
        view "(<% render :layout => 'partial_layout' do %>x<% end %>)"
        run
        received.should == '[({x})]'
      end
    end
  end

  describe "#render_to_string in the controller" do
    it "should not flush anything out to the client" do
      TestController.render_progressively
      action do
        @string = render_to_string :partial => 'partial'
        received.should == ''
        render :progressive => true
      end
      layout "<%= yield %>"
      view "<%= @string %>"
      partial "partial"
      run
      received.should == chunks("partial", :end => true)
    end
  end

  describe "#render_to_string in the view" do
    it "should not flush anything out to the client" do
      TestController.render_progressively
      TestController.helper_method :render_to_string
      layout "<%= yield %>"
      view <<-'EOS'.gsub(/^ *\|/, '')
        |<% string = render_to_string :partial => 'partial' -%>
        |<% received.should == '' -%>
        |<%= string -%>
      EOS
      partial "partial"
      action do
        render :progressive => true
      end
      run
      received.should == chunks("partial", :end => true)
    end
  end

  describe "initial chunk padding" do
    before do
      view "a<% flush %>"
      action do
        render :progressive => true, :layout => nil
      end
    end

    it "should extend to 255 bytes for Internet Explorer" do
      run('HTTP_USER_AGENT' => 'Mozilla/5.0 (Windows; U; MSIE 9.0; WIndows NT 9.0; en-US)')
      received.should == chunks("a<!--#{'+'*247}-->", :end => true)
    end

    it "should extend to 2048 bytes for Chrome" do
      run('HTTP_USER_AGENT' => 'Mozilla/5.0 (Windows NT 5.1) AppleWebKit/534.25 (KHTML, like Gecko) Chrome/12.0.706.0 Safari/534.25')
      received.should == chunks("a<!--#{'+'*2040}-->", :end => true)
    end

    it "should extend to 1024 bytes for Safari" do
      run('HTTP_USER_AGENT' => 'Mozilla/5.0 (Windows; U; Windows NT 6.1; tr-TR) AppleWebKit/533.20.25 (KHTML, like Gecko) Version/5.0.4 Safari/533.20.27')
      received.should == chunks("a<!--#{'+'*1016}-->", :end => true)
    end

    it "should not be included for Firefox" do
      run('HTTP_USER_AGENT' => 'Mozilla/5.0 (X11; Linux x86_64; rv:2.2a1pre) Gecko/20110324 Firefox/4.2a1pre')
      received.should == chunks("a", :end => true)
    end
  end

  describe "#when_streaming_template" do
    before do
      TestController.when_streaming_template { |c| c.data.order << :callback }
      view "<% data.order << :rendering %>"
      layout '<%= yield %>'
      data.order = []
    end

    it "should be called when rendering progressively" do
      action do
        data.order << :action
        render :progressive => true
      end
      run
      data.order.should == [:action, :callback, :rendering]
    end

    it "should not be called when not rendering progressively" do
      action do
        data.order << :action
        render :progressive => false
      end
      run
      data.order.should == [:action, :rendering]
    end
  end

  describe "#flash" do
    describe "when rendering progressively" do
      it "should behave correctly when referenced in the controller" do
        values = []
        view ""
        action do
          flash[:key] = "value" if params[:set]
          values << flash[:key]
          render :progressive => true
        end
        run('QUERY_STRING' => 'set=1')
        session_cookie = headers['Set-Cookie'].scan(/^(session=[^;]*)/).first.first

        run('HTTP_COOKIE' => session_cookie)
        session_cookie = headers['Set-Cookie'].scan(/^(session=[^;]*)/).first.first

        run('HTTP_COOKIE' => session_cookie)
        values.should == ['value', 'value', nil]
      end

      it "should behave correctly when only referenced in the view" do
        view "(<%= flash[:key] %>)"
        action do
          flash[:key] = "value" if params[:set]
          render :progressive => true
        end
        run('QUERY_STRING' => 'set=1')
        session_cookie = headers['Set-Cookie'].scan(/^(session=[^;]*)/).first.first
        received.should == chunks('(value)', :end => true)

        run('HTTP_COOKIE' => session_cookie)
        received.should == chunks('(value)', :end => true)
        session_cookie = headers['Set-Cookie'].scan(/^(session=[^;]*)/).first.first

        run('HTTP_COOKIE' => session_cookie)
        received.should == chunks('()', :end => true)
      end
    end

    describe "when not rendering progressively" do
      it "should behave correctly when referenced in the controller" do
        values = []
        view ""
        action do
          flash[:key] = "value" if params[:set]
          values << flash[:key]
          render :progressive => false
        end
        run('QUERY_STRING' => 'set=1')
        session_cookie = headers['Set-Cookie'].scan(/^(session=[^;]*)/).first.first

        run('HTTP_COOKIE' => session_cookie)
        session_cookie = headers['Set-Cookie'].scan(/^(session=[^;]*)/).first.first

        run('HTTP_COOKIE' => session_cookie)
        values.should == ['value', 'value', nil]
      end
    end

    it "should behave correctly when only referenced in the view" do
      view "(<%= flash[:key] %>)"
      action do
        flash[:key] = "value" if params[:set]
      end
      run('QUERY_STRING' => 'set=1')
      session_cookie = headers['Set-Cookie'].scan(/^(session=[^;]*)/).first.first
      received.should == '(value)'

      run('HTTP_COOKIE' => session_cookie)
      received.should == '(value)'
      session_cookie = headers['Set-Cookie'].scan(/^(session=[^;]*)/).first.first

      run('HTTP_COOKIE' => session_cookie)
      received.should == '()'
    end
  end

  describe "#flash.now" do
    describe "when rendering progressively" do
      it "should behave correctly when referenced in the controller" do
        values = []
        view ""
        action do
          flash.now[:key] = "value" if params[:set]
          values << flash[:key]
          render :progressive => true
        end
        run('QUERY_STRING' => 'set=1')
        session_cookie = headers['Set-Cookie'].scan(/^(session=[^;]*)/).first.first

        run('HTTP_COOKIE' => session_cookie)
        values.should == ['value', nil]
      end

      it "should behave correctly when only referenced in the view" do
        view "(<%= flash[:key] %>)"
        action do
          flash.now[:key] = "value" if params[:set]
          render :progressive => true
        end
        run('QUERY_STRING' => 'set=1')
        session_cookie = headers['Set-Cookie'].scan(/^(session=[^;]*)/).first.first
        received.should == chunks('(value)', :end => true)

        run('HTTP_COOKIE' => session_cookie)
        received.should == chunks('()', :end => true)
      end
    end

    describe "when not rendering progressively" do
      it "should behave correctly when referenced in the controller" do
        values = []
        view ""
        action do
          flash.now[:key] = "value" if params[:set]
          values << flash[:key]
          render :progressive => false
        end
        run('QUERY_STRING' => 'set=1')
        session_cookie = headers['Set-Cookie'].scan(/^(session=[^;]*)/).first.first

        run('HTTP_COOKIE' => session_cookie)
        values.should == ['value', nil]
      end
    end

    it "should behave correctly when only referenced in the view" do
      view "(<%= flash[:key] %>)"
      action do
        flash.now[:key] = "value" if params[:set]
      end
      run('QUERY_STRING' => 'set=1')
      session_cookie = headers['Set-Cookie'].scan(/^(session=[^;]*)/).first.first
      received.should == '(value)'

      run('HTTP_COOKIE' => session_cookie)
      received.should == '()'
    end
  end

  describe "#form_authenticity_token" do
    describe "when rendering progressively" do
      it "should match what is in the session when referenced in the controller" do
        view ''
        value = nil
        action do
          value = form_authenticity_token
          render :progressive => true
        end
        run
        session[:_csrf_token].should == value
      end

      it "should match what is in the session when only referenced in the view" do
        view "<%= form_authenticity_token %>"
        action do
          render :progressive => true
        end
        run
        received.should == chunks(session[:_csrf_token], :end => true)
      end
    end

    describe "when not rendering progressively" do
      it "should match what is in the session when referenced in the controller" do
        view ''
        value = nil
        action do
          value = form_authenticity_token
          render :progressive => false
        end
        run
        session[:_csrf_token].should == value
      end

      it "should match what is in the session when only referenced in the view" do
        view "<%= form_authenticity_token %>"
        action do
          render :progressive => false
        end
        run
        received.should == session[:_csrf_token]
      end
    end
  end

  describe "rendering" do
    def render_call(layout, partial, style)
      if style == :block
        "<% render :layout => '#{layout}' do %><%= render :partial => '#{partial}' %><% end %>"
      else
        "<%= render :layout => '#{layout}', :partial => '#{partial}' %>"
      end
    end

    describe "a partial with a layout inside another partial with a layout" do
      [:block, :partial].each do |outer_style|
        [:block, :partial].each do |inner_style|
          it "should work when the outer partial layout is specified with a #{outer_style} and the inner one with a #{inner_style}" do
            layout "layout[<% flush %><%= yield %>]"
            view "view[<% flush %>#{render_call 'outer_layout', 'outer', outer_style}]"
            template 'test/_outer_layout', 'outer_layout[<% flush %><%= yield %>]'
            template 'test/_inner_layout', 'inner_layout[<% flush %><%= yield %>]'
            template 'test/_outer', "outer[<% flush %>#{render_call 'inner_layout', 'inner', inner_style}]"
            template 'test/_inner', "inner"
            action do
              render :layout => 'layout', :progressive => true
            end
            run
            received.should == chunks('layout[', 'view[', 'outer_layout[', 'outer[', 'inner_layout[', 'inner]]]]]', :end => true)
          end
        end
      end
    end

    [:block, :partial].each do |style|
      describe "a partial with a layout inside the toplevel layout" do
        it "should render correctly when the partial layout is specified with a #{style}" do
          layout "layout[<% flush %>#{render_call 'partial_layout', 'partial', style}<%= yield %>]"
          view "view"
          partial "partial"
          template 'test/_partial_layout', 'partial_layout[<% flush %><%= yield %>]'
          action do
            render :layout => 'layout', :progressive => true
          end
          run
          received.should == chunks('layout[', 'partial_layout[', 'partial]view]', :end => true)
        end
      end
    end

    [:block, :partial].each do |outer_style|
      [:block, :partial].each do |inner_style|
        describe "a partial with a layout inside a partial layout" do
          it "should render correctly when the outer partial layout is specified with a #{outer_style} and the inner one with a #{inner_style}" do
            layout "layout[<% flush %><%= yield %>]"
            view "view[<% flush %>#{render_call 'outer_layout', 'outer', outer_style}]"
            template 'test/_outer_layout', "outer_layout[<% flush %>#{render_call 'inner_layout', 'inner', inner_style}<%= yield %>]"
            template 'test/_outer', 'outer'
            template 'test/_inner_layout', "inner_layout[<% flush %><%= yield %>]"
            template 'test/_inner', 'inner'
            partial "partial"
            action do
              render :layout => 'layout', :progressive => true
            end
            run
            received.should == chunks('layout[', 'view[', 'outer_layout[', 'inner_layout[', 'inner]outer]]]', :end => true)
          end
        end
      end
    end
  end

  describe "when there is an error during rendering" do
    before do
      class TestController
        def rescue_action(exception)
          # Run the default handler.
          ActionController::Base.instance_method(:rescue_action).bind(self).call(exception)
        end
      end
    end

    describe "when not progressively rendering" do
      it "should show the standard error page" do
        view "<% raise 'test exception' %>"
        run
        received.should include("Action Controller: Exception caught")
        received.should include('test exception')
      end
    end

    describe "when progressively rendering" do
      before do
        controller.render_errors_progressively_with do |view, exceptions|
          messages = exceptions.map { |e| e.original_exception.message }
          "(#{messages.join(',')})"
        end
      end

      describe "for local requests" do
        before do
          controller.class_eval do
            def local_request?
              true
            end
          end
        end

        it "should run the error callback for each error raised" do
          messages = []
          controller.on_progressive_rendering_error do |error|
            messages << error.original_exception.message
          end
          view "<% render :partial => 'a' %><% render :partial => 'b' %>"
          template 'test/_a', "<% raise 'a' %>"
          template 'test/_b', "<% raise 'b' %>"
          action { render :progressive => true, :layout => nil }
          run
          messages.should == ['a', 'b']
        end

        describe "when a structurally-complete response is rendered" do
          before do
            view "<% raise 'x' %>"
            action { render :progressive => true, :layout => 'layout' }
          end

          it "should inject errors correctly when the error occurs before the doctype" do
            layout "<%= yield %><!DOCTYPE html><html><head></head><body></body></html>"
            run
            received.should == chunks("<!DOCTYPE html><html><head></head><body>(x)</body></html>", :end => true)
          end

          it "should inject errors correctly when the error occurs before the opening html tag" do
            layout "<!DOCTYPE html><% flush %><% yield %><html><head></head><body></body></html>"
            run
            received.should == chunks("<!DOCTYPE html>", "<html><head></head><body>(x)</body></html>", :end => true)
          end

          it "should inject errors correctly when the error occurs before the beginning of the head" do
            layout "<!DOCTYPE html><html><% flush %><% yield %><head></head><body></body></html>"
            run
            received.should == chunks("<!DOCTYPE html><html>", "<head></head><body>(x)</body></html>", :end => true)
          end

          it "should inject errors correctly when the error occurs during the head" do
            layout "<!DOCTYPE html><html><head><% flush %><% yield %></head><body></body></html>"
            run
            received.should == chunks("<!DOCTYPE html><html><head>", "</head><body>(x)</body></html>", :end => true)
          end

          it "should inject errors correctly when the error occurs between the head and body" do
            layout "<!DOCTYPE html><html><head></head><% flush %><% yield %><body></body></html>"
            run
            received.should == chunks("<!DOCTYPE html><html><head></head>", "<body>(x)</body></html>", :end => true)
          end

          it "should inject errors correctly when the error occurs during the body" do
            layout "<!DOCTYPE html><html><head></head><body><% flush %><% yield %></body></html>"
            run
            received.should == chunks("<!DOCTYPE html><html><head></head><body>", "(x)</body></html>", :end => true)
          end

          it "should inject errors correctly when the error occurs after the body" do
            layout "<!DOCTYPE html><html><head></head><body></body><% flush %><% yield %></html>"
            run
            received.should == chunks("<!DOCTYPE html><html><head></head><body></body>", "</html>", "(x)", :end => true)
          end

          it "should inject errors correctly when the error occurs after the closing html tag" do
            layout "<!DOCTYPE html><html><head></head><body></body></html><% flush %><% yield %>"
            run
            received.should == chunks("<!DOCTYPE html><html><head></head><body></body></html>", "(x)", :end => true)
          end
        end

        describe "when an structurally-incomplete response is rendered" do
          before do
            action { render :progressive => true, :layout => nil }
          end

          it "should inject errors correctly when nothing is rendered" do
            view "<% flush %><% raise 'x' %>"
            run
            received.should == chunks("<!DOCTYPE html><html><head><title>Unhandled Exception</title></head><body>(x)</body></html>", :end => true)
          end

          it "should inject errors correctly when just the doctype is rendered" do
            view "<!DOCTYPE html><% flush %><% raise 'x' %>"
            run
            received.should == chunks("<!DOCTYPE html>", "<html><head><title>Unhandled Exception</title></head><body>(x)</body></html>", :end => true)
          end

          it "should inject errors correctly when just the doctype and opening html tag are rendered" do
            view "<!DOCTYPE html><html><% flush %><% raise 'x' %>"
            run
            received.should == chunks("<!DOCTYPE html><html>", "<head><title>Unhandled Exception</title></head><body>(x)</body></html>", :end => true)
          end

          it "should inject errors correctly when only half the head is rendered" do
            view "<!DOCTYPE html><html><head><% flush %><% raise 'x' %>"
            run
            received.should == chunks("<!DOCTYPE html><html><head>", "</head><body>(x)</body></html>", :end => true)
          end

          it "should inject errors correctly when only a head is rendered" do
            view "<!DOCTYPE html><html><head></head><% flush %><% raise 'x' %>"
            run
            received.should == chunks("<!DOCTYPE html><html><head></head>", "<body>(x)</body></html>", :end => true)
          end

          it "should inject errors correctly when the closing body tag is missing" do
            view "<!DOCTYPE html><html><head></head><body><% flush %><% raise 'x' %>"
            run
            received.should == chunks("<!DOCTYPE html><html><head></head><body>", "(x)</body></html>", :end => true)
          end

          it "should inject errors correctly when the closing html tag is missing" do
            view "<!DOCTYPE html><html><head></head><body></body><% flush %><% raise 'x' %>"
            run
            received.should == chunks("<!DOCTYPE html><html><head></head><body></body>", "(x)</html>", :end => true)
          end
        end

        describe "when the response consists of multiple templates" do
          before do
            action { render :progressive => true, :layout => 'layout' }
          end

          it "should inject errors when there is an error in the toplevel layout" do
            layout "<!DOCTYPE html><html><head></head><body><% flush %><%= raise 'x' %></body></html>"
            view ''
            run
            received.should == chunks("<!DOCTYPE html><html><head></head><body>", "(x)</body></html>", :end => true)
          end

          it "should inject errors when there is an error in the toplevel view" do
            layout "<!DOCTYPE html><html><head></head><body><% flush %>[<%= yield %>]</body></html>"
            view "<% raise 'x' %>"
            run
            received.should == chunks("<!DOCTYPE html><html><head></head><body>", "[](x)</body></html>", :end => true)
          end

          it "should inject errors when there is an error in a partial" do
            layout "<!DOCTYPE html><html><head></head><body><% flush %>[<%= yield %>]</body></html>"
            view "view{<%= render :partial => 'partial' %>}"
            partial "<% raise 'x' %>"
            run
            received.should == chunks("<!DOCTYPE html><html><head></head><body>", "[view{}](x)</body></html>", :end => true)
          end

          it "should inject errors when there is an error in a subpartial" do
            layout "<!DOCTYPE html><html><head></head><body><% flush %><%= yield %></body></html>"
            view "view{<%= render :partial => 'partial' %>}"
            partial "partial`<%= render :partial => 'subpartial' %>'"
            template 'test/_subpartial', "<% raise 'x' %>"
            run
            received.should == chunks("<!DOCTYPE html><html><head></head><body>", "view{partial`'}(x)</body></html>", :end => true)
          end

          it "should inject errors from all partials which raised an unhandled exception" do
            layout "<!DOCTYPE html><html><head></head><body><% flush %><%= yield %></body></html>"
            view "view[<%= render :partial => 'x' %><%= render :partial => 'ok' %><%= render :partial => 'y' %>]"
            template 'test/_x', "<% raise 'x' %>"
            template 'test/_y', "<% raise 'y' %>"
            template 'test/_ok', "ok"
            run
            received.should == chunks("<!DOCTYPE html><html><head></head><body>", "view[ok](x,y)</body></html>", :end => true)
          end
        end
      end

      describe "for nonlocal requests" do
        before do
          controller.class_eval do
            def local_request?
              false
            end
          end
        end

        it "should run the error callback for each error raised" do
          messages = []
          controller.on_progressive_rendering_error do |error|
            messages << error.original_exception.message
          end
          view "<% render :partial => 'a' %><% render :partial => 'b' %>"
          template 'test/_a', "<% raise 'a' %>"
          template 'test/_b', "<% raise 'b' %>"
          action { render :progressive => true, :layout => nil }
          run
          messages.should == ['a', 'b']
        end

        it "should not inject any error information" do
          layout "<!DOCTYPE html><html><head></head><body><% flush %><%= yield %></body></html>"
          view "...<% raise 'x' %>..."
          action { render :progressive => true, :layout => 'layout' }
          run
          received.should == chunks("<!DOCTYPE html><html><head></head><body>", "</body></html>", :end => true)
        end
      end
    end
  end
end
