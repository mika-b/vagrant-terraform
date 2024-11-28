require 'vagrant'

module VagrantPlugins
  module TerraformProvider
    module Errors
      class VagrantTerraformError < Vagrant::Errors::VagrantError
        error_namespace("vagrant_terraform.errors")
      end

      class NoVMError < VagrantTerraformError
        error_key(:no_vm_error)
      end

      class CreateVMError < VagrantTerraformError
        error_key(:create_vm_error)
      end

      class StartVMError < VagrantTerraformError
        error_key(:start_vm_error)
      end

      class NoIPError < VagrantTerraformError
        error_key(:no_ip_error)
      end

      class TerraformError < VagrantTerraformError
        error_key(:terraform_execution_error)
      end

    end
  end
end