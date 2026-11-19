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

        # Performs a request against the Proxmox API and returns the parsed
        # `data` field of the response envelope. `form` (POST only) is sent
        # as application/x-www-form-urlencoded, which is what the Proxmox
        # API expects.
        #
        # config must respond to api_url, api_token_id, api_token_secret,
        # insecure.
        def request(config, method, path, form = nil)
          uri = URI.join("#{config.api_url}/", path.sub(%r{^/}, ''))

          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = uri.scheme == 'https'
          http.verify_mode = OpenSSL::SSL::VERIFY_NONE if config.insecure

          req = method == :post ? Net::HTTP::Post.new(uri) : Net::HTTP::Get.new(uri)
          req['Authorization'] = "PVEAPIToken=#{config.api_token_id}=#{config.api_token_secret}"
          req.set_form_data(form || {}) if method == :post

          response = http.request(req)

          unless response.is_a?(Net::HTTPSuccess)
            raise Errors::ProxmoxApiError,
                  :error_message => "#{method.to_s.upcase} #{uri} returned #{response.code}: #{response.body}"
          end

          JSON.parse(response.body)["data"]
        rescue Errors::ProxmoxApiError
          raise
        rescue StandardError => e
          raise Errors::ProxmoxApiError, :error_message => e.message
        end

        def get(config, path)
          request(config, :get, path)
        end

        def post(config, path, form = nil)
          request(config, :post, path, form)
        end

        # data is the parsed `data` field from GET .../status/current.
        # Returns :running or :stopped.
        def extract_status(data)
          return :stopped if data.nil?
          data["status"] == "running" ? :running : :stopped
        end

        # data is the parsed `data` field from GET .../interfaces (an array
        # of interface hashes). Returns the IPv4 address (without prefix) of
        # the named interface, or nil if it has none yet.
        def extract_ip(data, iface_name = "eth0")
          return nil unless data.is_a?(Array)
          iface = data.find { |i| i["name"] == iface_name }
          return nil if iface.nil? || iface["inet"].nil?

          iface["inet"].split('/').first
        end

        # The node a container currently lives on. Prefer what terraform
        # recorded over the Vagrantfile's target_node: the provider's read
        # (run by every `terraform refresh`) writes the live node into
        # `current_node`/`target_node`, so this follows migrations and
        # Vagrantfile edits made after creation.
        def container_node(attributes, config)
          [attributes["current_node"], attributes["target_node"], config.target_node].find do |n|
            !n.nil? && !n.to_s.empty?
          end
        end

        # [node, vmid] for the container tracked in machine_tf_dir's
        # terraform.tfstate, or nil if there is no such container yet.
        def container_ref(machine_tf_dir, config)
          attributes = TerraformState.read_attributes("#{machine_tf_dir}/terraform.tfstate")
          return nil if attributes.nil? || attributes["vmid"].nil?

          [container_node(attributes, config), attributes["vmid"]]
        end

        def container_status(config, node, vmid)
          data = get(config, "nodes/#{node}/lxc/#{vmid}/status/current")
          extract_status(data)
        end

        def container_ip(config, node, vmid, iface_name = "eth0")
          data = get(config, "nodes/#{node}/lxc/#{vmid}/interfaces")
          extract_ip(data, iface_name)
        end

        # Starts or stops a container and waits until it reports the
        # requested state.
        #
        # Container power state is managed here rather than through the
        # proxmox_lxc resource's `start` attribute: the telmate provider
        # never reads `start` back from Proxmox and only acts when the
        # configured value differs from the one in terraform.tfstate, so a
        # container started/stopped outside Vagrant could never be brought
        # back to the desired state with `terraform apply`.
        #
        # target is :running or :stopped. Stopping uses a clean shutdown,
        # forced after shutdown_timeout seconds.
        def set_container_power(config, node, vmid, target, shutdown_timeout: 60, wait_timeout: 180)
          return if container_status(config, node, vmid) == target

          if target == :running
            post(config, "nodes/#{node}/lxc/#{vmid}/status/start")
          else
            post(config, "nodes/#{node}/lxc/#{vmid}/status/shutdown",
                 { "timeout" => shutdown_timeout.to_s, "forceStop" => "1" })
          end

          # The POST only queues a Proxmox task; poll until it has taken effect.
          deadline = Time.now + wait_timeout
          until container_status(config, node, vmid) == target
            if Time.now > deadline
              raise Errors::ProxmoxApiError,
                    :error_message => "container #{vmid} on node #{node} did not reach state '#{target}' within #{wait_timeout}s"
            end
            sleep 2
          end
        end

        # Convenience wrapper used by WaitForVmUp and ReadSSHInfo: returns the
        # container's current IP, or nil if the state file/vmid isn't there
        # yet.
        def container_ip_for_machine(machine_tf_dir, config)
          ref = container_ref(machine_tf_dir, config)
          return nil if ref.nil?

          container_ip(config, *ref)
        end
      end
    end
  end
end
