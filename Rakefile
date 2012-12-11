require 'rake/testtask'
Rake::TestTask.new do |t|
  t.pattern = "test/*_test.rb"
  t.libs.push "test"
end

task :default => :test
task :spec => :test

task :coverage => [:coverage_env, :test]

task :coverage_env do
  ENV['COVERAGE'] = 'true'
end
