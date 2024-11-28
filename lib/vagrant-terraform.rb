require 'log4r'
require 'pathname'
require 'vagrant-terraform/plugin'

module VagrantPlugins
  module TerraformProvider
    lib_path = Pathname.new(File.expand_path("../vagrant-terraform", __FILE__))
    autoload :Action, lib_path.join("action")
    autoload :Errors, lib_path.join("errors")
    autoload :Util,   lib_path.join("util")

    @@logger = Log4r::Logger.new("vagrant_terraform::provider")

    # This returns the path to the source of this plugin.
    #
    # @return [Pathname]
    def self.source_root
      @source_root ||= Pathname.new(File.expand_path("../../", __FILE__))
    end
  end
end
