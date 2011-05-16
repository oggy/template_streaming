$:.unshift File.expand_path('lib', File.dirname(__FILE__))
require 'template_streaming/version'

Gem::Specification.new do |s|
  s.name        = 'template_streaming'
  s.date        = Time.now.strftime('%Y-%m-%d')
  s.version     = TemplateStreaming::VERSION.to_s
  s.authors     = ["George Ogata"]
  s.email       = ["george.ogata@gmail.com"]
  s.homepage    = "http://github.com/oggy/template_streaming"
  s.summary     = "Progressive rendering for Rails."
  s.description = <<-EOS.gsub(/^ *\|/, '')
    |Adds a #flush helper to Rails which flushes the output buffer to
    |the client before the template has finished rendering.
  EOS

  s.required_rubygems_version = ">= 1.3.6"
  s.add_dependency "actionpack", '~> 2.3.11'
  s.add_development_dependency "rspec"
  s.add_development_dependency "temporaries"
  s.files = Dir["{doc,lib,rails}/**/*"] + %w(LICENSE README.markdown Rakefile CHANGELOG)
  s.test_files = Dir["spec/**/*"]
  s.require_path = 'lib'
  s.specification_version = 3
end
