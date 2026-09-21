require 'json'

module VagrantPlugins
  module TerraformProvider
    module Util
      module TerraformState
        module_function

        # Returns the `attributes` hash of the first resource's first
        # instance in a terraform.tfstate file, or nil if the file doesn't
        # exist or declares no resources/instances.
        def read_attributes(state_file)
          return nil unless File.exist?(state_file)

          data = JSON.parse(File.read(state_file))
          resources = data["resources"]
          return nil if resources.nil? || resources.empty?

          instances = resources.first["instances"]
          return nil if instances.nil? || instances.empty?

          instances.first["attributes"]
        end
      end
    end
  end
end
