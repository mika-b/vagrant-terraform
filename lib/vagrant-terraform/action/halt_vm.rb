require 'log4r'
require 'vagrant-terraform/errors'
require 'vagrant-terraform/util/terraform_execute'
require 'vagrant-terraform/util/update_vm_state'
require 'vagrant-terraform/util/proxmox_api'

module VagrantPlugins
  module TerraformProvider
    module Action

      class HaltVM
        include Util::TerraformExecute
        include Util::UpdateVmState

        def initialize(app, env)
          @logger = Log4r::Logger.new("vagrant_terraform::action::halt_vm")
          @app = app
        end

        def call(env)

          env[:ui].info(I18n.t("vagrant_terraform.halt_vm"))

          begin
            config = env[:machine].provider_config
            terraform_dir = Util::MachineNames.terraform_dir(env[:machine])
            if config.guest_type == :container
              # Via the API, not terraform: see ProxmoxApi.set_container_power.
              ref = Util::ProxmoxApi.container_ref(terraform_dir, config)
              Util::ProxmoxApi.set_container_power(config, *ref, :stopped) unless ref.nil?
            else
              terraform_main_file = "#{terraform_dir}/main.tf"
              update_vm_state(terraform_main_file, "vm_state", "\"stopped\"")
              terraform_execute(env, 'terraform apply -auto-approve')
            end
          rescue Exception => e
            # TODO: need to retry in some case?
            # retry if e.message =~ /something/
            raise e
          end

          @app.call(env)
        end
      end
    end
  end
end
