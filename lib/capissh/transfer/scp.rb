require 'net/scp'
require 'capissh/errors'

module Capissh
  class Transfer
    class SCP
      attr_reader :direction, :from, :to, :session, :options, :callback, :logger
      attr_accessor :error

      def initialize(direction, from, to, session, options={}, &block)
        @direction = direction
        @from      = from
        @to        = to
        @session   = session
        @options   = options
        @logger    = options.delete(:logger)
        @callback  = block || default_callback

        unless [:up,:down].include?(@direction)
          raise ArgumentError, "unsupported transfer direction: #{@direction.inspect}"
        end
      end

      def server
        session.xserver
      end

      def active?
        @channel && @channel.active?
      end

      def failed!
        @failed = true
      end

      def failed?
        @failed
      end

      def close
        @channel && @channel.close
      end

      def default_callback
        Proc.new do |channel, name, sent, total|
          logger.trace "[#{channel[:host]}] #{name}" if logger && sent == 0
        end
      end

      def intent
        "scp #{operation} #{from} -> #{to}"
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

      def upload
        @channel = session.scp.upload(from, to, options, &callback)
        @channel[:server] = server
        @channel[:host]   = server.host
        @channel
      end

      def download
        @channel = session.scp.download(from, to, options, &callback)
        @channel[:server] = server
        @channel[:host]   = server.host
        @channel
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

    end
  end
end
