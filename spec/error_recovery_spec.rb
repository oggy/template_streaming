require 'spec/spec_helper'

describe TemplateStreaming::ErrorRecovery do
  include StreamingApp

  describe "when there is an error during rendering" do
    before do
      class TestController
        def rescue_action(exception)
          # Run the default handler.
          ActionController::Base.instance_method(:rescue_action).bind(self).call(exception)
        end
      end
    end

    describe "when not streaming" do
      it "should show the standard error page" do
        view "<% raise 'test exception' %>"
        run
        received.should include("Action Controller: Exception caught")
        received.should include('test exception')
      end
    end

    describe "when streaming" do
      before do
        controller.render_streaming_errors_with do |view, exceptions|
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
          controller.on_streaming_error do |error|
            messages << error.original_exception.message
          end
          view "<% render :partial => 'a' %><% render :partial => 'b' %>"
          template 'test/_a', "<% raise 'a' %>"
          template 'test/_b', "<% raise 'b' %>"
          action { render :stream => true, :layout => nil }
          run
          messages.should == ['a', 'b']
        end

        describe "when a structurally-complete response is rendered" do
          before do
            view "<% raise 'x' %>"
            action { render :stream => true, :layout => 'layout' }
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
            action { render :stream => true, :layout => nil }
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
            action { render :stream => true, :layout => 'layout' }
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
          controller.on_streaming_error do |error|
            messages << error.original_exception.message
          end
          view "<% render :partial => 'a' %><% render :partial => 'b' %>"
          template 'test/_a', "<% raise 'a' %>"
          template 'test/_b', "<% raise 'b' %>"
          action { render :stream => true, :layout => nil }
          run
          messages.should == ['a', 'b']
        end

        it "should not inject any error information" do
          layout "<!DOCTYPE html><html><head></head><body><% flush %><%= yield %></body></html>"
          view "...<% raise 'x' %>..."
          action { render :stream => true, :layout => 'layout' }
          run
          received.should == chunks("<!DOCTYPE html><html><head></head><body>", "</body></html>", :end => true)
        end
      end
    end
  end

  describe "the default error rendering callback" do
    before do
      TestController.class_eval do
        def rescue_action(exception)
          # Run the default handler.
          ActionController::Base.instance_method(:rescue_action).bind(self).call(exception)
        end

        def local_request?
          true
        end
      end
    end

    it "should render the standard error information" do
      view "<% raise 'test exception' %>"
      action { render :stream => true }
      run
      received.should include('test exception')
      received.should include('#uncaught_exceptions')
    end
  end
end
