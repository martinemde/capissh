require 'capissh/transfer'

module Capissh
  class FileTransfers
    attr_reader :configuration, :connection_manager, :logger

    def initialize(configuration, connection_manager, options={})
      @configuration = configuration
      @connection_manager = connection_manager
      @logger  = options[:logger]
    end

    # Store the given data at the given location on all servers targetted
    # by the current task. If <tt>:mode</tt> is specified it is used to
    # set the mode on the file.
    def put(servers, data, path, options={})
      upload(servers, StringIO.new(data), path, options)
    end

    # Get file remote_path from FIRST server targeted by
    # the current task and transfer it to local machine as path.
    #
    # Pass only one server, or the first of the set of servers will be used.
    #
    # get server, "#{deploy_to}/current/log/production.log", "log/production.log.web"
    def get(servers, remote_path, path, options={}, &block)
      download(Array(servers).slice(0,1), remote_path, path, options, &block)
    end

    def upload(servers, from, to, options={}, &block)
      opts = options.dup
      mode = opts.delete(:mode)
      transfer(servers, :up, from, to, opts, &block)
      if mode
        mode = mode.is_a?(Numeric) ? mode.to_s(8) : mode.to_s
        configuration.run servers, "chmod #{mode} #{to}", opts
      end
    end

    def download(servers, from, to, options={}, &block)
      transfer(servers, :down, from, to, options, &block)
    end

    def transfer(servers, direction, from, to, options={}, &block)
      if configuration.dry_run
        return logger.debug "transfering: #{[direction, from, to] * ', '}"
      end
      connection_manager.execute_on_servers(servers, options) do |sessions|
        Transfer.process(direction, from, to, sessions, options.merge(:logger => logger), &block)
      end
    end

  end
end
