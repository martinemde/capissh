require 'capissh/command'

module Capissh
  class Invocation
    attr_reader :configuration, :logger

    def initialize(configuration, logger)
      @configuration = configuration
      @logger = logger
    end

    # Executes different commands in parallel. This is useful for commands
    # that need to be different on different hosts, but which could be
    # otherwise run in parallel.
    #
    # The +options+ parameter is currently unused.
    #
    # Example:
    #
    #   parallel do |session|
    #     session.when "in?(:app)", "/path/to/restart/mongrel"
    #     session.when "in?(:web)", "/path/to/restart/apache"
    #     session.when "in?(:db)", "/path/to/restart/mysql"
    #   end
    #
    # Each command may have its own callback block, for capturing and
    # responding to output, with semantics identical to #run:
    #
    #   session.when "in?(:app)", "/path/to/restart/mongrel" do |ch, stream, data|
    #     # ch is the SSH channel for this command, used to send data
    #     #    back to the command (e.g. ch.send_data("password\n"))
    #     # stream is either :out or :err, for which stream the data arrived on
    #     # data is a string containing data sent from the remote command
    #   end
    #
    # Also, you can specify a fallback command, to use when none of the
    # conditions match a server:
    #
    #   session.else "/execute/something/else"
    #
    # The string specified as the first argument to +when+ may be any valid
    # Ruby code. It has access to the following variables and methods:
    #
    # * +server+ is the ServerDefinition object for the server. This can be
    #   used to get the host-name, etc.
    # * +configuration+ is the current Capissh::Configuration object, which
    #   you can use to get the value of variables, etc.
    #
    # For example:
    #
    #   session.when "server.host =~ /app/", "/some/command"
    #   session.when "server.host == configuration[:some_var]", "/another/command"
    #   session.when "server.role?(:web) || server.role?(:app)", "/more/commands"
    #
    # See #run for a description of the valid +options+.
    def parallel(servers, options={})
      raise ArgumentError, "parallel() requires a block" unless block_given?
      tree = CommandTree.new(configuration, options) { |t| yield t }
      run_tree(servers, tree, options)
    end

    # Invokes the given command. If a +via+ key is given, it will be used
    # to determine what method to use to invoke the command. It defaults
    # to :run, but may be :sudo, or any other method that conforms to the
    # same interface as run and sudo.
    def invoke_command(servers, cmd, options={}, &block)
      options = options.dup
      via = options.delete(:via) || :run
      send(via, servers, cmd, options, &block)
    end

    # Execute the given command on all servers that are the target of the
    # current task. If a block is given, it is invoked for all output
    # generated by the command, and should accept three parameters: the SSH
    # channel (which may be used to send data back to the remote process),
    # the stream identifier (<tt>:err</tt> for stderr, and <tt>:out</tt> for
    # stdout), and the data that was received.
    #
    # The +options+ hash may include any of the following keys:
    #
    # * :on_no_matching_servers - if :continue, will continue to execute tasks if
    #   no matching servers are found for the host criteria. The default is to raise
    #   a NoMatchingServersError exception.
    # * :max_hosts - specifies the maximum number of hosts that should be selected
    #   at a time. If this value is less than the number of hosts that are selected
    #   to run, then the hosts will be run in groups of max_hosts. The default is nil,
    #   which indicates that there is no maximum host limit. Please note this does not
    #   limit the number of SSH channels that can be open, only the number of hosts upon
    #   which this will be called.
    # * :shell - says which shell should be used to invoke commands. This
    #   defaults to "sh". Setting this to false causes Capissh to invoke
    #   the commands directly, without wrapping them in a shell invocation.
    # * :data - if not nil (the default), this should be a string that will
    #   be passed to the command's stdin stream.
    # * :pty - if true, a pseudo-tty will be allocated for each command. The
    #   default is false. Note that there are benefits and drawbacks both ways.
    #   Empirically, it appears that if a pty is allocated, the SSH server daemon
    #   will _not_ read user shell start-up scripts (e.g. bashrc, etc.). However,
    #   if a pty is _not_ allocated, some commands will refuse to run in
    #   interactive mode and will not prompt for (e.g.) passwords.
    # * :env - a hash of environment variable mappings that should be made
    #   available to the command. The keys should be environment variable names,
    #   and the values should be their corresponding values. The default is
    #   empty, but may be modified by changing the +default_environment+
    #   Capissh variable.
    # * :eof - if true, the standard input stream will be closed after sending
    #   any data specified in the :data option. If false, the input stream is
    #   left open. The default is to close the input stream only if no block is
    #   passed.
    #
    # Note that if you set these keys in the +default_run_options+ Capissh
    # variable, they will apply for all invocations of #run, #invoke_command,
    # and #parallel.
    def run(servers, cmd, options={}, &block)
      if options[:eof].nil? && !cmd.include?(sudo_command)
        options = options.merge(:eof => !block_given?)
      end
      block ||= Command.default_io_proc
      tree = CommandTree.twig(configuration, cmd, options, &block)
      run_tree(servers, tree, options)
    end

    # Executes a Capissh::CommandTree object. This is not for direct
    # use, but should instead be called indirectly, via #run or #parallel,
    # or #invoke_command.
    def run_tree(servers, tree, options={})
      if tree.branches.empty? && tree.fallback
        logger.debug "executing #{tree.fallback}" unless options[:silent]
      elsif tree.branches.any?
        logger.debug "executing multiple commands in parallel"
        tree.each do |branch|
          logger.trace "-> #{branch}"
        end
      else
        raise ArgumentError, "attempt to execute without specifying a command"
      end

      options = add_default_command_options(options)

      tree.each do |branch|
        if branch.command.include?(sudo_command)
          branch.callback = sudo_behavior_callback(branch.callback)
        end
      end

      command = Command.new(tree, options.merge(:logger => logger))

      configuration.execute_on_servers(servers, options) do |sessions|
        command.call(sessions)
      end
    end

    # Invoked like #run, but executing the command via sudo.
    # This assumes that the sudo password (if required) is the same as the
    # password for logging in to the server.
    #
    #   sudo "mkdir /path/to/dir"
    #
    # Also, this method understands a <tt>:sudo</tt> configuration variable,
    # which (if specified) will be used as the full path to the sudo
    # executable on the remote machine:
    #
    #   Capissh.new(sudo: "/opt/local/bin/sudo")
    #
    # If you know what you're doing, you can also set <tt>:sudo_prompt</tt>,
    # which tells capissh which prompt sudo should use when asking for
    # a password. (This is so that capissh knows what prompt to look for
    # in the output.) If you set :sudo_prompt to an empty string, Capissh
    # will not send a preferred prompt.
    def sudo(servers, command, options={}, &block)
      run(servers, "#{sudo_command(options)} #{command}", options, &block)
    end

    # Returns the command string used by capissh to invoke a comamnd via
    # sudo.
    #
    #   run "#{sudo_command :as => 'bob'} mkdir /path/to/dir"
    #
    # Also, this method understands a <tt>:sudo</tt> configuration variable,
    # which (if specified) will be used as the full path to the sudo
    # executable on the remote machine:
    #
    #   Capissh.new(sudo: "/opt/local/bin/sudo")
    #
    # If you know what you're doing, you can also set <tt>:sudo_prompt</tt>,
    # which tells capissh which prompt sudo should use when asking for
    # a password. (This is so that capissh knows what prompt to look for
    # in the output.) If you set :sudo_prompt to an empty string, Capissh
    # will not send a preferred prompt.
    def sudo_command(options={}, &block)
      user = options[:as] && "-u #{options.delete(:as)}"

      sudo_prompt_option = "-p '#{sudo_prompt}'" unless sudo_prompt.empty?
      [configuration.fetch(:sudo, "sudo"), sudo_prompt_option, user].compact.join(" ")
    end

    # tests are too invasive right now
    # protected

    # Returns a Proc object that defines the behavior of the sudo
    # callback. The returned Proc will defer to the +fallback+ argument
    # (which should also be a Proc) for any output it does not
    # explicitly handle.
    def sudo_behavior_callback(fallback)
      # in order to prevent _each host_ from prompting when the password
      # was wrong, let's track which host prompted first and only allow
      # subsequent prompts from that host.
      prompt_host = nil

      Proc.new do |ch, stream, out|
        if out =~ /^Sorry, try again/
          if prompt_host.nil? || prompt_host == ch[:server]
            prompt_host = ch[:server]
            logger.important out, "#{stream} :: #{ch[:server]}"
            reset! :password
          end
        end

        if out =~ /^#{Regexp.escape(sudo_prompt)}/
          ch.send_data "#{configuration.fetch(:password,nil)}\n"
        elsif fallback
          fallback.call(ch, stream, out)
        end
      end
    end

    # Merges the various default command options into the options hash and
    # returns the result. The default command options that are understand
    # are:
    #
    # * :default_environment: If the :env key already exists, the :env
    #   key is merged into default_environment and then added back into
    #   options.
    # * :default_shell: if the :shell key already exists, it will be used.
    #   Otherwise, if the :default_shell key exists in the configuration,
    #   it will be used. Otherwise, no :shell key is added.
    def add_default_command_options(options)
      defaults = configuration.fetch(:default_run_options, {})
      options = defaults.merge(options)

      env = configuration.fetch(:default_environment, {})
      env = env.merge(options[:env]) if options[:env]
      options[:env] = env unless env.empty?

      shell = options[:shell] || configuration.fetch(:default_shell, nil)
      options[:shell] = shell unless shell.nil?

      options
    end

    # Returns the prompt text to use with sudo
    def sudo_prompt
      configuration.fetch(:sudo_prompt, "sudo password: ")
    end

  end
end
