require 'vagrant'
require 'filesize'

module VagrantPlugins
  module TerraformProvider
    class Config < Vagrant.plugin('2', :config)
      VMID_MIN = 10000
      VMID_MAX = 999999999

      attr_reader :disks

      attr_accessor :api_url
      attr_accessor :api_token_id
      attr_accessor :api_token_secret
      attr_accessor :balloon
      attr_accessor :vga
      attr_accessor :insecure
      attr_accessor :debug
      attr_accessor :vmname
      attr_accessor :template
      attr_accessor :disk_size
      attr_accessor :storage_domain
      attr_accessor :cpu_cores
      attr_accessor :cpu_type
      attr_accessor :memory_size
      attr_accessor :target_node
      attr_accessor :onboot
      attr_accessor :description
      attr_accessor :nameserver
      attr_accessor :searchdomain
      attr_accessor :os_type
      attr_accessor :full_clone
      attr_accessor :serial_port
      attr_accessor :vmid
      attr_accessor :guest_type
      attr_accessor :ostemplate
      attr_accessor :unprivileged

      def initialize
        @api_url           = UNSET_VALUE
        @api_token_id      = UNSET_VALUE
        @api_token_secret  = UNSET_VALUE
        @balloon           = UNSET_VALUE
        @vga               = UNSET_VALUE
        @insecure          = UNSET_VALUE
        @debug             = UNSET_VALUE
        @vmname            = UNSET_VALUE
        @template          = UNSET_VALUE
        @disk_size         = UNSET_VALUE
        @storage_domain    = UNSET_VALUE
        @cpu_cores         = UNSET_VALUE
        @cpu_type          = UNSET_VALUE
        @memory_size       = UNSET_VALUE
        @target_node       = UNSET_VALUE
        @onboot            = UNSET_VALUE
        @description       = UNSET_VALUE
        @nameserver        = UNSET_VALUE
        @searchdomain      = UNSET_VALUE
        @os_type           = UNSET_VALUE
        @full_clone        = UNSET_VALUE
        @serial_port       = UNSET_VALUE
        @vmid              = UNSET_VALUE
        @guest_type        = UNSET_VALUE
        @ostemplate        = UNSET_VALUE
        @unprivileged      = UNSET_VALUE
      end

      def finalize!
        @api_url = nil if @api_url == UNSET_VALUE
        @api_token_id = nil if @api_token_id == UNSET_VALUE
        @api_token_secret = nil if @api_token_secret == UNSET_VALUE
        @vga = 'virtio' if @vga == UNSET_VALUE
        @insecure = false if @insecure == UNSET_VALUE
        @debug = false if @debug == UNSET_VALUE
        @vmname = nil if @vmname == UNSET_VALUE
        @template = nil if @template == UNSET_VALUE
        @disk_size = nil if @disk_size == UNSET_VALUE
        @storage_domain = nil if @storage_domain == UNSET_VALUE
        @cpu_cores = 1 if @cpu_cores == UNSET_VALUE
        @cpu_type = 'host' if @cpu_type == UNSET_VALUE
        @memory_size = '512 MiB' if @memory_size == UNSET_VALUE
        @balloon = @memory_size if @balloon == UNSET_VALUE
        @target_node = nil if @target_node == UNSET_VALUE
        @onboot = false if @onboot == UNSET_VALUE
        @description = '' if @description == UNSET_VALUE
        @nameserver = '' if @nameserver == UNSET_VALUE
        @searchdomain = '' if @searchdomain == UNSET_VALUE
        @os_type = 'l26' if @os_type == UNSET_VALUE
        @full_clone = true if @full_clone == UNSET_VALUE
        @serial_port = false if @serial_port == UNSET_VALUE

        @vmid = nil if @vmid == UNSET_VALUE

        # Problems found while coercing values. Reported from #validate as a
        # normal Vagrant config error, instead of raising here, which
        # aborts Vagrantfile loading with a raw Ruby stack trace. "@__"
        # keeps them out of Config#merge.
        # (@__vmid_range is deliberately not reset: if finalize! runs again,
        # @vmid is already the Integer picked from the range.)
        @__finalize_errors = []

        if @vmid != nil
          if @vmid.is_a?(String) && @vmid.include?('-')
            range = @vmid.split('-').map { |v| Integer(v.strip, exception: false) }
            if range.size != 2 || range.include?(nil) || range[0] > range[1] ||
               range[0] < VMID_MIN || range[1] > VMID_MAX
              @__finalize_errors << I18n.t("vagrant_terraform.config.vmid_range_invalid",
                                           value: @vmid, min: VMID_MIN, max: VMID_MAX)
              @vmid = nil
            else
              # Kept so a VMID conflict at creation can retry with another
              # id from the same range (see #reroll_vmid!).
              @__vmid_range = range[0]..range[1]
              @vmid = rand(@__vmid_range)
            end
          else
            value = @vmid.is_a?(Integer) ? @vmid : Integer(@vmid.to_s.strip, exception: false)
            if value.nil? || value < VMID_MIN || value > VMID_MAX
              @__finalize_errors << I18n.t("vagrant_terraform.config.vmid_invalid",
                                           value: @vmid, min: VMID_MIN, max: VMID_MAX)
              @vmid = nil
            else
              @vmid = value
            end
          end
        end

        if @guest_type == UNSET_VALUE
          @guest_type = :vm
        else
          @guest_type = @guest_type.to_s.to_sym
          unless [:vm, :container].include?(@guest_type)
            @__finalize_errors << I18n.t("vagrant_terraform.config.guest_type_invalid",
                                         value: @guest_type.inspect)
          end
        end

        @ostemplate = nil if @ostemplate == UNSET_VALUE
        @unprivileged = true if @unprivileged == UNSET_VALUE

        @disk_size = parse_size('disk_size', @disk_size) unless @disk_size.nil?
        @memory_size = parse_size('memory_size', @memory_size)
        @balloon = parse_size('balloon', @balloon)
      end

      # Picks a different vmid from the configured range after a VMID
      # conflict. Returns the new vmid, or nil when there is nothing else
      # to try (no range, or a range of one).
      def reroll_vmid!
        return nil if @__vmid_range.nil? || @__vmid_range.size < 2

        candidate = @vmid
        candidate = rand(@__vmid_range) while candidate == @vmid
        @vmid = candidate
      end

      def vmid_from_range?
        !@__vmid_range.nil?
      end

      def validate(machine)
        errors = _detected_errors
        errors.concat(@__finalize_errors || [])

        errors << required('target_node') if @target_node.nil?
        errors << required('storage_domain') if @storage_domain.nil?
        errors << required('disk_size') if @disk_size.nil?
        if @guest_type == :container
          errors << I18n.t("vagrant_terraform.config.required_for_container", field: 'ostemplate') if @ostemplate.nil?
        elsif @template.nil?
          errors << required('template')
        end

        private_networks = machine.config.vm.networks.select { |type, _| type == :private_network }
        private_networks.each do |_, options|
          ip = options[:terraform__ip]
          if !ip.nil? && !ip.to_s.include?("/")
            errors << I18n.t("vagrant_terraform.config.ip_not_cidr", value: ip)
          end
          if options[:terraform__network_name].nil?
            errors << I18n.t("vagrant_terraform.config.network_name_missing")
          end
        end

        # Only private networks become container NICs, and the IP is read
        # from eth0. Without one the container gets no interface at all and
        # `vagrant up` would just time out waiting for an IP.
        if @guest_type == :container && private_networks.empty?
          errors << I18n.t("vagrant_terraform.config.container_no_network")
        end

        { "Terraform Provider" => errors }
      end

      private

      def required(field)
        I18n.t("vagrant_terraform.config.required", field: field)
      end

      # Parses a human-readable size ("2 GiB", "8 GB", or a byte count) into
      # bytes. On failure records an error and returns the value unchanged.
      def parse_size(field, value)
        Filesize.from(value.to_s).to_f('B').to_i
      rescue ArgumentError
        @__finalize_errors << I18n.t("vagrant_terraform.config.size_unparsable", field: field, value: value)
        value
      end

    end
  end
end

