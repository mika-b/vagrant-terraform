require 'log4r'
require 'vagrant-terraform/errors'
require 'vagrant-terraform/util/terraform_execute'
require 'vagrant-terraform/util/update_vm_state'

module VagrantPlugins
  module TerraformProvider
    module Action

      # Just start the VM.
      class StartVM
        include Util::TerraformExecute
        include Util::UpdateVmState

        def initialize(app, env)
          @logger = Log4r::Logger.new("vagrant_terraform::action::start_vm")
          @app = app
        end

        def call(env)
          config = env[:machine].provider_config

          env[:ui].info(I18n.t("vagrant_terraform.starting_vm"))

          begin
            terraform_dir = env[:machine_tf_dir]
            terraform_main_file = "#{terraform_dir}/main.tf"
            update_vm_state(terraform_main_file, "running")
            terraform_execute(env, 'terraform apply -auto-approve')
          rescue Exception => e
            fault_message = /Error was \"\[?(.+?)\]?\".*/.match(e.message)[1] rescue e.message
            # TODO: retry in some case?
            # retry if e.message =~ /something/

            if e.message !~ /VM is running/
              if config.debug
                raise e
              else
                raise Errors::StartVMError,
                  :error_message => fault_message
              end
            end

          end

          @app.call(env)
        end
      end
    end
  end
end
