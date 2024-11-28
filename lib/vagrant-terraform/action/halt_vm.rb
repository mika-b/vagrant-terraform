require 'log4r'
require 'vagrant-terraform/errors'
require 'vagrant-terraform/util/terraform_execute'
require 'vagrant-terraform/util/update_vm_state'

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
            terraform_dir = ".vagrant/terraform/#{env[:machine].id}"
            terraform_main_file = "#{terraform_dir}/main.tf"
            update_vm_state(terraform_main_file, "stopped")
            terraform_execute(env, 'terraform apply -auto-approve')
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
