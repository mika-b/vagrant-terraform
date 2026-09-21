require 'net/http'
require 'uri'
require 'json'
require 'openssl'
require 'vagrant-terraform/util/terraform_state'

module VagrantPlugins
  module TerraformProvider
    module Util
      module ProxmoxApi
        module_function

        # Performs a GET request against the Proxmox API and returns the
        # parsed `data` field of the response envelope.
        #
        # config must respond to api_url, api_token_id, api_token_secret,
        # insecure.
        def get(config, path)
          uri = URI.join("#{config.api_url}/", path.sub(%r{^/}, ''))

          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = uri.scheme == 'https'
          http.verify_mode = OpenSSL::SSL::VERIFY_NONE if config.insecure

          request = Net::HTTP::Get.new(uri)
          request['Authorization'] = "PVEAPIToken=#{config.api_token_id}=#{config.api_token_secret}"

          response = http.request(request)

          unless response.is_a?(Net::HTTPSuccess)
            raise Errors::ProxmoxApiError,
                  :error_message => "GET #{uri} returned #{response.code}: #{response.body}"
          end

          JSON.parse(response.body)["data"]
        rescue Errors::ProxmoxApiError
          raise
        rescue StandardError => e
          raise Errors::ProxmoxApiError, :error_message => e.message
        end

        # data is the parsed `data` field from GET .../status/current.
        # Returns :running or :stopped.
        def extract_status(data)
          data["status"] == "running" ? :running : :stopped
        end

        # data is the parsed `data` field from GET .../interfaces (an array
        # of interface hashes). Returns the IPv4 address (without prefix) of
        # the named interface, or nil if it has none yet.
        def extract_ip(data, iface_name = "eth0")
          iface = data.find { |i| i["name"] == iface_name }
          return nil if iface.nil? || iface["inet"].nil?

          iface["inet"].split('/').first
        end

        def container_status(config, target_node, vmid)
          data = get(config, "nodes/#{target_node}/lxc/#{vmid}/status/current")
          extract_status(data)
        end

        def container_ip(config, target_node, vmid, iface_name = "eth0")
          data = get(config, "nodes/#{target_node}/lxc/#{vmid}/interfaces")
          extract_ip(data, iface_name)
        end

        # Convenience wrapper used by WaitForVmUp and ReadSSHInfo: looks up
        # the container's vmid from its terraform.tfstate (under
        # machine_tf_dir) and returns its current IP, or nil if the state
        # file/vmid isn't there yet.
        def container_ip_for_machine(machine_tf_dir, config)
          attributes = TerraformState.read_attributes("#{machine_tf_dir}/terraform.tfstate")
          return nil if attributes.nil?

          vmid = attributes["vmid"]
          return nil if vmid.nil?

          container_ip(config, config.target_node, vmid)
        end
      end
    end
  end
end
