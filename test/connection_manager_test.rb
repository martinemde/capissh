require "test_helper"
require 'capissh/connection_manager'

class ConnectionManagerTest < MiniTest::Unit::TestCase
  def setup
    @options = {:logger => stub_everything}
    @connection_manager = Capissh::ConnectionManager.new(@options)
    Net::SSH.stubs(:configuration_for).returns({})
    @ssh_options = {
      :user        => "user",
      :port        => 8080,
      :password    => "g00b3r",
      :ssh_options => { :debug => :verbose }
    }
  end

  def test_initialize_should_initialize_collections
    assert @connection_manager.sessions.empty?
  end

  def test_connection_factory_should_return_default_connection_factory_instance
    factory = @connection_manager.connection_factory
    assert_instance_of Capissh::ConnectionManager::DefaultConnectionFactory, factory
  end

  def test_connection_factory_instance_should_be_cached
    assert_same @connection_manager.connection_factory, @connection_manager.connection_factory
  end

  def test_default_connection_factory_honors_config_options
    server = server("capissh")
    Capissh::SSH.expects(:connect).with(server, @options).returns(:session)
    assert_equal :session, @connection_manager.connection_factory.connect_to(server)
  end

  def test_should_connect_through_gateway_if_gateway_variable_is_set
    @connection_manager = Capissh::ConnectionManager.new(@options.merge(:gateway => "j@gateway"))
    Net::SSH::Gateway.expects(:new).with("gateway", "j", :password => nil, :auth_methods => %w(publickey hostbased), :config => false).returns(stub_everything)
    assert_instance_of Capissh::ConnectionManager::GatewayConnectionFactory, @connection_manager.connection_factory
  end

  def test_connection_factory_as_gateway_should_honor_config_options
    @connection_manager = Capissh::ConnectionManager.new(@options.merge(@ssh_options).merge(:gateway => "gateway"))
    Net::SSH::Gateway.expects(:new).with("gateway", "user", :debug => :verbose, :port => 8080, :password => nil, :auth_methods => %w(publickey hostbased), :config => false).returns(stub_everything)
    assert_instance_of Capissh::ConnectionManager::GatewayConnectionFactory, @connection_manager.connection_factory
  end

  def test_connection_factory_as_gateway_should_chain_gateways_if_gateway_variable_is_an_array
    @connection_manager = Capissh::ConnectionManager.new(@options.merge(:gateway => ["j@gateway1", "k@gateway2"]))
    gateway1 = mock
    Net::SSH::Gateway.expects(:new).with("gateway1", "j", :password => nil, :auth_methods => %w(publickey hostbased), :config => false).returns(gateway1)
    gateway1.expects(:open).returns(65535)
    Net::SSH::Gateway.expects(:new).with("127.0.0.1", "k", :port => 65535, :password => nil, :auth_methods => %w(publickey hostbased), :config => false).returns(stub_everything)
    assert_instance_of Capissh::ConnectionManager::GatewayConnectionFactory, @connection_manager.connection_factory
  end

  def test_connection_factory_as_gateway_should_chain_gateways_if_gateway_variable_is_a_hash
    @connection_manager = Capissh::ConnectionManager.new(@options.merge(:gateway => { ["j@gateway1", "k@gateway2"] => :default }))
    gateway1 = mock
    Net::SSH::Gateway.expects(:new).with("gateway1", "j", :password => nil, :auth_methods => %w(publickey hostbased), :config => false).returns(gateway1)
    gateway1.expects(:open).returns(65535)
    Net::SSH::Gateway.expects(:new).with("127.0.0.1", "k", :port => 65535, :password => nil, :auth_methods => %w(publickey hostbased), :config => false).returns(stub_everything)
    assert_instance_of Capissh::ConnectionManager::GatewayConnectionFactory, @connection_manager.connection_factory
  end

  def test_connection_factory_as_gateway_should_share_gateway_between_connections
    @connection_manager = Capissh::ConnectionManager.new(@options.merge(:gateway => "j@gateway"))
    Net::SSH::Gateway.expects(:new).once.with("gateway", "j", :password => nil, :auth_methods => %w(publickey hostbased), :config => false).returns(stub_everything)
    Capissh::SSH.stubs(:connect).returns(stub_everything)
    assert_instance_of Capissh::ConnectionManager::GatewayConnectionFactory, @connection_manager.connection_factory
    @connection_manager.establish_connections_to(server("capissh"))
    @connection_manager.establish_connections_to(server("another"))
  end

  def test_connection_factory_as_gateway_should_share_gateway_between_like_connections_if_gateway_variable_is_a_hash
    @connection_manager = Capissh::ConnectionManager.new(@options.merge(:gateway => { "j@gateway" => [ "capissh", "another"] }))
    Net::SSH::Gateway.expects(:new).once.with("gateway", "j", :password => nil, :auth_methods => %w(publickey hostbased), :config => false).returns(stub_everything)
    Capissh::SSH.stubs(:connect).returns(stub_everything)
    assert_instance_of Capissh::ConnectionManager::GatewayConnectionFactory, @connection_manager.connection_factory
    @connection_manager.establish_connections_to(server("capissh"))
    @connection_manager.establish_connections_to(server("another"))
  end

  def test_connection_factory_as_gateways_should_not_share_gateway_between_unlike_connections_if_gateway_variable_is_a_hash
    @connection_manager = Capissh::ConnectionManager.new(@options.merge(:gateway => { "j@gateway" => [ "capissh", "another"], "k@gateway2" => "yafhost" }))
    Net::SSH::Gateway.expects(:new).once.with("gateway", "j", :password => nil, :auth_methods => %w(publickey hostbased), :config => false).returns(stub_everything)
    Net::SSH::Gateway.expects(:new).once.with("gateway2", "k", :password => nil, :auth_methods => %w(publickey hostbased), :config => false).returns(stub_everything)
    Capissh::SSH.stubs(:connect).returns(stub_everything)
    assert_instance_of Capissh::ConnectionManager::GatewayConnectionFactory, @connection_manager.connection_factory
    @connection_manager.establish_connections_to(server("capissh"))
    @connection_manager.establish_connections_to(server("another"))
    @connection_manager.establish_connections_to(server("yafhost"))
  end

  def test_establish_connections_to_should_accept_a_single_nonarray_parameter
    Capissh::SSH.expects(:connect).with { |s,| s.host == "capissh" }.returns(server('capissh'))
    assert @connection_manager.sessions.empty?
    @connection_manager.connect!(server("capissh"))
    assert_equal ["capissh"], @connection_manager.sessions.keys.map(&:host)
  end

  def test_establish_connections_to_should_accept_an_array
    list = [server('cap1'), server('cap2'), server('cap3')]
    list.each do |server|
      Capissh::SSH.expects(:connect).with(server, anything).returns(server)
    end
    assert @connection_manager.sessions.empty?
    @connection_manager.establish_connections_to(list)
    assert_equal %w(cap1 cap2 cap3), @connection_manager.sessions.keys.sort.map(&:host)
  end

  def test_establish_connections_to_should_not_attempt_to_reestablish_existing_connections
    list = [server('cap1'), server('cap2'), server('cap3')]
    list[1,2].each do |server|
      Capissh::SSH.expects(:connect).with(server, anything).returns(server)
    end
    @connection_manager.sessions[list[0]] = list[0]
    @connection_manager.establish_connections_to(list)
    assert_equal %w(cap1 cap2 cap3), @connection_manager.sessions.keys.sort.map(&:host)
  end

  def test_establish_connections_to_should_raise_one_connection_error_on_failure
    Capissh::SSH.expects(:connect).times(2).raises(Exception)
    assert_raises(Capissh::ConnectionError) {
      @connection_manager.establish_connections_to(%w(cap1 cap2).map { |s| server(s) })
    }
  end

  def test_connection_error_should_include_accessor_with_host_array
    Capissh::SSH.expects(:connect).times(2).raises(Exception)
    begin
      @connection_manager.establish_connections_to(%w(cap1 cap2).map { |s| server(s) })
      flunk "expected an exception to be raised"
    rescue Capissh::ConnectionError => e
      assert e.respond_to?(:hosts)
      assert_equal %w(cap1 cap2), e.hosts.map { |h| h.to_s }.sort
    end
  end

  def test_connection_error_should_only_include_failed_hosts
    Capissh::SSH.expects(:connect).with(server('cap1'), anything).raises(Exception)
    Capissh::SSH.expects(:connect).with(server('cap2'), anything).returns(server('cap2'))

    begin
      @connection_manager.execute_on_servers(%w(cap1 cap2).map { |s| server(s) }) {}
      flunk "expected an exception to be raised"
    rescue Capissh::ConnectionError => e
      assert_equal %w(cap1), e.hosts.map { |h| h.to_s }
    end
  end

  def test_execute_on_servers_should_require_a_block
    assert_raises(ArgumentError) { @connection_manager.execute_on_servers([]) }
  end

  def test_execute_on_servers_should_require_servers
    assert_raises(ArgumentError) { @connection_manager.execute_on_servers {} }
  end

  def test_execute_on_servers_should_call_find_servers
    list = [server("first"), server("second")]
    list.each do |server|
      Capissh::SSH.expects(:connect).with(server,anything).returns(server)
    end
    @connection_manager.execute_on_servers(list) do |result|
      assert_equal Capissh::Sessions.new(list), result
    end
  end

  def test_execute_on_servers_should_raise_error_if_no_matching_servers
    assert_raises(Capissh::NoMatchingServersError) { @connection_manager.execute_on_servers([]) { |list| } }
  end

  def test_execute_on_servers_should_raise_an_error_if_no_servers_are_sent
    assert_raises(Capissh::NoMatchingServersError) do
      @connection_manager.execute_on_servers([]) do
        flunk "should not get here"
      end
    end
  end

  def test_execute_on_servers_should_not_raise_an_error_if_no_servers_and_continue_on_no_matching_servers
    @connection_manager.execute_on_servers([], :continue_on_no_matching_servers => true) do
      flunk "should not get here"
    end
  end

  def test_execute_on_servers_should_determine_server_list_from_active_task
    assert @connection_manager.sessions.empty?
    list = [server("cap1"), server("cap2"), server("cap3")]
    Capissh::SSH.expects(:connect).times(3).returns(*list.reverse)
    @connection_manager.execute_on_servers(list) {}
    assert_equal %w(cap1 cap2 cap3), @connection_manager.sessions.keys.sort.map { |s| s.host }
  end

  def test_execute_on_servers_should_yield_server_list_to_block
    assert @connection_manager.sessions.empty?
    list = [server("cap1"), server("cap2"), server("cap3")]
    Capissh::SSH.expects(:connect).times(3).returns(*list.reverse)
    block_called = false
    @connection_manager.execute_on_servers(list) do |servers|
      block_called = true
      assert servers.detect { |s| s.host == "cap1" }
      assert servers.detect { |s| s.host == "cap2" }
      assert servers.detect { |s| s.host == "cap3" }
      assert servers.all? { |s| @connection_manager.sessions[s] }
    end
    assert block_called
  end

  def test_execute_servers_should_raise_connection_error_on_failure_by_default
    list = [server("cap1")]
    Capissh::SSH.expects(:connect).raises(Exception)
    assert_raises(Capissh::ConnectionError) do
      @connection_manager.execute_on_servers(list) do
        flunk "expected an exception to be raised"
      end
    end
  end

  def test_execute_servers_should_not_raise_connection_error_on_failure_with_on_errors_continue
    list = [server("cap1"), server("cap2")]
    Capissh::SSH.expects(:connect).with(server('cap1'), anything).raises(Exception)
    Capissh::SSH.expects(:connect).with(server('cap2'), anything).returns(server('cap2'))
    @connection_manager.execute_on_servers(list, :continue_on_error => true) do |servers|
      assert_equal %w(cap2), servers.map { |s| s.host }
    end
  end

  def test_execute_on_servers_should_not_try_to_connect_to_hosts_with_connection_errors_with_on_errors_continue
    list = [server("cap1"), server("cap2")]
    Capissh::SSH.expects(:connect).with(server('cap1'), anything).raises(Exception)
    Capissh::SSH.expects(:connect).with(server('cap2'), anything).returns(server('cap2'))
    @connection_manager.execute_on_servers(list, :continue_on_error => true) do |servers|
      assert_equal %w(cap2), servers.map { |s| s.host }
    end
    @connection_manager.execute_on_servers(list, :continue_on_error => true) do |servers|
      assert_equal %w(cap2), servers.map { |s| s.host }
    end
  end

  def test_execute_on_servers_should_not_try_to_connect_to_hosts_with_command_errors_with_on_errors_continue
    cap1 = server("cap1")
    cap2 = server("cap2")
    list = [cap1, cap2]
    list.each do |server|
      Capissh::SSH.expects(:connect).with(server,anything).returns(server)
    end
    @connection_manager.execute_on_servers(list, :continue_on_error => true) do |servers|
      error = Capissh::CommandError.new
      error.hosts = [cap1]
      raise error
    end
    @connection_manager.execute_on_servers(list, :continue_on_error => true) do |servers|
      assert_equal %w(cap2), servers.map { |s| s.host }
    end
  end

  def test_execute_on_servers_should_not_try_to_connect_to_hosts_with_transfer_errors_with_on_errors_continue
    cap1 = server("cap1")
    cap2 = server("cap2")
    list = [cap1, cap2]
    list.each do |server|
      Capissh::SSH.expects(:connect).with(server,anything).returns(server)
    end
    @connection_manager.execute_on_servers(list, :continue_on_error => true) do |servers|
      error = Capissh::TransferError.new
      error.hosts = [cap1]
      raise error
    end
    @connection_manager.execute_on_servers(list, :continue_on_error => true) do |servers|
      assert_equal %w(cap2), servers.map { |s| s.host }
    end
  end

  def test_connect_should_establish_connections_to_all_servers_in_scope
    assert @connection_manager.sessions.empty?
    list = [server("cap1"), server("cap2"), server("cap3")]
    list.each do |server|
      Capissh::SSH.expects(:connect).with(server,anything).returns(server)
    end
    @connection_manager.connect!(list)
    assert_equal %w(cap1 cap2 cap3), @connection_manager.sessions.keys.sort.map { |s| s.host }
  end

  def test_execute_on_servers_should_only_run_on_tasks_max_hosts_hosts_at_once
    cap1 = server("cap1")
    cap2 = server("cap2")
    connection1 = mock()
    connection2 = mock()
    connection1.expects(:close)
    connection2.expects(:close)
    list = [cap1, cap2]
    Capissh::SSH.expects(:connect).times(2).returns(connection1).then.returns(connection2)
    block_called = 0
    @connection_manager.execute_on_servers(list, :max_hosts => 1) do |servers|
      block_called += 1
      assert_equal 1, servers.size
    end
    assert_equal 2, block_called
  end

  def test_execute_on_servers_should_only_run_on_max_hosts_hosts_at_once
    cap1 = server("cap1")
    cap2 = server("cap2")
    connection1 = mock()
    connection2 = mock()
    connection1.expects(:close)
    connection2.expects(:close)
    list = [cap1, cap2]
    Capissh::SSH.expects(:connect).times(2).returns(connection1).then.returns(connection2)
    block_called = 0
    @connection_manager.execute_on_servers(list, :max_hosts => 1) do |servers|
      block_called += 1
      assert_equal 1, servers.size
    end
    assert_equal 2, block_called
  end

  def test_execute_on_servers_should_cope_with_already_dropped_connections_when_attempting_to_close_them
    cap1 = server("cap1")
    cap2 = server("cap2")
    connection1 = mock()
    connection2 = mock()
    connection3 = mock()
    connection4 = mock()
    connection1.expects(:close).raises(IOError)
    connection2.expects(:close)
    connection3.expects(:close)
    connection4.expects(:close)
    list = [cap1, cap2]
    Capissh::SSH.expects(:connect).times(4).returns(connection1).then.returns(connection2).then.returns(connection3).then.returns(connection4)
    @connection_manager.execute_on_servers(list, :max_hosts => 1) {}
    @connection_manager.execute_on_servers(list, :max_hosts => 1) {}
  end
end
