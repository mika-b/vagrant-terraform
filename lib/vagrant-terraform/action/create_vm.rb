require 'log4r'
require 'vagrant-terraform/util/machine_names'
require 'vagrant-terraform/util/terraform_execute'
require 'vagrant/util/retryable'

module VagrantPlugins
  module TerraformProvider
    module Action
      class CreateVM
        include Util::TerraformExecute
        include Util::MachineNames
        include Vagrant::Util::Retryable

        def initialize(app, env)
          @logger = Log4r::Logger.new("vagrant_terraform::action::create_vm")
          @app = app
        end

        def call(env)
          # Get config.
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

          vmname = machine_vmname(env[:machine])

          main_tf = <<-END
provider "proxmox" {
    pm_api_url   = "#{config.api_url}"
    pm_api_token_id      = "#{config.api_token_id}"
    pm_api_token_secret  = "#{config.api_token_secret}"
    pm_tls_insecure = #{config.insecure.to_s}
    pm_debug = #{config.debug}
}

resource "proxmox_vm_qemu" "#{vmname.gsub(/\./, '-')}" {
    name       = "#{vmname}"
    target_nodes = ["#{config.target_node}"]
    desc = "#{config.description}"
    vm_state   = "stopped"
    clone      = "#{config.template}"
    full_clone = "#{config.full_clone}"
    cores      = #{config.cpu_cores.to_i}
    memory     = #{Filesize.from("#{config.memory_size} B").to_f('MiB').to_i}
    onboot = #{config.onboot}
    agent      = 1
    vga {
        type   = "#{config.vga}"
        # Between 4 and 512, ignored if type is defined to serial
        memory = 64
    }
    scsihw     = "virtio-scsi-pci"
    boot       = "order=virtio0"
    bootdisk   = "virtio0"
    os_type    = "#{config.os_type}"
    disks {
        virtio {
            virtio0 {
                disk {
                    backup = false
                    storage = "#{config.storage_domain}"
                    size = "#{Filesize.from("#{config.disk_size} B").to_f('GB').to_i}G"
                }
            }
        }
        ide {
            ide2 {
                cloudinit {
                    storage = "#{config.storage_domain}"
                }
            }
        }
    }
%SERIAL%
    nameserver = "#{config.nameserver}"
    searchdomain = "#{config.searchdomain}"
%NETWORKS%
    ciuser = "vagrant"
    sshkeys = <<EOF
    ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEA6NF8iallvQVp22WDkTkyrtvp9eWW6A8YVr+kz4TjGYe7gHzIw+niNltGEFHzD8+v1I2YJ6oXevct1YeS0o9HZyN1Q9qgCgzUFtdOKLv6IedplqoPkcmF0aYet2PkEDo3MlTBckFXPITAMzF8dJSIFo9D8HfdOV0IAdx4O7PtixWKn5y2hMNG0zQPyUecp4pzC6kivAIhyfHilFR61RGL+GPXQ2MWZWFYbAGjyiYJnAmCP3NOTd0jMZEnDkbUvxhMmBYSdETk1rRgm+R4LOzFUGaHqHDLKLX+FIPKcF96hrucXzcWyLbIbEgE98OHlnVYCzRdK8jlqm8tehUc9c9WhQ== vagrant insecure public key
    EOF
}

# terraform output -raw public_ip
output "public_ip" {
  value = proxmox_vm_qemu.#{vmname.gsub(/\./, '-')}.default_ipv4_address
}

terraform {
  required_version = ">= 1.8.0"
  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "3.0.1-rc6"
      #version = ">= 3.0.1-rc3"
    }
  }
}
 END
          network_template = <<-END
    network {
        id = %IDX%
        bridge    = "%BRIDGE%"
        firewall  = false
        link_down = false
        model     = "virtio"
    }
    ipconfig%IDX% = "%IP%"
END

          serial_template = <<-END
    serial {
      id = 0
      type = "socket"
    }
