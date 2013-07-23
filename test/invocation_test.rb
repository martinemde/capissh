require "test_helper"
require 'capissh/configuration'

class InvocationTest < Minitest::Test
  def setup
    @logger = stub_everything
    @configuration = Capissh::Configuration.new(:logger => @logger)
    @invocation = Capissh::Invocation.new(@configuration, @logger)
    @original_io_proc = Capissh::Command.default_io_proc
    @servers = [server('cap1'), server('cap2')]
  end

  def teardown
    Capissh::Command.default_io_proc = @original_io_proc
  end

  def test_run_options_should_be_passed_to_execute_on_servers
    prepare_command('ls', [:a,:b], {:foo => "bar", :eof => true, :logger => @logger})
    @configuration.expects(:execute_on_servers).with(@servers, :foo => "bar", :eof => true).yields([:a,:b])
    @invocation.run @servers, "ls", :foo => "bar"
  end

  def test_run_will_return_if_dry_run
    @configuration.expects(:execute_on_servers)
    command = mock('command')
    command.expects(:call).never
    Capissh::Command.expects(:new).returns(command)
    @invocation.run @servers, "ls", :foo => "bar"
  end

  def test_add_default_command_options_should_return_bare_options_if_there_is_no_env_or_shell_specified
    assert_equal({:foo => "bar"}, @invocation.add_default_command_options(:foo => "bar"))
  end

  def test_add_default_command_options_should_merge_default_environment_as_env
    @configuration[:default_environment][:bang] = "baz"
    assert_equal({:foo => "bar", :env => { :bang => "baz" }}, @invocation.add_default_command_options(:foo => "bar"))
  end

  def test_add_default_command_options_should_merge_env_with_default_environment
    @configuration[:default_environment][:bang] = "baz"
    @configuration[:default_environment][:bacon] = "crunchy"
    assert_equal({:foo => "bar", :env => { :bang => "baz", :bacon => "chunky", :flip => "flop" }}, @invocation.add_default_command_options(:foo => "bar", :env => {:bacon => "chunky", :flip => "flop"}))
  end

  def test_add_default_command_options_should_use_default_shell_if_present
    @configuration.set :default_shell, "/bin/bash"
    assert_equal({:foo => "bar", :shell => "/bin/bash"}, @invocation.add_default_command_options(:foo => "bar"))
  end

  def test_add_default_command_options_should_use_default_shell_of_false_if_present
    @configuration.set :default_shell, false
    assert_equal({:foo => "bar", :shell => false}, @invocation.add_default_command_options(:foo => "bar"))
  end

  def test_add_default_command_options_should_use_shell_in_preference_of_default_shell
    @configuration.set :default_shell, "/bin/bash"
    assert_equal({:foo => "bar", :shell => "/bin/sh"}, @invocation.add_default_command_options(:foo => "bar", :shell => "/bin/sh"))
  end

  def test_default_io_proc_should_log_stdout_arguments_as_info
    ch = { :host => "capissh",
           :server => server("capissh"),
           :logger => mock("logger") }
    ch[:logger].expects(:info).with("data stuff", "out :: capissh")
    Capissh::Command.default_io_proc[ch, :out, "data stuff"]
  end

  def test_default_io_proc_should_log_stderr_arguments_as_important
    ch = { :host => "capissh",
           :server => server("capissh"),
           :logger => mock("logger") }
    ch[:logger].expects(:important).with("data stuff", "err :: capissh")
    Capissh::Command.default_io_proc[ch, :err, "data stuff"]
  end

  def test_sudo_should_default_to_sudo
    @invocation.expects(:run).with(@servers, "sudo -p 'sudo password: ' ls", {})
    @invocation.sudo @servers, "ls"
  end

  def test_sudo_should_keep_input_stream_open
    @configuration.expects(:execute_on_servers).with(@servers, :foo => "bar")
    @invocation.sudo @servers, "ls", :foo => "bar"
  end

  def test_sudo_should_use_sudo_variable_definition
    @invocation.expects(:run).with(@servers, "/opt/local/bin/sudo -p 'sudo password: ' ls", {})
    @configuration.set :sudo, "/opt/local/bin/sudo"
    @invocation.sudo @servers, "ls"
  end

  def test_sudo_should_interpret_as_option_as_user
    @invocation.expects(:run).with(@servers, "sudo -p 'sudo password: ' -u app ls", {})
    @invocation.sudo @servers, "ls", :as => "app"
  end

  def test_sudo_should_pass_options_through_to_run
    @invocation.expects(:run).with(@servers, "sudo -p 'sudo password: ' ls", :foo => "bar")
    @invocation.sudo @servers, "ls", :foo => "bar"
  end

  def test_sudo_should_avoid_minus_p_when_sudo_prompt_is_empty
    @configuration.set :sudo_prompt, ""
    @invocation.expects(:run).with(@servers, "sudo ls", {})
    @invocation.sudo @servers, "ls"
  end

  def test_sudo_should_interpret_sudo_prompt_variable_as_custom_prompt
    @configuration.set :sudo_prompt, "give it to me: "
    @invocation.expects(:run).with(@servers, "sudo -p 'give it to me: ' ls", {})
    @invocation.sudo @servers, "ls"
  end

  def test_sudo_behavior_callback_should_send_password_when_prompted_with_default_sudo_prompt
    ch = mock("channel")
    ch.expects(:send_data).with("g00b3r\n")
    @configuration.options[:password] = "g00b3r"
    @invocation.sudo_behavior_callback(nil)[ch, nil, "sudo password: "]
  end

  def test_sudo_behavior_callback_should_send_password_when_prompted_with_custom_sudo_prompt
    ch = mock("channel")
    ch.expects(:send_data).with("g00b3r\n")
    @configuration.set :sudo_prompt, "give it to me: "
    @configuration.options[:password] = "g00b3r"
    @invocation.sudo_behavior_callback(nil)[ch, nil, "give it to me: "]
  end

  def test_sudo_behavior_callback_with_incorrect_password_on_first_prompt
    ch = mock("channel")
    ch.stubs(:[]).with(:host).returns("capissh")
    ch.stubs(:[]).with(:server).returns(server("capissh"))
    @configuration.expects(:reset!).with(:password)
    @invocation.sudo_behavior_callback(nil)[ch, nil, "Sorry, try again."]
  end

  def test_sudo_behavior_callback_with_incorrect_password_on_subsequent_prompts
    callback = @invocation.sudo_behavior_callback(nil)

    ch = mock("channel")
    ch.stubs(:[]).with(:host).returns("capissh")
    ch.stubs(:[]).with(:server).returns(server("capissh"))
    ch2 = mock("channel")
    ch2.stubs(:[]).with(:host).returns("cap2")
    ch2.stubs(:[]).with(:server).returns(server("cap2"))

    @configuration.expects(:reset!).with(:password).times(2)

    callback[ch, nil, "Sorry, try again."]
    callback[ch2, nil, "Sorry, try again."] # shouldn't call reset!
    callback[ch, nil, "Sorry, try again."]
  end

  def test_sudo_behavior_callback_should_reset_password_and_prompt_again_if_output_includes_both_cues
    ch = mock("channel")
    ch.stubs(:[]).with(:host).returns("capissh")
    ch.stubs(:[]).with(:server).returns(server("capissh"))
    ch.expects(:send_data, "password!\n").times(2)

    @configuration.set(:password, "password!")
    @configuration.expects(:reset!).with(:password)

    callback = @invocation.sudo_behavior_callback(nil)
    callback[ch, :out, "sudo password: "]
    callback[ch, :out, "Sorry, try again.\nsudo password: "]
  end

  def test_sudo_behavior_callback_should_defer_to_fallback_for_other_output
    inspectable_proc = Proc.new do |ch, stream, data|
      ch.called
      stream.called
      data.called
    end

    callback = @invocation.sudo_behavior_callback(inspectable_proc)

    a = mock("channel", :called => true)
    b = mock("stream", :called => true)
    c = mock("data", :called => true)

    callback[a, b, c]
  end

  def test_invoke_command_should_default_to_run
    @invocation.expects(:run).with(@servers, "ls", :continue_on_error => true)
    @invocation.invoke_command(@servers, "ls", :continue_on_error => true)
  end

  def test_invoke_command_should_delegate_to_method_identified_by_via
    @invocation.expects(:sudo).with(@servers, "ls", :continue_on_error => true)
    @invocation.invoke_command(@servers, "ls", :continue_on_error => true, :via => :sudo)
  end

  private

    def prepare_command(cmd, sessions, options)
      command = mock('command')
      command.expects(:call).with(sessions)
      Capissh::Command.expects(:new).returns(command).with do |tree, opts|
        tree.fallback.command == cmd && opts == options
      end
    end
end
