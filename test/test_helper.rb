require 'rubygems'
require 'bundler/setup'

if ENV['COVERAGE']
  require 'simplecov'
  SimpleCov.start
end

require 'minitest/spec'
require 'minitest/autorun'
require 'mocha/setup'

require 'capissh/server_definition'

module TestExtensions
  def server(host, options={})
    Capissh::ServerDefinition.new(host, options)
  end
end

class MiniTest::Unit::TestCase
  include TestExtensions
end

