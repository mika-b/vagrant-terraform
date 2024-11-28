module VagrantPlugins
  module TerraformProvider
    module Util
      module UpdateVmState

      module_function

        def update_vm_state(file_path, new_state)
          # Read the file contents
          lines = File.readlines(file_path)

          # Update the line containing "vm_state"
          updated_lines = lines.map do |line|
            if line.strip.start_with?("vm_state")
              line.gsub(/vm_state\s*=\s*".*"/, "vm_state = \"#{new_state}\"")
            else
              line
            end
          end

          # Write the updated contents back to the file
          File.open(file_path, "w") do |file|
            file.puts(updated_lines)
          end
        end
      end
    end
  end
end
