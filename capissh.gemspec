# -*- encoding: utf-8 -*-
lib = File.expand_path('../lib/', __FILE__)
$:.unshift lib unless $:.include?(lib)
require 'capissh/version'

Gem::Specification.new do |s|
  s.name = "capissh"
  s.version = Capissh::VERSION
  s.platform = Gem::Platform::RUBY
  s.authors = ["Martin Emde"]
  s.email = "martin.emde@gmail.com"
  s.homepage = "http://github.com/martinemde/capissh"
  s.summary = "Extraction of Capistrano's parallel SSH command execution"
  s.description = s.summary

  s.files = Dir.glob("{bin,lib}/**/*") + %w(LICENSE README.md)
  s.require_path = 'lib'

  s.test_files = Dir.glob("spec/**/*")

  s.add_runtime_dependency('net-ssh', "~> 2.2.1")
  s.add_runtime_dependency('net-ssh-gateway', ">= 1.1.0")
  s.add_runtime_dependency('net-sftp', ">= 2.0.0")
  s.add_runtime_dependency('net-scp', ">= 1.0.0")

  s.add_development_dependency('rspec', '~>2.0')
  s.add_development_dependency('rake')
  s.add_development_dependency('minitest')
  s.add_development_dependency('mocha')
  s.add_development_dependency('simplecov')
end