END
          if config.serial_port
            main_tf = main_tf.gsub(/%SERIAL%/, serial_template)
          else
            main_tf = main_tf.gsub(/%SERIAL%/, '')
          end

          vagrantfile_networks = []
          env[:machine].id = vmname
          env[:machine].config.vm.networks.each_with_index do |network, idx|
            type, options = network

            # Only private networks are supported
            next unless type == :private_network
            if ! options[:terraform__ip].nil?
              if ! options[:terraform__ip].include? "/"
                raise "IP must be given in CIDR form, for example 192.168.0.10/24"
              end

              if options[:terraform__gateway].nil?
                network_str = network_template.gsub(/%IP%/, "ip=#{options[:terraform__ip]}")
              else
                network_str = network_template.gsub(/%IP%/, "ip=#{options[:terraform__ip]},gw=#{options[:terraform__gateway]}")
              end
            else
              network_str = network_template.gsub(/%IP%/, "ip=dhcp")
            end
            network_str = network_str.gsub(/%BRIDGE%/, options[:terraform__network_name])
            network_str = network_str.gsub(/%IDX%/, idx.to_s)
            vagrantfile_networks << network_str
          end
          main_tf = main_tf.gsub(/%NETWORKS%/, vagrantfile_networks.join())

          # Output the settings we're going to use to the user
          env[:ui].info(I18n.t("vagrant_terraform.creating_vm"))
          env[:ui].info(" -- Name:          #{vmname}")
          env[:ui].info(" -- Template:      #{config.template}")
          env[:ui].info(" -- Description:   #{config.description}")
          env[:ui].info(" -- Target node:   #{config.target_node}")
          env[:ui].info(" -- Storage domain: #{config.storage_domain}")
          env[:ui].info(" -- CPU Cores:     #{config.cpu_cores}")
          env[:ui].info(" -- Memory:        #{Filesize.from("#{config.memory_size} B").to_f('MB').to_i} MB")
          env[:ui].info(" -- Disk:          #{Filesize.from("#{config.disk_size} B").to_f('GB').to_i} GB") unless config.disk_size.nil?

          terraform_dir = env[:machine_tf_dir]
          terraform_main_file = "#{terraform_dir}/main.tf"

          File.write(terraform_main_file, main_tf)
          terraform_execute(env, 'terraform init')

          retryable(on: Errors::TerraformError, tries: 10, sleep: 1) do
            begin
              terraform_execute(env, "terraform apply -auto-approve")
            rescue Errors::TerraformError => e
              # ==> vm_one: terraform stderr: ╷
              # ==> vm_one: │ Error: can't lock file '/var/lock/qemu-server/lock-100.conf' - got timeout
              ansi_escape_regex = /\e\[(?:[0-9]{1,2}(?:;[0-9]{1,2})*)?[m|K]/
              if e.message.gsub(ansi_escape_regex, '').include?("Error: can't lock file")
                env[:ui].info("Proxmox unable to get lock, retrying")
                raise e
              end

              # Terraform error message was 'clone failed: cfs-lock 'storage-qnap-nfs' error: got lock request timeout'
              if e.message.gsub(ansi_escape_regex, '').include?("clone failed: cfs-lock")
                env[:ui].info("Proxmox unable to get storage lock, retrying")
                raise e
              end

              # Terraform error message was 'clone failed: 'storage-qnap-nfs'-locked command timed out - aborting'
              if e.message.gsub(ansi_escape_regex, '').include?("command timed out")
                env[:ui].info("Proxmox clone failed, retrying")
                raise e
              end

              # Terraform error message was '500 got no worker upid - start worker failed'
              if e.message.gsub(ansi_escape_regex, '').include?("got no worker upid")
                env[:ui].info("Proxmox error: 'got no worker upid', retrying")
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

        def recover(env)
          # undo
          return if env["vagrant.error"].is_a?(Vagrant::Errors::VagrantError)  # leaves main.tf in .vagrant/terraform/HOSTNAME/
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
