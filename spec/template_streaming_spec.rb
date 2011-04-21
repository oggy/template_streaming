require 'spec/spec_helper'

describe TemplateStreaming do
  include StreamingApp

  describe "#flush" do
    describe "when streaming" do
      before do
        action do
          render :stream => true, :layout => 'layout'
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

    describe "when not streaming" do
      it "should not affect the output" do
        view "a<% flush %>b"
        action { render :stream => false, :layout => nil }
        run
        received.should == 'ab'
      end

      it "should not invert the layout rendering order" do
        view "<% data.order << :view -%>"
        layout "<% data.order << :layout1 -%><%= yield -%><% data.order << :layout2 -%>"
        action { render :stream => false, :layout => 'layout' }
        data.order = []
        run
        data.order.should == [:view, :layout1, :layout2]
      end
    end
  end

  describe "#push" do
    describe "when streaming" do
      before do
        action do
          render :stream => true, :layout => 'layout'
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

    describe "when not streaming" do
      before do
        action do
          render :stream => false, :layout => 'layout'
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
    describe "when streaming" do
      before do
        action do
          render :stream => true, :layout => nil
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

    describe "when not streaming" do
      before do
        action do
          render :stream => false, :layout => nil
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

  describe ".stream" do
    before do
      TestController.layout 'layout'
      layout "[<% flush %><%= yield %>]"
      view "a"
    end

    it "should stream all actions if no options are given" do
      TestController.stream
      run
      received.should == chunks('[', 'a]', :end => true)
    end

    it "should stream the action if it is included with :only" do
      TestController.stream :only => :action
      run
      received.should == chunks('[', 'a]', :end => true)
    end

    it "should not stream the action if it is excepted" do
      TestController.stream :except => :action
      run
      received.should == "[a]"
    end

    it "should be overridden to true by an explicit :stream => true when rendering" do
      TestController.stream :except => :action
      action do
        render :stream => true
      end
      run
      received.should == chunks('[', 'a]', :end => true)
    end

    it "should be overridden to false by an explicit :stream => false when rendering" do
      TestController.stream :only => :action
      action do
        render :stream => false
      end
      run
      received.should == "[a]"
    end
  end

  describe "#render in the controller" do
    describe "when streaming" do
      before do
        @render_options = {:stream => true}
        view "(<% flush %><%= render :partial => 'partial' %>)"
        partial "a<% flush %>b"
      end

      describe "with a layout" do
        before do
          @render_options[:layout] = 'layout'
          layout "[<% flush %><%= yield %>]"
        end

        it "should stream templates specified with :action" do
          render_options = @render_options
          action do
            render render_options.merge(:action => 'action')
          end
          run
          received.should == chunks('[', '(', 'a', 'b)]', :end => true)
        end

        it "should stream templates specified with :partial" do
          render_options = @render_options
          action do
            render render_options.merge(:partial => 'partial')
          end
          run
          received.should == chunks('[', 'a', 'b]', :end => true)
        end

        it "should stream :inline templates" do
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

        it "should stream templates specified with :action" do
          render_options = @render_options
          action do
            render render_options.merge(:action => 'action')
          end
          run
          received.should == chunks('(', 'a', 'b)', :end => true)
        end

        it "should stream templates specified with :partial" do
          render_options = @render_options
          action do
            render render_options.merge(:partial => 'partial')
          end
          run
          received.should == chunks('a', 'b', :end => true)
        end

        it "should stream :inline templates" do
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

    describe "when not streaming" do
      before do
        @render_options = {:stream => false}
        view "(<%= render :partial => 'partial' %>)"
        partial "ab"
      end

      describe "with a layout" do
        before do
          @render_options[:layout] = 'layout'
          layout "[<%= yield %>]"
        end

        it "should not stream templates specified with :action" do
          render_options = @render_options
          action do
            render render_options.merge(:action => 'action')
          end
          run
          received.should == '[(ab)]'
        end

        it "should not stream templates specified with :partial" do
          render_options = @render_options
          action do
            render render_options.merge(:partial => 'partial')
          end
          run
          received.should == '[ab]'
        end

        it "should not stream :inline templates" do
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

        it "should not stream templates specified with :action" do
          render_options = @render_options
          action do
            render render_options.merge(:action => 'action')
          end
          run
          received.should == '(ab)'
        end

        it "should not stream templates specified with :partial" do
          render_options = @render_options
          action do
            render render_options.merge(:partial => 'partial')
          end
          run
          received.should == 'ab'
        end

        it "should not stream :inline templates" do
          render_options = @render_options
          action do
            render render_options.merge(:inline => 'ab')
          end
          run
          received.should == 'ab'
        end
      end

      it "should not stream a given :text string" do
        render_options = @render_options
        action do
          render render_options.merge(:text => 'ab')
        end
        run
        received.should == 'ab'
      end
    end

    it "should use the standard defaults when only a :stream option is given" do
      template 'layouts/controller_layout', "[<%= yield %>]"
      TestController.layout 'controller_layout'
      view 'a'
      action do
        render :stream => false
      end
      run
      received.should == '[a]'
    end
  end

  describe "#render in the view" do
    describe "when streaming" do
      before do
        action do
          render :stream => true, :layout => 'layout'
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

    describe "when not streaming" do
      before do
        action do
          render :stream => false, :layout => 'layout'
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
      TestController.stream
      action do
        @string = render_to_string :partial => 'partial'
        received.should == ''
        render :stream => true
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
      TestController.stream
      TestController.helper_method :render_to_string
      layout "<%= yield %>"
      view <<-'EOS'.gsub(/^ *\|/, '')
        |<% string = render_to_string :partial => 'partial' -%>
        |<% received.should == '' -%>
        |<%= string -%>
      EOS
      partial "partial"
      action do
        render :stream => true
      end
      run
      received.should == chunks("partial", :end => true)
    end
  end

  describe "initial chunk padding" do
    before do
      view "a<% flush %>"
      action do
        render :stream => true, :layout => nil
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

    it "should be called when streaming" do
      action do
        data.order << :action
        render :stream => true
      end
      run
      data.order.should == [:action, :callback, :rendering]
    end

    it "should not be called when not streaming" do
      action do
        data.order << :action
        render :stream => false
      end
      run
      data.order.should == [:action, :rendering]
    end
  end

  class BlackHoleSessionStore < ActionController::Session::AbstractStore
    def get_session(env, sid)
      ['id', {}]
    end

    def set_session(env, sid, data)
      true
    end

    def destroy(env)
      true
    end
  end

  describe "#flash" do
    describe "when streaming" do
      it "should behave correctly when referenced in the controller" do
        values = []
        view ""
        action do
          flash[:key] = "value" if params[:set]
          values << flash[:key]
          render :stream => true
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
          render :stream => true
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

      it "should be frozen in the view if the session is sent with the headers" do
        view "<% data.frozen = flash.frozen? %>"
        action { render :stream => true }
        run
        data.frozen.should be_true
      end

      it "should not be frozen in the view if the session is not sent with the headers" do
        with_attribute_value ActionController::Base, :session_store, BlackHoleSessionStore do
          view "<% data.frozen = flash.frozen? %>"
          action { render :stream => true }
          run
          data.frozen.should be_false
        end
      end
    end

    describe "when not streaming" do
      it "should behave correctly when referenced in the controller" do
        values = []
        view ""
        action do
          flash[:key] = "value" if params[:set]
          values << flash[:key]
          render :stream => false
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

    it "should not be frozen in the view" do
      view "<% data.frozen = flash.frozen? %>"
      action { render :stream => false }
      run
      data.frozen.should be_false
    end
  end

  describe "#flash.now" do
    describe "when streaming" do
      it "should behave correctly when referenced in the controller" do
        values = []
        view ""
        action do
          flash.now[:key] = "value" if params[:set]
          values << flash[:key]
          render :stream => true
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
          render :stream => true
        end
        run('QUERY_STRING' => 'set=1')
        session_cookie = headers['Set-Cookie'].scan(/^(session=[^;]*)/).first.first
        received.should == chunks('(value)', :end => true)

        run('HTTP_COOKIE' => session_cookie)
        received.should == chunks('()', :end => true)
      end
    end

    describe "when not streaming" do
      it "should behave correctly when referenced in the controller" do
        values = []
        view ""
        action do
          flash.now[:key] = "value" if params[:set]
          values << flash[:key]
          render :stream => false
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

  describe "#cookies" do
    describe "when streaming" do
      it "should be frozen in the view" do
        view "<% data.frozen = cookies.frozen? %>"
        action { render :stream => true }
        run
        data.frozen.should be_true
      end

      it "should be frozen in the view irrespective of session store" do
        with_attribute_value ActionController::Base, :session_store, BlackHoleSessionStore do
          view "<% data.frozen = cookies.frozen? %>"
          action { render :stream => true }
          run
          data.frozen.should be_true
        end
      end
    end

    describe "when not streaming" do
      it "should not be frozen in the view" do
        view "<% data.frozen = session.frozen? %>"
        action { render :stream => false }
        run
        data.frozen.should be_false
      end
    end
  end

  describe "#session" do
    describe "when streaming" do
      it "should be frozen in the view if the session is sent with the headers" do
        view "<% data.frozen = session.frozen? %>"
        action { render :stream => true }
        run
        data.frozen.should be_true
      end

      it "should not be frozen in the view if the session is not sent with the headers" do
        with_attribute_value ActionController::Base, :session_store, BlackHoleSessionStore do
          view "<% data.frozen = session.frozen? %>"
          action { render :stream => true }
          run
          data.frozen.should be_false
        end
      end
    end

    describe "when not streaming" do
      it "should not be frozen in the view" do
        view "<% data.frozen = session.frozen? %>"
        action { render :stream => false }
        run
        data.frozen.should be_false
      end
    end
  end

  describe "#form_authenticity_token" do
    describe "when streaming" do
      it "should match what is in the session when referenced in the controller" do
        view ''
        value = nil
        action do
          value = form_authenticity_token
          render :stream => true
        end
        run
        session[:_csrf_token].should == value
      end

      it "should match what is in the session when only referenced in the view" do
        view "<%= form_authenticity_token %>"
        action do
          render :stream => true
        end
        run
        received.should == chunks(session[:_csrf_token], :end => true)
      end
    end

    describe "when not streaming" do
      it "should match what is in the session when referenced in the controller" do
        view ''
        value = nil
        action do
          value = form_authenticity_token
          render :stream => false
        end
        run
        session[:_csrf_token].should == value
      end

      it "should match what is in the session when only referenced in the view" do
        view "<%= form_authenticity_token %>"
        action do
          render :stream => false
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
              render :layout => 'layout', :stream => true
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
            render :layout => 'layout', :stream => true
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
              render :layout => 'layout', :stream => true
            end
            run
            received.should == chunks('layout[', 'view[', 'outer_layout[', 'inner_layout[', 'inner]outer]]]', :end => true)
          end
        end
      end
    end
  end
end
