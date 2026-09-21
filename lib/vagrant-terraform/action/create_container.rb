require 'log4r'
require 'vagrant-terraform/util/machine_names'
require 'vagrant-terraform/util/terraform_execute'
require 'vagrant/util/retryable'

module VagrantPlugins
  module TerraformProvider
    module Action
      class CreateContainer
        include Util::TerraformExecute
        include Util::MachineNames
        include Vagrant::Util::Retryable

        def initialize(app, env)
          @logger = Log4r::Logger.new("vagrant_terraform::action::create_container")
          @app = app
        end

        def call(env)
          config = env[:machine].provider_config
          if config.target_node.nil?
            raise "'target_node' must not be empty."
          end

          if config.storage_domain.nil?
            raise "'storage_domain' must not be empty."
          end

          if config.disk_size.nil?
            raise "'disk_size' must be set."
          end

          if config.ostemplate.nil?
            raise "'ostemplate' must be set for containers."
          end

          vmname = machine_vmname(env[:machine])

          networks = []
          private_network_idx = 0
          env[:machine].config.vm.networks.each do |network|
            type, options = network
            next unless type == :private_network

            if !options[:terraform__ip].nil? && !options[:terraform__ip].include?("/")
              raise "IP must be given in CIDR form, for example 192.168.0.10/24"
            end
            raise "'terraform__network_name' must be set for each private network." if options[:terraform__network_name].nil?

            networks << {
              :idx => private_network_idx,
              :bridge => options[:terraform__network_name],
              :ip => options[:terraform__ip] || "dhcp",
              :gateway => options[:terraform__gateway],
            }
            private_network_idx += 1
          end

          env[:ui].info(I18n.t("vagrant_terraform.creating_container"))
          env[:ui].info(" -- Name:          #{vmname}")
          env[:ui].info(" -- OS template:   #{config.ostemplate}")
          env[:ui].info(" -- Description:   #{config.description}")
          env[:ui].info(" -- Target node:   #{config.target_node}")
          env[:ui].info(" -- Storage domain: #{config.storage_domain}")
          env[:ui].info(" -- CPU Cores:     #{config.cpu_cores}")
          env[:ui].info(" -- Memory:        #{Filesize.from("#{config.memory_size} B").to_f('MB').to_i} MB")
          env[:ui].info(" -- Disk:          #{Filesize.from("#{config.disk_size} B").to_f('GB').to_i} GB")

          main_tf = render_main_tf(config, vmname, networks)

          env[:machine].id = vmname
          terraform_dir = env[:machine_tf_dir]
          terraform_main_file = "#{terraform_dir}/main.tf"
          File.write(terraform_main_file, main_tf)

          # Avoid downloading the provider every time even when it's in the cache
          ENV['TF_PLUGIN_CACHE_MAY_BREAK_DEPENDENCY_LOCK_FILE'] = "1"
          retryable(on: Errors::TerraformError, tries: 100, sleep: 1) do
            begin
              terraform_execute(env, 'terraform init')
            rescue Errors::TerraformError => e
              ansi_escape_regex = /\e\[(?:[0-9]{1,2}(?:;[0-9]{1,2})*)?[m|K]/
              if e.message.gsub(ansi_escape_regex, '').include?("Failed to install provider")
                @logger.debug("Failed to install provider, retrying")
                raise e
              end
            end
          end

          retryable(on: Errors::TerraformError, tries: 10, sleep: 1) do
            begin
              lockfile = '.vagrant/terraform/lock'
              max_retries = 300
              retry_delay = 2

              File.open(lockfile, 'w') do |file|
                retries = 0

                # Container creation can't be done in parallel because multiple
                # containers might get the same VMID.
                until file.flock(File::LOCK_EX | File::LOCK_NB)
                  if retries >= max_retries
                    raise Errors::CreateVMError,
                      :error_message => "Failed to acquire lock after #{max_retries} attempts. Exiting."
                  end

                  @logger.debug("Lock is currently held. Retrying in #{retry_delay} seconds...")
                  retries += 1
                  sleep(retry_delay)
                end

                begin
                  terraform_execute(env, "terraform apply -auto-approve")
                ensure
                  file.flock(File::LOCK_UN)
                end
              end

            rescue Errors::TerraformError => e
              ansi_escape_regex = /\e\[(?:[0-9]{1,2}(?:;[0-9]{1,2})*)?[m|K]/

              if e.message.gsub(ansi_escape_regex, '').include?("Error: can't lock file")
                env[:ui].info("Proxmox unable to get lock, retrying")
                raise e
              end

              if e.message.gsub(ansi_escape_regex, '').include?("error: got lock request timeout")
                env[:ui].info("Proxmox unable to get storage lock, retrying")
                raise e
              end

              if e.message.gsub(ansi_escape_regex, '').include?("command timed out")
                env[:ui].info("Proxmox clone failed with command timeout, retrying")
                raise e
              end

              if e.message.gsub(ansi_escape_regex, '').include?("got no worker upid")
                env[:ui].info("Proxmox error: 'got no worker upid', retrying")
                raise e
              end

              if e.message.gsub(ansi_escape_regex, '') =~ /.*volume .* does not exist/
                env[:ui].info("Volume not created, retrying. Error was: #{e.message}")
                raise e
              end

              if e.message.gsub(ansi_escape_regex, '').include?("Request cancelled")
                env[:ui].info("Proxmox error: Request cancelled")
                raise e
              end

              if e.message.gsub(ansi_escape_regex, '') =~ /.*Error: [0-9 ]*unable to create VM [0-9]*: config file already exists/
                env[:ui].info("Proxmox ID conflict, retrying")
                raise e
              end

              if config.debug
                raise e
              else
                fault_message = /Error: (.*)/.match(e.message.gsub(ansi_escape_regex, ''))[1] rescue e.message
                raise Errors::CreateVMError,
                  :error_message => fault_message
              end
            end
          end

          @app.call(env)
        end

        # Pure HCL rendering, independent of the Vagrant `env`, so it can be
        # exercised directly. `config` must respond to target_node,
        # ostemplate, unprivileged, cpu_cores, memory_size, onboot,
        # description, nameserver, searchdomain, storage_domain, disk_size,
        # vmid, api_url, api_token_id, api_token_secret, insecure, debug.
        # `networks` is an array of {:idx, :bridge, :ip, :gateway} hashes.
        def render_main_tf(config, vmname, networks)
          network_blocks = networks.map do |net|
            gw_line = (net[:gateway].nil? || net[:ip] == "dhcp") ? "" : "\n        gw     = \"#{net[:gateway]}\""
            <<-NET
    network {
        name   = "eth#{net[:idx]}"
        bridge = "#{net[:bridge]}"
        ip     = "#{net[:ip]}"#{gw_line}
    }
            NET
          end.join

          vmid_line = config.vmid ? "    vmid         = \"#{config.vmid}\"\n" : ""

          <<-END
provider "proxmox" {
    pm_api_url   = "#{config.api_url}"
    pm_api_token_id      = "#{config.api_token_id}"
    pm_api_token_secret  = "#{config.api_token_secret}"
    pm_tls_insecure = #{config.insecure.to_s}
    pm_debug = #{config.debug}
}

resource "proxmox_lxc" "#{vmname.gsub(/\./, '-')}" {
    target_node  = "#{config.target_node}"
    hostname     = "#{vmname}"
    ostemplate   = "#{config.ostemplate}"
    unprivileged = #{config.unprivileged}
    cores        = #{config.cpu_cores.to_i}
    memory       = #{Filesize.from("#{config.memory_size} B").to_f('MB').to_i}
    onboot       = #{config.onboot}
    description  = "#{config.description}"
    nameserver   = "#{config.nameserver}"
    searchdomain = "#{config.searchdomain}"
    start        = false
#{vmid_line}
    rootfs {
        storage = "#{config.storage_domain}"
        size    = "#{Filesize.from("#{config.disk_size} B").to_f('GB').to_i}G"
    }

    ssh_public_keys = <<EOF
    ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEA6NF8iallvQVp22WDkTkyrtvp9eWW6A8YVr+kz4TjGYe7gHzIw+niNltGEFHzD8+v1I2YJ6oXevct1YeS0o9HZyN1Q9qgCgzUFtdOKLv6IedplqoPkcmF0aYet2PkEDo3MlTBckFXPITAMzF8dJSIFo9D8HfdOV0IAdx4O7PtixWKn5y2hMNG0zQPyUecp4pzC6kivAIhyfHilFR61RGL+GPXQ2MWZWFYbAGjyiYJnAmCP3NOTd0jMZEnDkbUvxhMmBYSdETk1rRgm+R4LOzFUGaHqHDLKLX+FIPKcF96hrucXzcWyLbIbEgE98OHlnVYCzRdK8jlqm8tehUc9c9WhQ== vagrant insecure public key
    EOF

#{network_blocks}}

terraform {
  required_version = ">= 1.8.0"
  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "3.0.2-rc05"
    }
  }
}
          END
        end

        def recover(env)
          return if env["vagrant.error"].is_a?(Vagrant::Errors::VagrantError)
          env[:ui].info(I18n.t("vagrant_terraform.error_recovering"))
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
