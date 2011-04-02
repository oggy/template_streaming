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
      #TestController.render_progressively
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
      #TestController.render_progressively
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
end
