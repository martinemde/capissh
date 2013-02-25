require 'net/sftp'
require 'capissh/errors'

module Capissh
  class Transfer
    class SFTP

      attr_reader :direction, :from, :to, :session, :options, :callback, :logger
      attr_accessor :error

      def initialize(direction, from, to, session, options={}, &block)
        @direction = direction
        @from      = from
        @to        = to
        @session   = session

        @logger    = options.delete(:logger)

        @options   = options.dup
        @options[:properties] ||= {}
        @options[:properties][:server] = server
        @options[:properties][:host]   = server.host

        @callback  = block || default_callback

        unless [:up,:down].include?(@direction)
          raise ArgumentError, "unsupported transfer direction: #{@direction.inspect}"
        end
      end

      def server
        session.xserver
      end

      def default_callback
        Proc.new do |event, op, *args|
          if event == :open
            logger.trace "[#{op[:host]}] #{args[0].remote}"
          elsif event == :finish
            logger.trace "[#{op[:host]}] done"
          end
        end
      end

      def intent
        "sftp #{operation} #{from} -> #{to}"
      end

      def operation
        "#{direction}load"
      end

      def prepare
        case direction
        when :up   then upload
        when :down then download
        end
      end

      def connect(&block)
        session.sftp(false).connect(&block)
      end

      def upload
        connect do |sftp|
          @transfer = sftp.upload(from, to, options, &callback)
        end
      end

      def download
        connect do |sftp|
          @transfer = sftp.download(from, to, options, &callback)
        end
      end

      def active?
        @transfer.nil? || @transfer.active?
      end

      def close
        @transfer.abort!
      end

      def failed!
        @failed = true
      end

      def failed?
        @failed
      end

      def sanitized_from
        from.responds_to?(:read) ? "#<#{from.class}>" : from
      end

      def sanitized_to
        to.responds_to?(:read) ? "#<#{to.class}>" : to
      end
    end
  end
end
