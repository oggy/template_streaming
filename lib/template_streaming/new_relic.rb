#
# The NewRelic agent won't consider activity outside of the
# controller's #perform_action inside the scope of the request. We
# need to add the rendering that occurs in the response body's #each
# to the stats and traces.
#
# The New Relic agent offers no useful API for this, so we resort to
# fugly, brittle hacks. Hopefully this will improve in a later version
# of the agent.
#
# Here's what we do:
#
#  Stats:
#
#   * We sandwich the action and view rendering between
#     Agent#start_accumulating and Agent#finish_accumulating.
#   * During this, the stats for the metric names passed
#     to #start_accumulating will be returned from the StatsEngine as
#     AccumulatedMethodTraceStats objects. These are stored outside of
#     the usual stats table.
#   * On #finish_accumulating, the AccumulatedMethodTraceStats
#     calculate the accumulated values and add them to the standard
#     stats table.
#   * We ensure the view stats are in the correct scope by storing the
#     metric_frame created during the controller's #perform_action,
#     and opening a new metric frame with attributes copied from the
#     saved metric frame.
#
#  Apdex:
#
#   * We stash the first metric frame in the env hash, and tell it not
#     to submit apdex values (#hold_apdex). Instead, it records the
#     times that would have been used in the apdex calculation.
#   * After body.each, we pass the first metric frame to the second to
#     accumulate the times for the apdex stat
#     (#record_accumulated_apdex)
#
#  Histogram:
#
#   * We intercept calls to Histogram#process(time) between
#     #start_accumulating and #finish_accumulating.
#   * On #finish_accumulating, we call the standard Histogram#process
#     to add the histogram stat.
#   * Because Agent#reset_stats replaces Agent#histogram with a fresh
#     instance, and this happens in a second thread outside of a
#     critical section, we can't store the accumulating time in the
#     histogram. We instead store it in the agent.
#
#  Traces:
#
#   * We intercept TransactionSampler#notice_scope_empty to stash the
#     completed samples in an array of accumulated samples.
#   * On #finish_accumulating, we merge the samples into a
#     supersample, which replaces the root segments of the accumulated
#     samples with one common root segment.
#   * The supersample is added to the list for harvesting.
#
# TODO
# ----
#
#  * Add support for New Relic developer mode profiling.
#

# Load parts of the agent we need to hack.
def self.expand_load_path_entry(path)
  $:.each do |dir|
    absolute_path = File.join(dir, path)
    return absolute_path if File.exist?(absolute_path)
  end
  nil
end
require 'new_relic/agent'
# New Relic requires this thing multiple times under different names...
require 'new_relic/agent/instrumentation/metric_frame'
require expand_load_path_entry('new_relic/agent/instrumentation/metric_frame.rb')
require 'new_relic/agent/instrumentation/controller_instrumentation'

