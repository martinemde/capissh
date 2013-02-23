require 'net/scp'
require 'net/sftp'

require 'capissh/errors'

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
      @logger    = options.delete(:logger)
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
          if error.respond_to?(:session)
            transfer = session_map[error.session]
            handle_error(transfer, error)
          else
            raise
          end
        end
      end

      failed = transfers.select { |txfr| txfr[:failed] }
      if failed.any?
        hosts = failed.map { |txfr| txfr[:server] }
        errors = failed.map { |txfr| "#{txfr[:error]} (#{txfr[:error].message})" }.uniq.join(", ")
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
      if from.responds_to?(:read)
        "#<#{from.class}>"
      else
        from
      end
    end

    def sanitized_to
      if to.responds_to?(:read)
        "#<#{to.class}>"
      else
        to
      end
    end

    private

      def prepare_transfer(session)
        session_from = normalize(from, session)
        session_to   = normalize(to, session)

        case transport
        when :sftp
          prepare_sftp_transfer(session_from, session_to, session)
        when :scp
          prepare_scp_transfer(session_from, session_to, session)
        else
          raise ArgumentError, "unsupported transport type: #{transport.inspect}"
        end
      end

      def prepare_scp_transfer(from, to, session)
        real_callback = callback || Proc.new do |channel, name, sent, total|
          logger.trace "[#{channel[:host]}] #{name}" if logger && sent == 0
        end

        channel = case direction
          when :up
            session.scp.upload(from, to, options, &real_callback)
          when :down
            session.scp.download(from, to, options, &real_callback)
          else
            raise ArgumentError, "unsupported transfer direction: #{direction.inspect}"
          end

        channel[:server] = session.xserver
        channel[:host]   = session.xserver.host

        return channel
      end

      class SFTPTransferWrapper
        attr_reader :operation

        def initialize(session, &callback)
          session.sftp(false).connect do |sftp|
            @operation = callback.call(sftp)
          end
        end

        def active?
          @operation.nil? || @operation.active?
        end

        def [](key)
          @operation[key]
        end

        def []=(key, value)
          @operation[key] = value
        end

        def abort!
          @operation.abort!
        end
      end

      def prepare_sftp_transfer(from, to, session)
        SFTPTransferWrapper.new(session) do |sftp|
          real_callback = Proc.new do |event, op, *args|
            if callback
              callback.call(event, op, *args)
            elsif event == :open
              logger.trace "[#{op[:host]}] #{args[0].remote}"
            elsif event == :finish
              logger.trace "[#{op[:host]}] done"
            end
          end

          opts = options.dup
          opts[:properties] ||= {}
          opts[:properties][:server] = session.xserver
          opts[:properties][:host]   = session.xserver.host

          case direction
          when :up
            sftp.upload(from, to, opts, &real_callback)
          when :down
            sftp.download(from, to, opts, &real_callback)
          else
            raise ArgumentError, "unsupported transfer direction: #{direction.inspect}"
          end
        end
      end

      def normalize(argument, session)
        if argument.is_a?(String)
          argument.gsub(/\$CAPISSH:HOST\$/, session.xserver.host)
        elsif argument.respond_to?(:read)
          pos = argument.pos
          clone = StringIO.new(argument.read)
          clone.pos = argument.pos = pos
          clone
        else
          argument
        end
      end

      def handle_error(transfer, error)
        raise error if error.message.include?('expected a file to upload')

        transfer[:error] = error
        transfer[:failed] = true

        case transport
        when :sftp then transfer.abort!
        when :scp  then transfer.close
        end
      end
  end
end
