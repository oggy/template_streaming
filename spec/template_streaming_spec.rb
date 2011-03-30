require 'spec/spec_helper'

describe TemplateStreaming do
  include ProgressiveRenderingTest

  it "should render progressively when the layout is progressive" do
    TestController.layout 'test', :progressive => true

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

  it "should render normally when the layout is not progressive" do
    TestController.layout 'test'

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
