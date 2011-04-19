require 'spec/spec_helper'

describe TemplateStreaming::Caching do
  include ProgressiveRenderingTest

  describe "page caching" do
    use_attribute_value ActionController::Base, :page_cache_directory, "#{TMP}/page_cache"
    use_attribute_value ActionController::Base, :perform_caching, true

    before do
      controller.caches_page :action
      action { render :progressive => true }
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
      controller.caches_action :action
      push_attribute_value ActionController::Base, :cache_store, ActiveSupport::Cache::MemoryStore.new
    end

    after do
      pop_attribute_value ActionController::Base, :cache_store
    end

    describe "when no layout is used" do
      it "should render the page correctly" do
        view "a<% flush %>b"
        action { render :progressive => true, :layout => nil }
        run
        received.should == chunks('a', 'b', :end => true)
      end

      it "should use the cached copy if it exists" do
        view "<% data.render_count += 1 %>a<% flush %>b"
        action { render :progressive => true, :layout => nil }
        data.render_count = 0
        run
        run
        received.should == 'ab'
        data.render_count.should == 1
      end
    end
  end
end
