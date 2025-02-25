require "log4r"
require "open3"

module VagrantPlugins
  module TerraformProvider
    module Action
      # This action reads the state of the machine and puts it in the
      # `:machine_state_id` key in the environment.
      class SetupTerraform
        def initialize(app, env)
          @app    = app
          @logger = Log4r::Logger.new("vagrant_terraform::action::setup_terraform")
        end

        def call(env)
          raise "env[:machine_tf_dir] not set" if env[:machine_tf_dir].nil?

          terraform_dir = env[:machine_tf_dir]
          if File.exist?(terraform_dir) && File.exist?("#{terraform_dir}/terraform.tfstate")
            env[:ui].info("Already initialized.")
          else
            # dir_name = env[:root_path].basename.to_s.dup.gsub(/[^-a-z0-9_]/i, "")
            begin
              Dir.mkdir(File.dirname(terraform_dir)) unless File.exist?(File.dirname(terraform_dir))
              FileUtils.touch("#{File.dirname(terraform_dir)}/lock")
            rescue => e
              retry if e.message =~ /File exists/
              env[:ui].error("terraform init failed: #{e.message}")
            end

            begin
              Dir.mkdir(terraform_dir) unless File.exist?(terraform_dir)
            rescue => e
              retry if e.message =~ /File exists/
              env[:ui].error("terraform init failed: #{e.message}")
            end
          end
          @app.call(env)
        end
      end
    end
  end
end