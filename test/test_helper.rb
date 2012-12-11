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

  def namespace(fqn=nil)
    space = stub(:roles => {}, :fully_qualified_name => fqn, :default_task => nil)
    yield(space) if block_given?
    space
  end

  def role(space, name, *args)
    opts = args.last.is_a?(Hash) ? args.pop : {}
    space.roles[name] ||= []
    space.roles[name].concat(args.map { |h| Capissh::ServerDefinition.new(h, opts) })
  end

  def new_task(name, namespace=@namespace, options={}, &block)
    block ||= Proc.new {}
    task = Capissh::TaskDefinition.new(name, namespace, options, &block)
    assert_equal block, task.body
    return task
  end
end

class MiniTest::Unit::TestCase
  include TestExtensions
end

