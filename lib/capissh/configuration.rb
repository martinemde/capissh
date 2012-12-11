require 'capissh/logger'
require 'capissh/connections'
require 'capissh/roles'
require 'capissh/servers'
require 'capissh/invocation'

module Capissh
  # Represents a specific Capissh configuration. A Configuration instance
  # may be used to load multiple recipe files, define and describe tasks,
  # define roles, and set configuration variables.
  class Configuration
    # The logger instance defined for this configuration.
    attr_accessor :debug, :logger, :dry_run, :preserve_roles

    def initialize(options={}) #:nodoc:
      @debug = false
      @dry_run = false
      @preserve_roles = false
      @logger = Capissh::Logger.new(options)
    end

    # The includes must come at the bottom, since they may redefine methods
    # defined in the base class.
    include Roles, Servers

    # Mix in the actions
  end
end
