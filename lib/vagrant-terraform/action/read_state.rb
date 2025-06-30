require "log4r"
require 'vagrant-terraform/util/terraform_execute'
require 'vagrant-terraform/util/machine_names'

$terraform_refreshed = nil

module VagrantPlugins
  module TerraformProvider
    module Action
      # This action reads the state of the machine and puts it in the
      # `:machine_state_id` key in the environment.
      class ReadState
        include Util::TerraformExecute
        include Util::MachineNames

        def initialize(app, env)
          @app    = app
          @logger = Log4r::Logger.new("vagrant_terraform::action::read_state")
        end

        def call(env)
          env[:machine_state_id] = read_state(env)
          @app.call(env)
        end

        def read_state(env)
          env[:machine_tf_dir] = ".vagrant/terraform/#{machine_vmname(env[:machine])}"
          terraform_state_file = "#{env[:machine_tf_dir]}/terraform.tfstate"
          if File.exist?(env[:machine_tf_dir]) && File.exist?(terraform_state_file)
            # read_state might get called several times. Avoid refreshing 5 times in a row
            # for example during "vagrant up" for no obvious reason.
            if $terraform_refreshed.nil?
              terraform_execute(env, 'terraform refresh')
              $terraform_refreshed = true
            end

            json_data = File.read(terraform_state_file)
            data = JSON.parse(json_data)

            # Navigate to the "vm_state" value
            resources = data["resources"]
            return :not_created if resources.nil? || resources.empty?

            first_resource = resources.first  # TODO: find by name
            instances = first_resource["instances"]
            return :not_created if instances.nil? || instances.empty?

            attributes = instances.first["attributes"]
            return :not_created if attributes.nil?
            return :not_created if attributes["vm_state"].nil?

            ip_addr = attributes["default_ipv4_address"]
            unless ip_addr.nil?
              env[:ip_address] = ip_addr
            end

            return attributes["vm_state"].to_sym
          else
            return :not_created
          end
        end
      end
    end
  end
end