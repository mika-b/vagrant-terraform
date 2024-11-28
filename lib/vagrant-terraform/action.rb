require 'fileutils'
require 'vagrant/action/builder'

module VagrantPlugins
  module TerraformProvider
    module Action
      # Include the built-in modules so we can use them as top-level things.
      include Vagrant::Action::Builtin

      # This action is called to bring the box up from nothing.
      def self.action_up
        Vagrant::Action::Builder.new.tap do |b|
          b.use HandleBox
          b.use ConfigValidate

          b.use Call, ReadState do |env, b2|
            b2.use SetupTerraform
            # synced_folders defaults to NFS on linux. Make it default to rsync.
            env[:machine].config.nfs.functional = false
            if env[:machine_state_id] == :running
              b2.use Provision
              b2.use SyncedFolderCleanup
              require 'vagrant/action/builtin/synced_folders'
              b2.use SyncedFolders
              next
            end

            if env[:machine_state_id] == :not_created
              b2.use CreateVM
              b2.use Provision
              b2.use SetHostname
            end

            b2.use StartVM
            b2.use WaitForVmUp
            b2.use SyncedFolderCleanup
            require 'vagrant/action/builtin/synced_folders'
            b2.use SyncedFolders
          end

        end
      end

      def self.action_destroy
        Vagrant::Action::Builder.new.tap do |b|
          b.use ConfigValidate
          b.use Call, IsCreated do |env, b2|
            if !env[:result]
              unless env[:machine].id.nil?
                dir = ".vagrant/terraform/#{env[:machine].id}"
                env[:ui].info("Removing: " + dir)
                FileUtils.rm_rf(dir)
              end
              env[:ui].info(I18n.t("vagrant_terraform.not_created"))
              next
            end

            b2.use ProvisionerCleanup, :before if defined?(ProvisionerCleanup)
            b2.use HaltVM unless env[:machine].state.id == :stopped
            # b2.use WaitTillDown unless env[:machine].state.id == :stopped
            b2.use DestroyVM
          end
        end
      end

      def self.action_provision
        Vagrant::Action::Builder.new.tap do |b|
          b.use ConfigValidate
          b.use Call, IsCreated do |env, b2|
            # synced_folders defaults to NFS on linux. Make it default to rsync.
            env[:machine].config.nfs.functional = false
            if !env[:result]
              env[:ui].info(I18n.t("vagrant_terraform.not_created"))
              next
            end
            b2.use Provision
            b2.use SyncedFolderCleanup
            require 'vagrant/action/builtin/synced_folders'
            b2.use SyncedFolders
          end
        end
      end

      # This action is called to read the state of the machine. The resulting
      # state is expected to be put into the `:machine_state_id` key.
      def self.action_read_state
        Vagrant::Action::Builder.new.tap do |b|
          b.use HandleBox
          b.use ConfigValidate
          b.use ReadState
        end
      end

      # This action is called to read the SSH info of the machine. The
      # resulting state is expected to be put into the `:machine_ssh_info`
      # key.
      def self.action_read_ssh_info
        Vagrant::Action::Builder.new.tap do |b|
          b.use ConfigValidate
          b.use Call, ReadState do |env, b2|
            b2.use ReadSSHInfo
          end
        end
      end

      def self.action_halt
        Vagrant::Action::Builder.new.tap do |b|
          b.use Call, IsRunning do |env, b2|
            if env[:machine_state_id] == :powering_up
              env[:ui].info(I18n.t("vagrant_terraform.powering_up"))
              next
            end
            if !env[:result]
              env[:ui].info(I18n.t("vagrant_terraform.not_up"))
              next
            end
            b2.use HaltVM
          end
        end
      end

      def self.action_reload
        Vagrant::Action::Builder.new.tap do |b|
          b.use action_halt
          b.use action_up
        end
      end

      def self.action_ssh
        Vagrant::Action::Builder.new.tap do |b|
          b.use ConfigValidate

          b.use Call, ReadState do |env, b2|
            if env[:machine_state_id] == :not_created
              env[:ui].info(I18n.t("vagrant_terraform.not_created"))
              next
            end
            if env[:machine_state_id] != :running
              env[:ui].info(I18n.t("vagrant_terraform.not_up"))
              next
            end

            raise Errors::NoIPError if env[:ip_address].nil?
            b2.use SSHExec
          end

        end
      end

      def self.action_ssh_run
        Vagrant::Action::Builder.new.tap do |b|
          b.use ConfigValidate

          b.use Call, ReadState do |env, b2|
            if env[:machine_state_id] == :not_created
              b2.use MessageNotCreated
              next
            end
            if env[:machine_state_id] != :running
              env[:ui].info(I18n.t("vagrant_terraform.not_up"))
              next
            end

            raise Errors::NoIPError if env[:ip_address].nil?
            b2.use SSHRun
          end
        end
      end

      action_root = Pathname.new(File.expand_path("../action", __FILE__))
      autoload :SetupTerraform, action_root.join("setup_terraform")
      autoload :CreateVM, action_root.join("create_vm")
      autoload :DestroyVM, action_root.join("destroy_vm")
      autoload :HaltVM, action_root.join("halt_vm")
      autoload :IsCreated, action_root.join("is_created")
      autoload :IsRunning, action_root.join("is_running")
      autoload :ReadSSHInfo, action_root.join("read_ssh_info")
      autoload :ReadState, action_root.join("read_state")
      autoload :WaitForVmUp, action_root.join("wait_for_vm_up")

      autoload :StartVM, action_root.join("start_vm")
      # autoload :SyncedFolders, 'vagrant/action/builtin/synced_folders'
      autoload :SyncedFolderCleanup, 'vagrant/action/builtin/synced_folder_cleanup'
    end
  end
end
