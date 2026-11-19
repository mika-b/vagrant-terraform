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

        # Absolute path of the directory holding all per-machine terraform
        # working directories (and the VM-creation lock file) for this
        # Vagrant project: <project>/.vagrant/terraform.
        #
        # Must be absolute: Vagrant does not chdir to the project root, so a
        # cwd-relative ".vagrant/terraform" breaks whenever vagrant runs with
        # a different cwd -- `vagrant global-status --prune` (which loads
        # every project's environment from wherever it's invoked), commands
        # given a global-status machine id from another directory, or plain
        # commands run from a project subdirectory.
        def terraform_base_dir(machine)
          machine.env.local_data_path.join("terraform").to_s
        end

        def terraform_dir(machine)
          File.join(terraform_base_dir(machine), machine_vmname(machine))
        end
      end
    end
  end
end
