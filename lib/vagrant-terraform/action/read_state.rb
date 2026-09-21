require "log4r"
require 'vagrant-terraform/util/terraform_execute'
require 'vagrant-terraform/util/machine_names'
require 'vagrant-terraform/util/terraform_state'
require 'vagrant-terraform/util/proxmox_api'

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
          return :not_created unless File.exist?(env[:machine_tf_dir]) && File.exist?(terraform_state_file)

          # read_state might get called several times. Avoid refreshing 5 times in a row
          # for example during "vagrant up" for no obvious reason.
          if $terraform_refreshed.nil?
            terraform_execute(env, 'terraform refresh', 'is not running')
            $terraform_refreshed = true
          end

          attributes = Util::TerraformState.read_attributes(terraform_state_file)
          return :not_created if attributes.nil?

          if env[:machine].provider_config.guest_type == :container
            read_container_state(env, attributes)
          else
            read_vm_state(env, attributes)
          end
        end

        def read_vm_state(env, attributes)
          return :not_created if attributes["vm_state"].nil?

          ip_addr = attributes["default_ipv4_address"]
          env[:ip_address] = ip_addr unless ip_addr.nil?

          attributes["vm_state"].to_sym
        end

        def read_container_state(env, attributes)
          vmid = attributes["vmid"]
          return :not_created if vmid.nil?

          config = env[:machine].provider_config
          Util::ProxmoxApi.container_status(config, config.target_node, vmid)
        end
      end
    end
  end
end
