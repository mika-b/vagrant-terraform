require 'fileutils'
require 'log4r'
require 'vagrant-terraform/errors'
require 'vagrant-terraform/util/terraform_execute'

module VagrantPlugins
  module TerraformProvider
    module Action

      class DestroyVM
        include Util::TerraformExecute

        def initialize(app, env)
          @logger = Log4r::Logger.new("vagrant_terraform::action::destroy_vm")
          @app = app
        end

        def call(env)
          env[:ui].info(I18n.t("vagrant_terraform.destroy_vm"))

          begin
            # for some reason here the machine_tf_dir is not in env even though read_state has been called
            # multiple times on 'vagrant halt' before we get here.
            terraform_dir = ".vagrant/terraform/#{env[:machine].id}"

            terraform_execute(env, 'terraform destroy -auto-approve')
            FileUtils.rm_rf(terraform_dir)
          rescue Exception => e
            retry if e.message =~ /Please try again/

            raise e
          end

          @app.call(env)
        end
      end
    end
  end
end
