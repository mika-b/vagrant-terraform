module VagrantPlugins
  module TerraformProvider
    module Util
      module MachineNames
        DEFAULT_NAME = 'vagrant'.freeze

      module_function

        def machine_hostname(machine)
          machine.config.vm.hostname || DEFAULT_NAME
        end

        def machine_vmname(machine)
          if machine.id.nil?
            machine.provider_config.vmname || machine_hostname(machine)
          else
            machine.id
          end
        end
      end
    end
  end
end
