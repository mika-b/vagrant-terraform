require 'log4r'
require 'socket'
require 'timeout'
require 'vagrant-terraform/util/timer'
require 'vagrant-terraform/util/terraform_execute'
require 'net/ssh'

module VagrantPlugins
  module TerraformProvider
    module Action

      # Wait till VM is started, till it obtains an IP address and is
      # accessible via ssh.
      class WaitForVmUp
        include Util::TerraformExecute

        def initialize(app, env)
          @logger = Log4r::Logger.new("vagrant_terraform::action::wait_for_vm_up")
          @app = app
        end

        def port_open?(ip)
          # Check if ssh server responds, AuthenticationFailed is what we expect to get.
          # If credentials vagrant:vagrant happen to work that's a success as well.
          begin
            begin
              ssh = Net::SSH.start(ip, "vagrant", password: "vagrant",
                                   non_interactive: true, user_known_hosts_file: [],
                                   verify_host_key: :never)
            ensure
              ssh&.close
            end
            return true
          rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH
            return false
          rescue Net::SSH::AuthenticationFailed
            return true
          rescue Net::SSH::Disconnect => e
            @logger.debug("Net::SSH disconnected: #{e.message}")
            return false
          rescue Errno::ECONNRESET
            @logger.debug("Got connection reset")
            return false
          rescue StandardError => e
            @logger.debug("Got error #{e.message}")
            return false
          rescue => e
            @logger.debug("An error of type #{e.class} happened, message is #{e.message}")
            return false
          end
          return false
        end

        def call(env)
          # Initialize metrics if they haven't been
          env[:metrics] ||= {}

          # Wait for VM to obtain an ip address.
          env[:metrics]["instance_ip_time"] = Util::Timer.time do
            env[:ui].info(I18n.t("vagrant_terraform.waiting_for_ip"))
            for attempt in 1..100
              # If we're interrupted don't worry about waiting
              next if env[:interrupted]

              output = terraform_execute(env, "terraform refresh")
              ip_addr = output.match(/\b(?:\d{1,3}\.){3}\d{1,3}\b/)&.to_s
              unless ip_addr.nil?
                env[:ui].info("Got IP (attempt #{attempt}): #{ip_addr}")
                # Check if SSH-Server is up
                if port_open?(ip_addr)
                  env[:ip_address] = ip_addr
                  @logger.debug("Got output #{env[:ip_address]}")
                  break
                end
              end
              sleep 2
            end
          end

          terminate(env) if env[:interrupted]

          if env[:ip_address].nil?
            env[:ui].error("failed to get IP: #{env[:metrics]["instance_ip_time"]}")
            raise Errors::NoIPError
          else
            @logger.info("Got IP address #{env[:ip_address]}")
            @logger.info("Time for getting IP: #{env[:metrics]["instance_ip_time"]}")

            # Booted and ready for use.
            env[:ui].info(I18n.t("vagrant_terraform.ready"))

            @app.call(env)
          end
        end

        def recover(env)
          return if env["vagrant.error"].is_a?(Vagrant::Errors::VagrantError)

          if env[:machine].provider.state.id != :not_created
            # Undo the import
            terminate(env)
          end
        end

        def terminate(env)
          destroy_env = env.dup
          destroy_env.delete(:interrupted)
          destroy_env[:config_validate] = false
          destroy_env[:force_confirm_destroy] = true
          env[:action_runner].run(Action.action_destroy, destroy_env)
        end
      end
    end
  end
end
