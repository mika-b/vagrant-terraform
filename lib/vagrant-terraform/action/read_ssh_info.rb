require "log4r"
require 'vagrant-terraform/util/terraform_execute'
require 'vagrant-terraform/util/proxmox_api'

module VagrantPlugins
  module TerraformProvider
    module Action
      # This action reads the SSH info for the machine and puts it into the
      # `:machine_ssh_info` key in the environment.
      class ReadSSHInfo
        include Util::TerraformExecute

        def initialize(app, env)
          @app    = app
          @logger = Log4r::Logger.new("vagrant_terraform::action::read_ssh_info")
        end

        def call(env)
          env[:machine_ssh_info] = read_ssh_info(env)

          @app.call(env)
        end

        # Returns a hash of SSH connection information if and only if at least one IPv4
        # address associated with the machine in question could be retrieved
        # Otherwise, it returns nil.
        def read_ssh_info(env)
          machine = env[:machine]
          config = machine.provider_config

          ip_addr = if config.guest_type == :container
                      begin
                        Util::ProxmoxApi.container_ip_for_machine(env[:machine_tf_dir], config)
                      rescue Errors::ProxmoxApiError => e
                        @logger.debug("container IP lookup failed: #{e.message}")
                        nil
                      end
                    else
                      terraform_execute(env, "terraform output -raw public_ip")
                    end
          return nil if ip_addr.nil?

          username = machine.config.ssh.username
          username = "root" if config.guest_type == :container && username.nil?

          return {
            :host             => ip_addr,
            :port             => machine.config.ssh.guest_port,
            :username         => username,
            :private_key_path => machine.config.ssh.private_key_path,
            :forward_agent    => machine.config.ssh.forward_agent,
            :forward_x11      => machine.config.ssh.forward_x11,
          }
        end
      end
    end
  end
end
