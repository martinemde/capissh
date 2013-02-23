require 'benchmark'
require 'capissh/errors'
require 'capissh/command/tree'

module Capissh

  # This class encapsulates a single command to be executed on a set of remote
  # machines, in parallel.
  class Command
    attr_reader :tree, :sessions, :options

    class << self
      attr_accessor :default_io_proc

      def process_tree(tree, sessions, options={})
        new(tree, options).call(sessions)
      end
      alias process process_tree

      # Convenience method to process a command given as a string
      # rather than a Command::Tree.
      def process_string(string, sessions, options={}, &block)
        tree = Tree.twig(nil, string, &block)
        process_tree(tree, sessions, options)
      end
    end

    self.default_io_proc = Proc.new do |ch, stream, out|
      if ch[:logger]
        level = stream == :err ? :important : :info
        ch[:logger].send(level, out, "#{stream} :: #{ch[:server]}")
      end
    end

    # Instantiates a new command object. The +command+ must be a string
    # containing the command to execute. +sessions+ is an array of Net::SSH
    # session instances, and +options+ must be a hash containing any of the
    # following keys:
    #
    # * +shell+: (optional), the shell (eg. 'bash') or false. Default: 'sh'
    # * +logger+: (optional), a Capissh::Logger instance
    # * +data+: (optional), a string to be sent to the command via it's stdin
    # * +eof+: (optional), close stdin after sending data
    # * +env+: (optional), a string or hash to be interpreted as environment
    #   variables that should be defined for this command invocation.
    # * +pty+: (optional), execute the command in a pty
    def initialize(tree, options={})
      @tree = tree
      @options = options
    end

    # Processes the command in parallel on all specified hosts. If the command
    # fails (non-zero return code) on any of the hosts, this will raise a
    # Capissh::CommandError.
    def call(sessions)
      channels = open_channels(sessions)

      elapsed = Benchmark.realtime do
        loop do
          active = sessions.process_iteration do
            channels.any? { |ch| !ch[:closed] }
          end
          break unless active
        end
      end

      logger.trace "command finished in #{(elapsed * 1000).round}ms" if logger

      failed = channels.select { |ch| ch[:status] != 0 }
      if failed.any?
        commands = failed.inject({}) do |map, ch|
          map[ch[:command]] ||= []
          map[ch[:command]] << ch[:server]
          map
        end
        message = commands.map do |command, list|
          "#{command.inspect} on #{list.join(',')}"
        end
        error = CommandError.new("failed: #{message.join("; ")}")
        error.hosts = commands.values.flatten
        raise error
      end

      self
    end

    private

      def logger
        options[:logger]
      end

      def open_channels(sessions)
        sessions.map do |session|
          server = session.xserver
          @tree.base_command_and_callback(server).map do |base_command, io_proc|
            session.open_channel do |channel|
              channel[:server] = server
              channel[:options] = options
              channel[:logger] = logger
              channel[:base_command] = base_command
              channel[:io_proc] = io_proc

              request_pty_if_necessary(channel) do |ch|
                logger.trace "executing command", ch[:server] if logger

                command_line = compose_command(channel[:base_command], channel[:server])
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

      def compose_command(command, server)
        command = command.strip.gsub(/\r?\n/, "\\\n")

        if options[:shell] == false
          shell = nil
        else
          shell = "#{options[:shell] || "sh"} -c"
          command = command.gsub(/'/) { |m| "'\\''" }
          command = "'#{command}'"
        end

        [environment, shell, command].compact.join(" ")
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
        @environment ||=
          if String === options[:env]
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
