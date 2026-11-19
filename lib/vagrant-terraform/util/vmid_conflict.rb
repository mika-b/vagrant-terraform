require 'vagrant-terraform/util/update_vm_state'

module VagrantPlugins
  module TerraformProvider
    module Util
      # Handling of "this VMID is taken" failures from `terraform apply`
      # during creation, shared by CreateVM and CreateContainer.
      module VmidConflict
        # Messages meaning the requested VMID is (or just became) taken:
        # - the telmate provider's own pre-check for a set vmid (qemu);
        # - Proxmox's race message, when the id was free at check time but
        #   another creation took it first;
        # - Proxmox's "<type> <id> already exists" for a set vmid that is in
        #   use (the provider does no pre-check for LXC).
        # Each pattern matches only the short, human-readable part, which is
        # what gets quoted back to the user (not the whole terraform stderr,
        # which includes the full request parameters).
        PATTERNS = [
          /vmId: \d+ already in use/,
          /unable to create (VM|CT) \d+[^\n]*?config file already exists/,
          /\b(VM|CT) \d+ already exists(?: on node '[^'\n]*')?/,
        ].freeze

        module_function

        def conflict?(message)
          !conflict_detail(message).nil?
        end

        # The matched conflict text, e.g. "CT 20000 already exists on node 'pve1'".
        def conflict_detail(message)
          PATTERNS.each do |re|
            match = message[re]
            return match unless match.nil?
          end
          nil
        end

        # Call when `message` (ANSI-stripped stderr) is a VMID conflict.
        # Returns normally when creation should be retried; raises
        # CreateVMError when retrying can't help.
        #
        # - no vmid configured: Proxmox picked the next free id and lost a
        #   race to a parallel creation; the next attempt gets a new one.
        # - vmid from a range: pick another id from the range and rewrite
        #   main.tf with it.
        # - fixed vmid: it's simply taken; every retry would fail the same.
        def prepare_retry(env, config, terraform_main_file, message)
          if config.vmid.nil?
            env[:ui].info("Proxmox ID conflict, retrying")
            return
          end

          old_vmid = config.vmid
          if config.vmid_from_range? && (new_vmid = config.reroll_vmid!)
            env[:ui].info("VMID #{old_vmid} is already in use, retrying with #{new_vmid}")
            UpdateVmState.update_vm_state(terraform_main_file, "vmid", "\"#{new_vmid}\"")
            return
          end

          raise Errors::CreateVMError,
                :error_message => "VMID #{old_vmid} is already in use. Set a different 'vmid', " \
                                  "a range such as '10000-10999', or leave it unset. " \
                                  "(Proxmox: #{conflict_detail(message) || 'VMID conflict'})"
        end
      end
    end
  end
end
