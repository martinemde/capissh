require 'net/scp'
require 'net/sftp'

require 'capissh/errors'
require 'capissh/transfer/scp'
require 'capissh/transfer/sftp'

module Capissh
  class Transfer

    def self.process(direction, from, to, sessions, options={}, &block)
      new(direction, from, to, options, &block).call(sessions)
    end

    attr_reader :options
    attr_reader :callback

    attr_reader :transport
    attr_reader :direction
    attr_reader :from
    attr_reader :to

    attr_reader :logger

    def initialize(direction, from, to, options={}, &block)
      @direction = direction
      @from      = from
      @to        = to
      @options   = options
      @callback  = block
      @transport = options.fetch(:via, :sftp)
      @logger    = options[:logger]

      unless [:up,:down].include?(@direction)
        raise ArgumentError, "unsupported transfer direction: #{@direction.inspect}"
      end

      unless [:sftp,:scp].include?(@transport)
        raise ArgumentError, "unsupported transport type: #{@transport.inspect}"
      end
    end

    def intent
      "#{transport} #{operation} #{from} -> #{to}"
    end

    def call(sessions)
      session_map = {}
      transfers = sessions.map do |session|
        session_map[session] = prepare_transfer(session)
      end

      loop do
        begin
          active = sessions.process_iteration do
            transfers.any? { |transfer| transfer.active? }
          end
          break unless active
        rescue Exception => error
          raise error if error.message.include?('expected a file to upload')
          if error.respond_to?(:session)
            session_map[error.session].failed(error)
          else
            raise
          end
        end
      end

      failed = transfers.select { |transfer| transfer.failed? }
      if failed.any?
        hosts = failed.map { |transfer| transfer.server }
        errors = failed.map { |transfer| "#{transfer.error} (#{transfer.error.message})" }.uniq.join(", ")
        error = TransferError.new("#{operation} via #{transport} failed on #{hosts.join(',')}: #{errors}")
        error.hosts = hosts

        logger.important(error.message) if logger
        raise error
      end

      logger.debug "#{transport} #{operation} complete" if logger
      self
    end

    def operation
      "#{direction}load"
    end

    def sanitized_from
      from.responds_to?(:read) ? "#<#{from.class}>" : from
    end

    def sanitized_to
      to.responds_to?(:read) ? "#<#{to.class}>" : to
    end

    private

      def transfer_class
        {
          :sftp => Transfer::SFTP,
          :scp  => Transfer::SCP,
        }
      end

      def prepare_transfer(session)
        session_from = normalize(from, session)
        session_to   = normalize(to,   session)
        transfer = transfer_class[transport].new(direction, session_from, session_to, session, options, &callback)
        transfer.prepare
        transfer
      end

      def normalize(argument, session)
        if argument.is_a?(String)
          Configuration.default_placeholder_callback.call(argument, session.xserver)
        elsif argument.respond_to?(:read)
          pos = argument.pos
          clone = StringIO.new(argument.read)
          clone.pos = argument.pos = pos
          clone
        else
          argument
        end
      end
  end
end
