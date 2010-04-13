# -*- encoding: utf-8 -*-
$:.unshift File.expand_path('lib', File.dirname(__FILE__))
require 'template_streaming/version'

Gem::Specification.new do |s|
  s.name        = 'template_streaming'
  s.date        = Date.today.strftime('%Y-%m-%d')
  s.version     = TemplateStreaming::VERSION.join('.')
  s.platform    = Gem::Platform::RUBY
  s.authors     = ["George Ogata"]
  s.email       = ["george.ogata@gmail.com"]
  s.homepage    = "http://github.com/oggy/template_streaming"
  s.summary     = "Rails plugin which enables progressive rendering."
  s.description = <<-EOS.gsub(/^ *\|/, '')
    |Adds a #flush helper to Rails which lets you flush the output
    |buffer to the client early, allowing the client to begin fetching
    |external resources while the server is rendering the page.
  EOS

  s.required_rubygems_version = ">= 1.3.6"
  s.add_development_dependency "rspec"
  s.files = Dir["{doc,lib,rails}/**/*"] + %w(LICENSE README.markdown Rakefile CHANGELOG)
  s.test_files = Dir["spec/**/*"]
  s.extra_rdoc_files = ["LICENSE", "README.markdown"]
  s.require_path = 'lib'
  s.specification_version = 3
  s.rdoc_options = ["--charset=UTF-8"]
end
