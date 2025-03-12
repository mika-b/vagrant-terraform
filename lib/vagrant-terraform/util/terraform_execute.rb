require 'open3'

module VagrantPlugins
  module TerraformProvider
    module Util
      module TerraformExecute

      module_function

        def terraform_execute(env, command)
          env[:machine_tf_dir] = ".vagrant/terraform/#{env[:machine].id}" if env[:machine_tf_dir].nil?
          Dir.mkdir(env[:machine_tf_dir]) unless File.exist?(env[:machine_tf_dir])

          stdout, stderr, status = Open3.capture3(command, :chdir=>env[:machine_tf_dir])

          if !stderr.empty? && env[:machine].provider_config.debug
              env[:ui].info("terraform command: #{command}")
              env[:ui].info("terraform stdout: #{stdout}")
              env[:ui].info("terraform stderr: #{stderr}")
              env[:ui].info("terraform status: #{status}")
          end

          if status != 0
            raise Errors::TerraformError,
                  :error_message => "terraform command '#{command}' failed with status: #{status}, stderr: #{stderr}"
          end
          return stdout
        end
      end
    end
  end
end
