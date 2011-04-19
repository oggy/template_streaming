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
end
