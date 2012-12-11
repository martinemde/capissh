require 'benchmark'
require 'capissh/errors'
require 'capissh/processable'
require 'capissh/command/tree'

module Capissh

  # This class encapsulates a single command to be executed on a set of remote
  # machines, in parallel.
  class Command
    include Processable

    attr_reader :tree, :sessions, :options

    class << self
      attr_accessor :default_io_proc
    end

    self.default_io_proc = Proc.new do |ch, stream, out|
      level = stream == :err ? :important : :info
      ch[:options][:logger].send(level, out, "#{stream} :: #{ch[:server]}")
    end

    def self.process(tree, sessions, options={})
      new(tree, sessions, options).process!
    end

    # Instantiates a new command object. The +command+ must be a string
    # containing the command to execute. +sessions+ is an array of Net::SSH
    # session instances, and +options+ must be a hash containing any of the
    # following keys:
    #
    # * +shell+: (optional), the shell command string (eg. 'bash') or false
    # * +logger+: (optional), a Capissh::Logger instance
    # * +data+: (optional), a string to be sent to the command via it's stdin
    # * +eof+: (optional), close stdin after sending data
    # * +env+: (optional), a string or hash to be interpreted as environment
    #   variables that should be defined for this command invocation.
    # * +pty+: (optional), execute the command in a pty
    def initialize(tree, sessions, options={}, &block)
      if String === tree
        @command_callback_pairs = lambda { |server| [[tree, block || self.class.default_io_proc]] }
      elsif block
        raise ArgumentError, "block given with tree argument"
      else
        @command_callback_pairs = lambda { |server| tree.branches_for(server).map { |branch| [branch.command, branch.callback] } }
      end

      @role_names = lambda { |server| tree.respond_to?(:configuration) && tree.configuration && tree.configuration.role_names_for_host(server).join(',') }
      @sessions = sessions
      @options = options
      @channels = open_channels
    end

    # Processes the command in parallel on all specified hosts. If the command
    # fails (non-zero return code) on any of the hosts, this will raise a
    # Capissh::CommandError.
    def process!
      elapsed = Benchmark.realtime do
        loop do
          break unless process_iteration { @channels.any? { |ch| !ch[:closed] } }
        end
      end

      logger.trace "command finished in #{(elapsed * 1000).round}ms" if logger

      if (failed = @channels.select { |ch| ch[:status] != 0 }).any?
        commands = failed.inject({}) { |map, ch| (map[ch[:command]] ||= []) << ch[:server]; map }
        message = commands.map { |command, list| "#{command.inspect} on #{list.join(',')}" }.join("; ")
        error = CommandError.new("failed: #{message}")
        error.hosts = commands.values.flatten
        raise error
      end

      self
    end

    # Force the command to stop processing, by closing all open channels
    # associated with this command.
    def stop!
      @channels.each do |ch|
        ch.close unless ch[:closed]
      end
    end

    private

      def logger
        options[:logger]
      end

      def open_channels
        sessions.map do |session|
          server = session.xserver
          @command_callback_pairs.call(server).map do |base_command, io_proc|
            session.open_channel do |channel|
              channel[:server] = server
              channel[:host] = server.host
              channel[:options] = options
              channel[:base_command] = base_command
              channel[:io_proc] = io_proc

              request_pty_if_necessary(channel) do |ch|
                logger.trace "executing command", ch[:server] if logger

                command_line = make_command(channel[:base_command], channel[:server], channel[:host])
                channel[:command] = command_line

                ch.exec(command_line)
                ch.send_data(options[:data]) if options[:data]
                ch.eof! if options[:eof]
              end

              channel.on_data do |ch, data|
                ch[:io_proc].call(ch, :out, data)
              end

              channel.on_extended_data do |ch, type, data|
                ch[:io_proc].call(ch, :err, data)
              end

              channel.on_request("exit-status") do |ch, data|
                ch[:status] = data.read_long
              end

              channel.on_close do |ch|
                ch[:closed] = true
              end
            end
          end
        end.flatten
      end

      def request_pty_if_necessary(channel)
        if options[:pty]
          channel.request_pty do |ch, success|
            if success
              yield ch
            else
              # just log it, don't actually raise an exception, since the
              # process method will see that the status is not zero and will
              # raise an exception then.
              logger.important "could not open channel", ch[:server] if logger
              ch.close
            end
          end
        else
          yield channel
        end
      end

      def make_command(base_command, server, host)
        cmd = replace_placeholders(base_command, server, host)

        if options[:shell] == false
          shell = nil
        else
          shell = "#{options[:shell] || "sh"} -c"
          cmd = cmd.gsub(/'/) { |m| "'\\''" }
          cmd = "'#{cmd}'"
        end

        [environment, shell, cmd].compact.join(" ")
      end

      def replace_placeholders(command, server, host)
        roles = @role_names && @role_names.call(server)
        command = command.gsub(/\$CAPISTRANO:HOST\$/, host)
        command.gsub!(/\$CAPISTRANO:HOSTROLES\$/, roles) if roles
        command
      end

      # prepare a space-separated sequence of variables assignments
      # intended to be prepended to a command, so the shell sets
      # the environment before running the command.
      # i.e.: options[:env] = {'PATH' => '/opt/ruby/bin:$PATH',
      #                        'TEST' => '( "quoted" )'}
      # environment returns:
      # "env TEST=(\ \"quoted\"\ ) PATH=/opt/ruby/bin:$PATH"
      def environment
        return if options[:env].nil? || options[:env].empty?
        @environment ||= if String === options[:env]
            "env #{options[:env]}"
          else
            options[:env].inject("env") do |string, (name, value)|
              value = value.to_s.gsub(/[ "]/) { |m| "\\#{m}" }
              string << " #{name}=#{value}"
            end
          end
      end
  end
end
