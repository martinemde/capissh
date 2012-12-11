require 'capissh/command'

module Capissh
  module Invocation
    def initialize(*args) #:nodoc:
      super
      @default_environment = {}
      @default_run_options = {}
    end

    # Executes different commands in parallel. This is useful for commands
    # that need to be different on different hosts, but which could be
    # otherwise run in parallel.
    #
    # The +options+ parameter is currently unused.
    #
    # Example:
    #
    #   task :restart_everything do
    #     parallel do |session|
    #       session.when "in?(:app)", "/path/to/restart/mongrel"
    #       session.when "in?(:web)", "/path/to/restart/apache"
    #       session.when "in?(:db)", "/path/to/restart/mysql"
    #     end
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
    # * +in?(role)+ returns true if the server participates in the given role
    # * +server+ is the ServerDefinition object for the server. This can be
    #   used to get the host-name, etc.
    # * +configuration+ is the current Capissh::Configuration object, which
    #   you can use to get the value of variables, etc.
    #
    # For example:
    #
    #   session.when "server.host =~ /app/", "/some/command"
    #   session.when "server.host == configuration[:some_var]", "/another/command"
    #   session.when "in?(:web) || in?(:app)", "/more/commands"
    #
    # See #run for a description of the valid +options+.
    def parallel(options={})
      raise ArgumentError, "parallel() requires a block" unless block_given?
      tree = Command::Tree.new(self) { |t| yield t }
      run_tree(tree, options)
    end

    # Invokes the given command. If a +via+ key is given, it will be used
    # to determine what method to use to invoke the command. It defaults
    # to :run, but may be :sudo, or any other method that conforms to the
    # same interface as run and sudo.
    def invoke_command(cmd, options={}, &block)
      options = options.dup
      via = options.delete(:via) || :run
      send(via, cmd, options, &block)
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
    # * :hosts - this is either a string (for a single target host) or an array
    #   of strings, indicating which hosts the command should run on. By default,
    #   the hosts are determined from the task definition.
    # * :roles - this is either a string or symbol (for a single target role) or
    #   an array of strings or symbols, indicating which roles the command should
    #   run on. If :hosts is specified, :roles will be ignored.
    # * :only - specifies a condition limiting which hosts will be selected to
    #   run the command. This should refer to values set in the role definition.
    #   For example, if a role is defined with :primary => true, then you could
    #   select only hosts with :primary true by setting :only => { :primary => true }.
    # * :except - specifies a condition limiting which hosts will be selected to
    #   run the command. This is the inverse of :only (hosts that do _not_ match
    #   the condition will be selected).
    # * :on_no_matching_servers - if :continue, will continue to execute tasks if
    #   no matching servers are found for the host criteria. The default is to raise
    #   a NoMatchingServersError exception.
    # * :once - if true, only the first matching server will be selected. The default
    #   is false (all matching servers will be selected).
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
    def run(cmd, options={}, &block)
      if options[:eof].nil? && !cmd.include?(sudo)
        options = options.merge(:eof => !block_given?)
      end
      block ||= Command.default_io_proc
      tree = Command::Tree.new(self) { |t| t.else(cmd, &block) }
      run_tree(tree, options)
    end

    # Executes a Capissh::Command::Tree object. This is not for direct
    # use, but should instead be called indirectly, via #run or #parallel,
    # or #invoke_command.
    def run_tree(tree, options={}) #:nodoc:
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

      return if dry_run || (debug && continue_execution(tree) == false)

      options = add_default_command_options(options)

      tree.each do |branch|
        if branch.command.include?(sudo)
          branch.callback = sudo_behavior_callback(branch.callback)
        end
      end

      execute_on_servers(options) do |servers| # FIXME: execute_on_servers
        targets = servers.map { |s| sessions[s] } # FIXME: sessions
        Command.process(tree, targets, options.merge(:logger => logger))
      end
    end

    # Returns the command string used by capissh to invoke a comamnd via
    # sudo.
    #
    #   run "#{sudo :as => 'bob'} mkdir /path/to/dir"
    #
    # It can also be invoked like #run, but executing the command via sudo.
    # This assumes that the sudo password (if required) is the same as the
    # password for logging in to the server.
    #
    #   sudo "mkdir /path/to/dir"
    #
    # Also, this method understands a <tt>:sudo</tt> configuration variable,
    # which (if specified) will be used as the full path to the sudo
    # executable on the remote machine:
    #
    #   set :sudo, "/opt/local/bin/sudo"
    #
    # If you know what you're doing, you can also set <tt>:sudo_prompt</tt>,
    # which tells capissh which prompt sudo should use when asking for
    # a password. (This is so that capissh knows what prompt to look for
    # in the output.) If you set :sudo_prompt to an empty string, Capissh
    # will not send a preferred prompt.
    def sudo(*parameters, &block)
      options = parameters.last.is_a?(Hash) ? parameters.pop.dup : {}
      command = parameters.first
      user = options[:as] && "-u #{options.delete(:as)}"

      sudo_prompt_option = "-p '#{sudo_prompt}'" unless sudo_prompt.empty?
      sudo_command = [fetch(:sudo, "sudo"), sudo_prompt_option, user].compact.join(" ")

      if command
        command = sudo_command + " " + command
        run(command, options, &block)
      else
        return sudo_command
      end
    end

    # Returns a Proc object that defines the behavior of the sudo
    # callback. The returned Proc will defer to the +fallback+ argument
    # (which should also be a Proc) for any output it does not
    # explicitly handle.
    def sudo_behavior_callback(fallback) #:nodoc:
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
          ch.send_data "#{@password}\n"
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
      defaults = @default_run_options
      options = defaults.merge(options)

      env = @default_environment
      env = env.merge(options[:env]) if options[:env]
      options[:env] = env unless env.empty?

      shell = options[:shell] || @default_shell
      options[:shell] = shell unless shell.nil?

      options
    end

    # Returns the prompt text to use with sudo
    def sudo_prompt
      fetch(:sudo_prompt, "sudo password: ")
    end

    def continue_execution(tree)
      if tree.branches.length == 1
        continue_execution_for_branch(tree.branches.first)
      else
        tree.each { |branch| branch.skip! unless continue_execution_for_branch(branch) }
        tree.any? { |branch| !branch.skip? }
      end
    end

    def continue_execution_for_branch(branch)
      case Capissh::CLI.debug_prompt(branch)
        when "y"
          true
        when "n"
          false
        when "a"
          exit(-1)
      end
    end
  end
end
