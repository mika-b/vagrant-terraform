require 'open3'
require 'set'
require 'vagrant-terraform/util/machine_names'

module VagrantPlugins
  module TerraformProvider
    module Util
      module TerraformExecute
        # Terraform working directories whose terraform.tfstate has been
        # brought up to date (by `terraform refresh` or `terraform apply`)
        # during this process. ReadState uses this to refresh each machine at
        # most once per process instead of on every state query.
        REFRESHED_DIRS = Set.new

      module_function

        def terraform_refreshed?(dir)
          REFRESHED_DIRS.include?(File.expand_path(dir))
        end

        def terraform_execute(env, command, ignore_error = nil)
          env[:machine_tf_dir] = MachineNames.terraform_dir(env[:machine]) if env[:machine_tf_dir].nil?
          Dir.mkdir(env[:machine_tf_dir]) unless File.exist?(env[:machine_tf_dir])

          stdout, stderr, status = Open3.capture3(command, :chdir=>env[:machine_tf_dir])

          if !stderr.empty? && env[:machine].provider_config.debug
              env[:ui].info("terraform command: #{command}")
              env[:ui].info("terraform stdout: #{stdout}")
              env[:ui].info("terraform stderr: #{stderr}")
              env[:ui].info("terraform status: #{status}")
          end

          if status != 0 && !(ignore_error && stderr.include?(ignore_error))
            raise Errors::TerraformError,
                  :error_message => "terraform command '#{command}' failed with status: #{status}, stderr: #{stderr}"
          end

          # Both refresh and apply leave terraform.tfstate reflecting the
          # live resource, so a following state read needn't refresh again.
          if command.start_with?('terraform refresh', 'terraform apply')
            REFRESHED_DIRS << File.expand_path(env[:machine_tf_dir])
          end

          return stdout
        end
      end
    end
  end
end
