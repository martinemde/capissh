require 'rspec/core/rake_task'

desc "Run unit specifications"
RSpec::Core::RakeTask.new do |spec|
  spec.rspec_opts = %w(-fs --color)
  spec.pattern = FileList['spec/**/*_spec.rb']
end

task :coverage => [:coverage_env, :spec]

task :coverage_env do
  ENV['COVERAGE'] = '1'
end

task :test => :spec
task :default => :spec