module TemplateStreaming
  module NewRelic
    Error = Class.new(RuntimeError)

    # Rack environment keys.
    ENV_FRAME_DATA = 'template_streaming.new_relic.frame_data'
    ENV_RECORDED_METRICS = 'template_streaming.new_relic.recorded_metrics'
    ENV_METRIC_PATH = 'template_streaming.new_relic.metric_path'
    ENV_IGNORE_APDEX = 'template_streaming.new_relic.ignore_apdex'

    class Middleware
      def initialize(app)
        @app = app
      end

      def call(env)
        @env = env
        status, headers, @body = @app.call(env)
        [status, headers, self]
      rescue Exception => error
        agent.finish_accumulating
        raise
      end

      def each(&block)
        in_controller_scope do
          @body.each(&block)
        end
      ensure
        agent.finish_accumulating
      end

      private

      def agent
        ::NewRelic::Agent.instance
      end

      def in_controller_scope
        controller_frame_data = @env[ENV_FRAME_DATA] or
          # Didn't hit the action, or do_not_trace was set.
          return yield

        #return perform_action_with_newrelic_profile(args, &block) if NewRelic::Control.instance.profiling?

        # This is based on ControllerInstrumentation#perform_action_with_newrelic_trace.
        frame_data = ::NewRelic::Agent::Instrumentation::MetricFrame.current(true)
        frame_data.apdex_start = frame_data.start
        frame_data.request = controller_frame_data.request
        frame_data.push('Controller', @env[ENV_METRIC_PATH])
        begin
          frame_data.filtered_params = controller_frame_data.filtered_params
          ::NewRelic::Agent.trace_execution_scoped(@env[ENV_RECORDED_METRICS]) do
            begin
              frame_data.start_transaction
              ::NewRelic::Agent::BusyCalculator.dispatcher_start frame_data.start
              yield
            rescue Exception => e
              frame_data.notice_error(e)
              raise
            end
          end
        ensure
          ::NewRelic::Agent::BusyCalculator.dispatcher_finish
          frame_data.record_accumulated_apdex(controller_frame_data) unless @env[ENV_IGNORE_APDEX]
          frame_data.pop
        end
      end
    end

    module Controller
      def self.included(base)
        base.class_eval do
          # Make sure New Relic's hook wraps ours so we have access to the metric frame it sets.
          method_name = :perform_action_with_newrelic_trace
          method_defined?(method_name) || private_method_defined?(method_name) and
            raise "Template Streaming must be loaded before New Relic's controller instrumentation"
          alias_method_chain :process, :template_streaming
          alias_method_chain :perform_action, :template_streaming
        end
      end

      def process_with_template_streaming(request, response, method = :perform_action, *arguments)
        metric_names = ["HttpDispatcher", "Controller/#{newrelic_metric_path(request.parameters['action'])}"]
        ::NewRelic::Agent.instance.start_accumulating(*metric_names)
        process_without_template_streaming(request, response, method, *arguments)
      end

      def perform_action_with_template_streaming(*args, &block)
        unless _is_filtered?('do_not_trace')
          frame_data = request.env[ENV_FRAME_DATA] = ::NewRelic::Agent::Instrumentation::MetricFrame.current
          frame_data.hold_apdex
          # This depends on current scope stack, so stash it too.
          request.env[ENV_RECORDED_METRICS] = ::NewRelic::Agent::Instrumentation::MetricFrame.current.recorded_metrics
          request.env[ENV_METRIC_PATH] = newrelic_metric_path
          request.env[ENV_IGNORE_APDEX] = _is_filtered?('ignore_apdex')
        end
        perform_action_without_template_streaming(*args, &block)
      end
    end

    module StatsEngine
      def self.included(base)
        base.class_eval do
          alias_method_chain :get_stats_no_scope, :template_streaming
          alias_method_chain :get_custom_stats, :template_streaming
          alias_method_chain :get_stats, :template_streaming
        end
      end

      #
      # Start accumulating the given +metric_names+.
      #
      # The metric_names can be either strings or MetricSpec's. See
      # StatsEngine::MetricStats for which metric names you need to
      # accumulate.
      #
      def start_accumulating(*metric_names)
        metric_names.each do |metric_name|
          unaccumulated_stats = stats_hash[metric_name] ||= ::NewRelic::MethodTraceStats.new
          accumulated_stats = AccumulatedMethodTraceStats.new(unaccumulated_stats)
          accumulated_stats_hash[metric_name] ||= accumulated_stats
        end
      end

      #
      # Freeze and clear the list of accumulated stats, and add the
      # aggregated stats to the unaccumulated stats.
      #
      def finish_accumulating
        accumulated_stats_hash.each do |metric_name, stats|
          stats.finish_accumulating
          stats.freeze
        end
        accumulated_stats_hash.clear
      end

      def get_stats_no_scope_with_template_streaming(metric_name)
        accumulated_stats_hash[metric_name] ||
          get_stats_no_scope_without_template_streaming(metric_name)
      end

      def get_custom_stats_with_template_streaming(metric_name, stat_class)
        accumulated_stats_hash[metric_name] ||
          get_custom_stats_without_template_streaming(metric_name, stat_class)
      end

      def get_stats_with_template_streaming(metric_name, use_scope = true, scoped_metric_only = false)
        key = scoped_metric_only || (use_scope && scope_name && scope_name != metric_name) ?
        ::NewRelic::MetricSpec.new(metric_name, scope_name) : metric_name
        accumulated_stats_hash[key] ||
          get_stats_without_template_streaming(metric_name, use_scope, scoped_metric_only)
      end

      private

      def accumulated_stats_hash
        @accumulated_stats_hash ||= {}
      end
    end

    #
    # An AccumulatedMethodTraceStats is a proxy which aggregates the
    # stats given to it, and updates the stats given to it on
    # construction when #finish_accumulating is called.
    #
    # Example:
    #
    #   acc = AccumulatedMethodTraceStats.new(stats)
    #   acc.trace_call(20, 10)
    #   acc.trace_call(20, 10)
    #   acc.finish_accumulating  # calls stats.trace_call(40, 20)
    #
    class AccumulatedMethodTraceStats
      def initialize(target_stats)
        @target_stats = target_stats
      end

      def finish_accumulating
        if @recorded_data_points
          totals = aggregate(@recorded_data_points)
          @target_stats.record_data_point(*totals)
        end
        if @traced_calls
          totals = aggregate(@traced_calls)
          @target_stats.trace_call(*totals)
        end
        @record_data_points = @traced_calls = nil
      end

      def record_data_point(call_time, exclusive_time = call_time)
        recorded_data_points << [call_time, exclusive_time]
      end

      def trace_call(call_time, exclusive_time = call_time)
        traced_calls << [call_time, exclusive_time]
      end

      # No need to aggregate this.
      delegate :record_multiple_data_points, :to => '@target_stats'

      private

      def aggregate(data)
        total_call_time = total_exclusive_time = 0
        data.each do |call_time, exclusive_time|
          total_call_time      += call_time
          total_exclusive_time += exclusive_time
        end
        [total_call_time, total_exclusive_time]
      end

      def recorded_data_points
        @recorded_data_points ||= []
      end

      def traced_calls
        @traced_calls ||= []
      end
    end

    module MetricFrame
      def self.included(base)
        base.alias_method_chain :record_apdex, :template_streaming
      end

      #
      # Tell the MetricFrame to hold on to the times calculated during
      # #record_apdex instead of adding the apdex value to the stats.
      #
      # Call #record_accumulated_apdex on another MetricFrame with
      # this frame as an argument to record the total time.
      #
      def hold_apdex
        @hold_apdex = true
      end

      def record_apdex_with_template_streaming(*args, &block)
        return unless recording_web_transaction? && ::NewRelic::Agent.is_execution_traced?
        ending = Time.now.to_f
        if @hold_apdex
          @held_summary_apdex = ending - apdex_start
          @held_controller_apdex = ending - start
          return
        end
        record_apdex_without_template_streaming(*args, &block)
      end

      attr_reader :held_summary_apdex, :held_controller_apdex

      def record_accumulated_apdex(*previous_frames)
        return unless recording_web_transaction? && ::NewRelic::Agent.is_execution_traced?
        ending = Time.now.to_f
        total_summary_apdex = previous_frames.map{|frame| frame.held_summary_apdex}.sum
        total_controller_apdex = previous_frames.map{|frame| frame.held_controller_apdex}.sum
        summary_stat = ::NewRelic::Agent.instance.stats_engine.get_custom_stats("Apdex", ::NewRelic::ApdexStats)
        controller_stat = ::NewRelic::Agent.instance.stats_engine.get_custom_stats("Apdex/#{path}", ::NewRelic::ApdexStats)
        self.class.update_apdex(summary_stat, total_summary_apdex + ending - apdex_start, exception)
        self.class.update_apdex(controller_stat, total_controller_apdex + ending - start, exception)
      end
    end

    module ControllerInstrumentationShim
      def self.included(base)
        # This shim method takes the wrong number of args. Fix it.
        base.module_eval 'def newrelic_metric_path(*args); end', __FILE__, __LINE__ + 1
      end

      # This is private in the real ControllerInstrumentation module,
      # but we need it.
      def _is_filtered?(key)
        true
      end
    end

    module Histogram
      def self.included(base)
        base.alias_method_chain :process, :template_streaming
      end

      def start_accumulating
        # Agent#reset_stats replaces #histogram with a fresh one, so
        # we can't store accumulating response time in here. Store it
        # in the agent instead.
        agent.accumulated_histogram_time = 0
      end

      def finish_accumulating
        process_without_template_streaming(agent.accumulated_histogram_time)
        agent.accumulated_histogram_time = nil
      end

      def process_with_template_streaming(response_time)
        if agent.accumulated_histogram_time
          agent.accumulated_histogram_time += response_time
        else
          process_without_template_streaming(response_time)
        end
      end

      private

      def agent
        @agent ||= ::NewRelic::Agent.instance
      end
    end

    module Agent
      def start_accumulating(*metric_names)
        stats_engine.start_accumulating(*metric_names)
        histogram.start_accumulating
        transaction_sampler.start_accumulating
      end

      def finish_accumulating
        stats_engine.finish_accumulating
        histogram.finish_accumulating
        transaction_sampler.finish_accumulating
      end

      attr_accessor :accumulated_histogram_time
    end

    module TransactionSampler
      def self.included(base)
        base.alias_method_chain :notice_scope_empty, :template_streaming
      end

      def start_accumulating
        @accumulated_samples = []
      end

      def finish_accumulating
        supersample = merge_accumulated_samples or
          return nil
        @accumulated_samples = nil

        # Taken from TransactionSampler#notice_scope_empty.
        @samples_lock.synchronize do
          @last_sample = supersample

          @random_sample = @last_sample if @random_sampling

          # ensure we don't collect more than a specified number of samples in memory
          @samples << @last_sample if ::NewRelic::Control.instance.developer_mode?
          @samples.shift while @samples.length > @max_samples

          if @slowest_sample.nil? || @slowest_sample.duration < @last_sample.duration
            @slowest_sample = @last_sample
          end
        end
      end

      def notice_scope_empty_with_template_streaming(time=Time.now.to_f)
        if @accumulated_samples
          last_builder = builder or
            return
          last_builder.finish_trace(time)
          @accumulated_samples << last_builder.sample
          clear_builder
        else
          notice_scope_empty_without_template_streaming(time)
        end
      end

      private

      def merge_accumulated_samples
        return nil if @accumulated_samples.empty?

        # The RPM transaction trace viewer only shows the first
        # segment under the root segment. Move the segment trees of
        # subsequent samples under that of the first one.
        supersample = @accumulated_samples.shift.dup  # samples have been frozen
        supersample.incorporate(@accumulated_samples)
        supersample
      end
    end

    module TransactionSample
      #
      # Return a copy of this sample with the segment timestamps all
      # incremented by the given delta.
      #
      # Note that although the returned object is a different
      # TransactionSample instance, the segments will be the same
      # objects, modified in place. We would modify the
      # TransactionSample in place too, only this method is called on
      # frozen samples.
      #
      def bump_by(delta)
        root_segment.bump_by(delta)
        sample = dup
        sample.instance_eval{@start_time += delta}
        sample
      end

      #
      # Return the segment under the root.
      #
      # If the root segment has more than one child, raise an
      # error. It appears this is never supposed to happen,
      # though--the RPM transaction trace view only ever shows the
      # first segment.
      #
      def subroot_segment
        @subroot_segment ||=
          begin
            (children = @root_segment.called_segments).size == 1 or
              raise Error, "multiple top segments found"
            children.first
          end
      end

      #
      # Put the given samples under this one.
      #
      # The subroot children of the given samples are moved under this
      # sample's subroot.
      #
      def incorporate(samples)
        incorporated_duration = 0.0
        samples.each do |sample|
          # Bump timestamps by the total length of previous samples.
          sample = sample.bump_by(root_segment.duration + incorporated_duration)
          incorporated_duration += sample.root_segment.duration

          # Merge segments.
          sample.subroot_segment.called_segments.each do |segment|
            subroot_segment.add_called_segment(segment)
          end

          # Merge params.
          if (request_params = sample.params.delete(:request_params))
            params[:request_params].reverse_merge!(request_params)
          end
          if (custom_params = sample.params.delete(:custom_params))
            params[:custom_params] ||= {}
            params[:custom_params].reverse_merge!(custom_params)
          end
          params.reverse_merge!(sample.params)
        end

        root_segment.exit_timestamp += incorporated_duration
        subroot_segment.exit_timestamp += incorporated_duration
      end
    end

    module Segment
      attr_reader :called_segments
      attr_writer :exit_timestamp

      #
      # Increment the timestamps by the given delta.
      #
      def bump_by(delta)
        @entry_timestamp += delta
        @exit_timestamp += delta
        if @called_segments
          @called_segments.each do |segment|
            segment.bump_by(delta)
          end
        end
      end
    end

    ActionController::Dispatcher.middleware.insert(0, Middleware)
    ActionController::Base.send :include, Controller
    ::NewRelic::Agent::StatsEngine.send :include, StatsEngine
    ::NewRelic::Agent::Instrumentation::MetricFrame.send :include, MetricFrame
    ::NewRelic::Agent::Instrumentation::ControllerInstrumentation::Shim.send :include, ControllerInstrumentationShim
    ::NewRelic::Histogram.send :include, Histogram
    ::NewRelic::Agent::Agent.send :include, Agent
    ::NewRelic::Agent::TransactionSampler.send :include, TransactionSampler
    ::NewRelic::TransactionSample.send :include, TransactionSample
    ::NewRelic::TransactionSample::Segment.send :include, Segment
  end
end
