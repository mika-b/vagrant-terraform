module VagrantPlugins
  module TerraformProvider
    module Util
      # SSH/rsync config adjustments for LXC containers logged into as root.
      #
      # Containers SSH in as root by default (see ReadSSHInfo), and stock CT
      # templates commonly don't have a `sudo` binary at all. Vagrant still
      # wraps privileged guest commands in config.ssh.sudo_command, and the
      # rsync synced-folder implementation separately defaults its remote
      # --rsync-path to the literal "sudo rsync"
      # (plugins/synced_folders/rsync/default_unix_cap.rb) -- it is passed
      # straight to the local rsync binary, not through the SSH communicator.
      # As root there is nothing to escalate to, so both become no-ops.
      #
      # Applied once from Provider#initialize, so every command that uses
      # this machine sees it: up/provision as well as `vagrant rsync` and
      # `vagrant rsync-auto`, which use the machine config directly without
      # going through any of this plugin's action chains.
      #
      # Only when the effective SSH user is root: with a non-root
      # config.ssh.username, privileged commands genuinely need sudo.
      module ContainerSsh
        DEFAULT_SUDO_COMMAND = "sudo -E -H %c".freeze

        module_function

        def root_login?(machine)
          username = machine.config.ssh.username
          username.nil? || username.to_s == "root"
        end

        def apply_overrides(machine)
          return unless machine.provider_config.guest_type == :container
          return unless root_login?(machine)

          ssh = machine.config.ssh
          # Leave a user-customised sudo_command alone.
          ssh.sudo_command = "%c" if ssh.sudo_command == DEFAULT_SUDO_COMMAND

          # rsync__rsync_path is Vagrant's documented per-folder override for
          # exactly this; ||= keeps an explicit user setting.
          machine.config.vm.synced_folders.each_value do |folder_opts|
            folder_opts[:rsync__rsync_path] ||= "rsync"
          end
        end
      end
    end
  end
end
