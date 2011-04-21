require 'spec/spec_helper'

describe TemplateStreaming::Autoflushing do
  include StreamingApp

  describe "when streaming" do
    describe "when autoflushing is on" do
      use_attribute_value TemplateStreaming, :autoflush, 0

      it "should automatically flush" do
        layout "[<%= yield %>]"
        view "(<%= render :partial => 'partial' %>)"
        partial 'partial'
        action { render :stream => true, :layout => 'layout' }
        run
        received.should == chunks('[', '(', 'partial', ')', ']', :end => true)
      end

      it "should autoflush correctly for partials with layouts where the partial is given as an option" do
        layout "[<%= yield %>]"
        view "(<%= render :partial => 'partial' %>)"
        partial "{<%= render :layout => 'subpartial_layout', :partial => 'subpartial' %>}"
        template 'test/_subpartial_layout', '<<%= yield %>>'
        template 'test/_subpartial', 'subpartial'
        action { render :stream => true, :layout => 'layout' }
        run
        received.should == chunks('[', '(', '{', '<', 'subpartial', '>', '}', ')', ']', :end => true)
      end

      it "should autoflush correctly for partials with layouts where the partial is given as a block" do
        layout "[<%= yield %>]"
        view "(<%= render :partial => 'partial' %>)"
        partial "{<% render :layout => 'subpartial_layout' do %>`<%= render :partial => 'subpartial' %>'<% end %>}"
        template 'test/_subpartial_layout', '<<%= yield %>>'
        template 'test/_subpartial', 'subpartial'
        action { render :stream => true, :layout => 'layout' }
        run
        received.should == chunks('[', '(', '{', '<', '`', 'subpartial', '\'', '>', '}', ')', ']', :end => true)
      end

      it "should autoflush correctly for views with multiple partials" do
        layout "[<%= yield %>][<%= yield %>]"
        view "(<%= render :partial => 'partial' %>)(<%= render :partial => 'partial' %>)"
        partial 'partial'
        action { render :stream => true, :layout => 'layout' }
        run
        received.should == chunks('[', '(', 'partial', ')(', 'partial', ')', '][', '(', 'partial', ')(', 'partial', ')', ']', :end => true)
      end

      it "should flush correctly when some of the automatic flushes are throttled" do
        with_attribute_value TemplateStreaming, :autoflush, 0.2 do
          data.t = Time.now
          Time.stub(:now).and_return(data.t)
          view <<-EOS.gsub(/^ *\|/, '')
            |<%= 1 -%>
            |<%= Time.stub(:now).and_return(data.t + 0.1); render :partial => 'a' -%>
            |<%= 2 -%>
            |<%= Time.stub(:now).and_return(data.t + 0.2); render :partial => 'b' -%>
            |<%= 3 -%>
            |<%= Time.stub(:now).and_return(data.t + 0.3); render :partial => 'c' -%>
            |<%= 4 -%>
          EOS
          action { render :stream => true, :layout => nil }
          template 'test/_a', 'a'
          template 'test/_b', 'b'
          template 'test/_c', 'c'
          template 'test/_d', 'd'
          action { render :stream => true, :layout => nil }
          run
          received.should == chunks('1', 'a2b3', 'c4', :end => true)
        end
      end
    end
  end
end
