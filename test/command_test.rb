require "test_helper"
require 'capissh/command'
require 'capissh/configuration'

class CommandTest < MiniTest::Unit::TestCase
  def tree(cmd, options={}, &block)
    Capissh::Command::Tree.twig(nil, cmd, options, &block)
  end

  def test_command_should_open_channels_on_all_sessions
    assert_equal "ls", Capissh::Command.new(tree("ls")).tree.fallback.command
  end

  def test_command_with_newlines_should_be_properly_escaped
    cmd = Capissh::Command.new(tree("ls\necho"))
    assert_equal "ls\\\necho", cmd.tree.fallback.command
  end

  def test_command_with_windows_newlines_should_be_properly_escaped
    cmd = Capissh::Command.new(tree("ls\r\necho"))
    assert_equal "ls\\\necho", cmd.tree.fallback.command
  end

  def test_command_with_pty_should_request_pty_and_register_success_callback
    sessions = setup_for_extracting_channel_action(:request_pty, true) do |ch|
      ch.expects(:exec).with(%(sh -c 'ls'))
    end
    Capissh::Command.new(tree("ls"), :pty => true).call(sessions)
  end

  def test_command_with_env_key_should_have_environment_constructed_and_prepended
    sessions = setup_for_extracting_channel_action do |ch|
      ch.expects(:request_pty).never
      ch.expects(:exec).with(%(env FOO=bar sh -c 'ls'))
    end
    Capissh::Command.new(tree("ls", :env => { "FOO" => "bar" })).call(sessions)
  end

  def test_env_with_symbolic_key_should_be_accepted_as_a_string
    sessions = setup_for_extracting_channel_action do |ch|
      ch.expects(:exec).with(%(env FOO=bar sh -c 'ls'))
    end
    Capissh::Command.new(tree("ls", :env => { :FOO => "bar" })).call(sessions)
  end

  def test_env_as_string_should_be_substituted_in_directly
    sessions = setup_for_extracting_channel_action do |ch|
      ch.expects(:exec).with(%(env HOWDY=there sh -c 'ls'))
    end
    Capissh::Command.new(tree("ls", :env => "HOWDY=there")).call(sessions)
  end

  def test_env_with_symbolic_value_should_be_accepted_as_string
    sessions = setup_for_extracting_channel_action do |ch|
      ch.expects(:exec).with(%(env FOO=bar sh -c 'ls'))
    end
    Capissh::Command.new(tree("ls", :env => { "FOO" => :bar })).call(sessions)
  end

  def test_env_value_should_be_escaped
    sessions = setup_for_extracting_channel_action do |ch|
      ch.expects(:exec).with(%(env FOO=(\\ \\\"bar\\\"\\ ) sh -c 'ls'))
    end
    Capissh::Command.new(tree("ls", :env => { "FOO" => '( "bar" )' })).call(sessions)
  end

  def test_env_with_multiple_keys_should_chain_the_entries_together
    sessions = setup_for_extracting_channel_action do |ch|
      ch.expects(:exec).with do |command|
        command =~ /^env / &&
        command =~ /\ba=b\b/ &&
        command =~ /\bc=d\b/ &&
        command =~ /\be=f\b/ &&
        command =~ / sh -c 'ls'$/
      end
    end
    Capissh::Command.new(tree("ls", :env => { :a => :b, :c => :d, :e => :f })).call(sessions)
  end

  def test_open_channel_should_set_server_key_on_channel
    channel = nil
    sessions = setup_for_extracting_channel_action { |ch| channel = ch }
    Capissh::Command.new(tree("ls")).call(sessions)
    assert_equal "capissh", channel[:server].host
  end

  def test_open_channel_should_set_options_key_on_channel
    channel = nil
    sessions = setup_for_extracting_channel_action { |ch| channel = ch }
    Capissh::Command.new(tree("ls"), :data => "here we go").call(sessions)
    assert_equal({ :data => 'here we go' }, channel[:options])
  end

  def test_successful_channel_should_send_command
    sessions = setup_for_extracting_channel_action do |ch|
      ch.expects(:exec).with(%(sh -c 'ls'))
    end
    Capissh::Command.new(tree("ls")).call(sessions)
  end

  def test_successful_channel_with_shell_option_should_send_command_via_specified_shell
    sessions = setup_for_extracting_channel_action do |ch|
      ch.expects(:exec).with(%(/bin/bash -c 'ls'))
    end
    Capissh::Command.new(tree("ls", :shell => "/bin/bash")).call(sessions)
  end

  def test_successful_channel_with_shell_false_should_send_command_without_shell
    sessions = setup_for_extracting_channel_action do |ch|
      ch.expects(:exec).with(%(echo `hostname`))
    end
    Capissh::Command.new(tree("echo `hostname`", :shell => false)).call(sessions)
  end

  def test_successful_channel_should_send_data_if_data_key_is_present
    sessions = setup_for_extracting_channel_action do |ch|
      ch.expects(:exec).with(%(sh -c 'ls'))
      ch.expects(:send_data).with("here we go")
    end
    Capissh::Command.new(tree("ls"), :data => "here we go").call(sessions)
  end

  def test_unsuccessful_pty_request_should_close_channel
    sessions = setup_for_extracting_channel_action(:request_pty, false) do |ch|
      ch.expects(:close)
    end
    Capissh::Command.new(tree("ls"), :pty => true).call(sessions)
  end

  def test_on_data_should_invoke_callback_as_stdout
    sessions = setup_for_extracting_channel_action(:on_data, "hello")
    called = false
    twig = tree("ls") do |ch, stream, data|
      called = true
      assert_equal :out, stream
      assert_equal "hello", data
    end
    Capissh::Command.new(twig).call(sessions)
    assert called, "expected to yield output to io block"
  end

  def test_on_extended_data_should_invoke_callback_as_stderr
    sessions = setup_for_extracting_channel_action(:on_extended_data, 2, "hello")
    called = false
    twig = tree("ls") do |ch, stream, data|
      called = true
      assert_equal :err, stream
      assert_equal "hello", data
    end
    Capissh::Command.new(twig).call(sessions)
    assert called, "expected to yield output to io block"
  end

  def test_on_request_should_record_exit_status
    data = mock(:read_long => 5)
    channel = nil
    sessions = setup_for_extracting_channel_action([:on_request, "exit-status"], data) { |ch| channel = ch }
    assert_raises(Capissh::CommandError, %|failed: "sh -c 'ls'" on capissh|) { Capissh::Command.new(tree("ls")).call(sessions) }
    assert_equal 5, channel[:status]
  end

  def test_on_close_should_set_channel_closed
    channel = nil
    sessions = setup_for_extracting_channel_action(:on_close) { |ch| channel = ch }
    Capissh::Command.new(tree("ls")).call(sessions)
    assert channel[:closed]
  end

  def test_process_should_return_cleanly_if_all_channels_have_zero_exit_status
    sessions = MockSessions.new [
      mock_session(new_channel(true, 0)),
      mock_session(new_channel(true, 0)),
      mock_session(new_channel(true, 0))
    ]
    Capissh::Command.new(tree("ls")).call(sessions)
  end

  def test_process_should_raise_error_if_any_channel_has_non_zero_exit_status
    sessions = MockSessions.new [
      mock_session(new_channel(true, 0)),
      mock_session(new_channel(true, 0)),
      mock_session(new_channel(true, 1))
    ]
    cmd = Capissh::Command.new(tree("ls"))
    assert_raises(Capissh::CommandError) { cmd.call(sessions) }
  end

  def test_command_error_should_include_accessor_with_host_array
    sessions = MockSessions.new [
      mock_session(new_channel(true, 0)),
      mock_session(new_channel(true, 0)),
      mock_session(new_channel(true, 1))
    ]
    cmd = Capissh::Command.new(tree("ls"))

    begin
      cmd.call(sessions)
      flunk "expected an exception to be raised"
    rescue Capissh::CommandError => e
      assert e.respond_to?(:hosts)
      assert_equal %w(capissh), e.hosts.map { |h| h.to_s }
    end
  end

  def test_process_should_loop_until_all_channels_are_closed
    new_channel = Proc.new do |times|
      ch = mock("channel")
      returns = [false] * (times-1)
      ch.stubs(:to_ary)
      ch.stubs(:[]).with(:closed).returns(*(returns + [true]))
      ch.expects(:[]).with(:status).returns(0)
      ch
    end

    sessions = MockSessions.new [
      mock_session(new_channel[5]),
      mock_session(new_channel[10]),
      mock_session(new_channel[7])
    ]
    Capissh::Command.new(tree("ls")).call(sessions)
  end

  def test_process_should_instantiate_command_and_call
    cmd = mock("command")
    cmd.expects(:call).with(%w(a b c)).returns(nil)
    twig = tree("ls -l")
    Capissh::Command.expects(:new).with(twig, {:foo => "bar"}).returns(cmd)
    Capissh::Command.process(twig, %w(a b c), :foo => "bar")
  end

  def test_input_stream_closed_when_eof_option_is_true
    channel = nil
    sessions = setup_for_extracting_channel_action { |ch| channel = ch }
    channel.expects(:eof!)
    Capissh::Command.new(tree("cat"), :data => "here we go", :eof => true).call(sessions)
    assert_equal({ :data => 'here we go', :eof => true }, channel[:options])
  end

  private

    def mock_session(channel=nil)
      channel ||= new_channel(true, 0)
      stub('session',
           :open_channel => channel,
           :preprocess   => true,
           :postprocess  => true,
           :listeners    => {},
           :xserver      => server("capissh"))
    end

    class MockChannel < Hash
      def close
      end
    end

    def new_channel(closed, status=nil)
      ch = MockChannel.new
      ch.update({ :closed => closed, :host => "capissh", :server => server("capissh") })
      ch[:status] = status if status
      ch.expects(:close) unless closed
      ch
    end

    class MockSessions < Array
      def process_iteration
        yield
      end
    end

    def setup_for_extracting_channel_action(action=nil, *args)
      s = server("capissh")
      session = mock("session", :xserver => s)

      channel = {:failed => false, :closed => true, :status => 0}
      session.expects(:open_channel).yields(channel).returns(channel)

      channel.stubs(:on_data)
      channel.stubs(:on_extended_data)
      channel.stubs(:on_request)
      channel.stubs(:on_close)
      channel.stubs(:exec)
      channel.stubs(:send_data)

      if action
        action = Array(action)
        channel.expects(action.first).with(*action[1..-1]).yields(channel, *args)
      end

      yield channel if block_given?

      sessions = [session]
      sessions.stubs(:process_iteration).yields.returns(false)
      sessions
    end
end
