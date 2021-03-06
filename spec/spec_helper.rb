$:.unshift File.expand_path('../lib', File.dirname(__FILE__))

ROOT = File.expand_path('..', File.dirname(__FILE__))
TMP = "#{ROOT}/spec/tmp"

require 'bundler'
Bundler.setup(:default, :development)

require 'action_controller'
require 'template_streaming'
require 'temporaries'

require 'support/streaming_app'
