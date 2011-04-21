require 'spec/spec_helper'

describe TemplateStreaming::Caching do
  include StreamingApp

  describe "page caching" do
    use_attribute_value ActionController::Base, :page_cache_directory, "#{TMP}/page_cache"
    use_attribute_value ActionController::Base, :perform_caching, true

    before do
      controller.caches_page :action
      action { render :stream => true }
      view "a<% flush %>b"
    end

    it "should render and cache the page correctly" do
      run
      received.should == chunks('a', 'b', :end => true)
      File.read("#{controller.page_cache_directory}/index.html").should == 'ab'
    end
  end

  describe "action caching" do
    before do
      push_attribute_value ActionController::Base, :cache_store, ActiveSupport::Cache::MemoryStore.new
    end

    after do
      pop_attribute_value ActionController::Base, :cache_store
    end

    describe "when streaming" do
      describe "when no layout is used" do
        before do
          controller.caches_action :action
        end

        it "should render the page correctly" do
          view "a<% flush %>b"
          action { render :stream => true, :layout => nil }
          run
          received.should == chunks('a', 'b', :end => true)
        end

        it "should use the cached copy if it exists" do
          view "<% data.render_count += 1 %>a<% flush %>b"
          action { render :stream => true, :layout => nil }
          data.render_count = 0
          run
          run
          received.should == 'ab'
          data.render_count.should == 1
        end
      end
    end

    describe "when not streaming" do
      describe "when no layout is used" do
        before do
          controller.caches_action :action
          action { render :stream => false, :layout => nil }
        end

        it "should render the page correctly" do
          view "a<% flush %>b"
          run
          received.should == 'ab'
        end

        it "should use the cached copy if it exists" do
          view "<% data.render_count += 1 %>a<% flush %>b"
          data.render_count = 0
          run
          run
          received.should == 'ab'
          data.render_count.should == 1
        end
      end

      describe "when the layout is cached" do
        before do
          controller.caches_action :action, :layout => true
          action { render :stream => false, :layout => 'layout' }
        end

        it "should cache the layout" do
          layout "<% data.render_count += 1 %>[<%= yield %>]"
          view "view"
          data.render_count = 0

          run
          received.should == '[view]'
          data.render_count.should == 1

          run
          received.should == '[view]'
          data.render_count.should == 1
        end
      end

      describe "when the layout is not cached" do
        before do
          controller.caches_action :action, :layout => false
          # AC always does render(:layout => true) to render the layout when the
          # body is cached, even if an explicit layout name is given. Hence, our
          # layout name must match the controller name.
          action { render :stream => false, :layout => 'test' }
        end

        it "should not cache the layout" do
          template 'layouts/test', "<% data.render_count += 1 %>[<%= yield %>]"
          view "view"
          data.render_count = 0

          run
          received.should == '[view]'
          data.render_count.should == 1

          run
          received.should == '[view]'
          data.render_count.should == 2
        end
      end
    end
  end
end
