require "log4r"
require 'vagrant-terraform/util/terraform_execute'

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

          ip_addr = terraform_execute(env, "terraform output -raw public_ip")
          return nil if ip_addr.nil?

          return {
            :host             => ip_addr,
            :port             => machine.config.ssh.guest_port,
            :username         => machine.config.ssh.username,
            :private_key_path => machine.config.ssh.private_key_path,
            :forward_agent    => machine.config.ssh.forward_agent,
            :forward_x11      => machine.config.ssh.forward_x11,
          }
        end
      end
    end
  end
end
