require 'vagrant'
require 'filesize'

module VagrantPlugins
  module TerraformProvider
    class Config < Vagrant.plugin('2', :config)
      attr_reader :disks

      attr_accessor :api_url
      attr_accessor :api_token_id
      attr_accessor :api_token_secret
      attr_accessor :insecure
      attr_accessor :debug
      attr_accessor :vmname
      attr_accessor :template
      attr_accessor :disk_size
      attr_accessor :storage_domain
      attr_accessor :cpu_cores
      attr_accessor :memory_size
      attr_accessor :target_node
      attr_accessor :onboot
      attr_accessor :description
      attr_accessor :nameserver
      attr_accessor :searchdomain
      attr_accessor :os_type
      attr_accessor :full_clone

      def initialize
        @api_url           = UNSET_VALUE
        @api_token_id      = UNSET_VALUE
        @api_token_secret  = UNSET_VALUE
        @insecure          = UNSET_VALUE
        @debug             = UNSET_VALUE
        @vmname            = UNSET_VALUE
        @template          = UNSET_VALUE
        @disk_size         = UNSET_VALUE
        @storage_domain    = UNSET_VALUE
        @cpu_cores         = UNSET_VALUE
        @memory_size       = UNSET_VALUE
        @target_node       = UNSET_VALUE
        @onboot            = UNSET_VALUE
        @description       = UNSET_VALUE
        @nameserver        = UNSET_VALUE
        @searchdomain      = UNSET_VALUE
        @os_type           = UNSET_VALUE
        @full_clone        = UNSET_VALUE
      end

      def finalize!
        @api_url = nil if @api_url == UNSET_VALUE
        @api_token_id = nil if @api_token_id == UNSET_VALUE
        @api_token_secret = nil if @api_token_secret == UNSET_VALUE
        @insecure = false if @insecure == UNSET_VALUE
        @debug = false if @debug == UNSET_VALUE
        @vmname = nil if @vmname == UNSET_VALUE
        @template = nil if @template == UNSET_VALUE
        @disk_size = nil if @disk_size == UNSET_VALUE
        @storage_domain = nil if @storage_domain == UNSET_VALUE
        @cpu_cores = 1 if @cpu_cores == UNSET_VALUE
        @memory_size = '512 MiB' if @memory_size == UNSET_VALUE
        @target_node = nil if @target_node == UNSET_VALUE
        @onboot = false if @onboot == UNSET_VALUE
        @description = '' if @description == UNSET_VALUE
        @nameserver = '' if @nameserver == UNSET_VALUE
        @searchdomain = '' if @searchdomain == UNSET_VALUE
        @os_type = 'l26' if @os_type == UNSET_VALUE
        @full_clone = true if @full_clone == UNSET_VALUE

        unless disk_size.nil?
          begin
            @disk_size = Filesize.from(@disk_size).to_f('B').to_i
          rescue ArgumentError
            raise "Not able to parse 'disk_size' #{@disk_size}."
          end
        end

        begin
          @memory_size = Filesize.from(@memory_size).to_f('B').to_i
        rescue ArgumentError
          raise "Not able to parse `memory_size`."
        end
      end

    end
  end
end

