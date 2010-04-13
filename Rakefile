gem 'ritual'
require 'ritual'

spec_task :spec do |t|
  t.libs << 'lib' << 'spec'
  t.spec_files = FileList['spec/**/*_spec.rb']
end

spec_task :rcov do |t|
  t.libs << 'lib' << 'spec'
  t.pattern = 'spec/**/*_spec.rb'
  t.rcov = true
end

rdoc_task do |t|
  t.rdoc_dir = 'rdoc'
  t.title = "Template Streaming #{version}"
  t.rdoc_files.include('README*')
  t.rdoc_files.include('lib/**/*.rb')
end

task :default => :spec
