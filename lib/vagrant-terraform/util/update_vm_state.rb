module VagrantPlugins
  module TerraformProvider
    module Util
      module UpdateVmState

      module_function

        def update_vm_state(file_path, key, formatted_value)
          # Read the file contents
          lines = File.readlines(file_path)

          # Update the line containing the given key
          updated_lines = lines.map do |line|
            if line.strip.start_with?(key)
              line.gsub(/#{Regexp.escape(key)}\s*=\s*\S.*/, "#{key} = #{formatted_value}")
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
