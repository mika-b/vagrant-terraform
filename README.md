# Vagrant Terraform Provider

This is an experimental [Vagrant](http://www.vagrantup.com) plugin for Proxmox that uses
Terraform under the hood to operate the virtual machines.

Could be extended to support other Terraform providers in addition to Proxmox but at
the moment I'm not planning to.

Things I'm _not_ planning to do (due to lack of time and resources):
* Put this in rubygems.org. If you want to use this, roll your own gem like instructed below.
* Support other Terraform providers unless I have to move away from Proxmox to something else.
* Add support for suspend / snapshots.
* Support / test anything other than Ubuntu/Fedora
* Support Ruby 2.x

## Installation

```
$ gem build *.gemspec
$ vagrant plugin install *.gem
```

## Usage

### Prerequisites

#### Requirements

Tested on Ubuntu 22.04 and Fedora 40.

[Terraform](https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli)

#### Configuration

Create API user
https://registry.terraform.io/providers/Telmate/proxmox/latest/docs#creating-the-proxmox-user-and-role-for-terraform
```
pveum role add Terraform -privs "Datastore.AllocateSpace Datastore.AllocateTemplate Datastore.Audit Pool.Allocate Sys.Audit Sys.Console Sys.Modify VM.Allocate VM.Audit VM.Clone VM.Config.CDROM VM.Config.Cloudinit VM.Config.CPU VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options VM.Migrate VM.Monitor VM.PowerMgmt SDN.Use"

pveum user add terraform@pve
pveum aclmod / -user terraform@pve -role Terraform
pveum user token add terraform@pve automation --privsep 0
```
The value on the last line is your API token secret you are going to need in your Vagrantfile.

Privilege separation needs to be disabled from API key due to:
https://github.com/Telmate/terraform-provider-proxmox/issues/784

#### Prepare a VM template on your Proxmox PVE

Download cloud image
```
wget https://cloud-images.ubuntu.com/noble/current/SHA256SUMS https://cloud-images.ubuntu.com/noble/current/SHA256SUMS.gpg https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img
gpg --keyid-format long --verify SHA256SUMS.gpg SHA256SUMS  # Requires public key "UEC Image Automatic Signing Key <cdimage@ubuntu.com>"
sha256sum -c --ignore-missing SHA256SUMS
```

Customize it the way you want with virt-customize
```
export LIBGUESTFS_BACKEND=direct; virt-customize -a noble-server-cloudimg-amd64.img --install qemu-guest-agent --run-command "truncate -s 0 /etc/machine-id /var/lib/dbus/machine-id"
```

Create a VM and convert it to template
```
qm create 9001 --memory 1024 --net0 virtio,bridge=vmbr0 --scsihw virtio-scsi-pci --name ubuntu-noble-template --machine q35,viommu=virtio --ostype l26 --rng0 /dev/urandom
qm set 9001 --virtio0 [STORAGE_NAME]:0,import-from=/root/noble-server-cloudimg-amd64.img
qm set 9001 --ide2 [STORAGE_NAME]:cloudinit --boot c --bootdisk virtio0
qm template 9001
```


### Supported Commands

1. `vagrant up`
1. `vagrant destroy`
1. `vagrant ssh [-c 'command']`
1. `vagrant ssh-config`
1. `vagrant halt`
1. `vagrant reload`
1. `vagrant status`

### Simple configuration example with two network interfaces

```
Vagrant.configure("2") do |config|
  config.vm.box = 'dummy'
  config.vm.box_url = 'https://github.com/mika-b/vagrant-terraform/blob/master/example_box/dummy.box?raw=true'

  config.vm.hostname = "example-vm.local"

  config.vm.synced_folder './', '/vagrant', type: 'rsync', rsync__exclude: ["log/", ".git/"]  # , rsync__verbose: false
  config.ssh.forward_agent = true

  config.vm.network :private_network,
    :terraform__network_name => 'testmgmt' # DHCP
  config.vm.network :private_network,
    :terraform__network_name => 'vmbr0', :terraform__ip => '192.168.0.51/24', :terraform__gateway => '192.168.0.1'

  config.vm.provider :terraform do |terraform|
    terraform.api_url = 'https://[PVE_ADDRESS]:8006/api2/json'
    terraform.api_token_id = "terraform@pve!automation"
    terraform.api_token_secret = "[API_TOKEN]"
    terraform.insecure = true
    terraform.debug = false
    terraform.description = "Created by: #{ENV['USER']}"
    terraform.template = 'ubuntu-noble-template'
    terraform.cpu_cores = 2
    terraform.memory_size = '4 GiB'
    terraform.disk_size = '15 GB'
    terraform.target_node = 'pve1'
    terraform.storage_domain = '[STORAGE_NAME]'
    terraform.nameserver = '1.1.1.1 1.0.0.1'
    terraform.searchdomain = 'example.com'
  end

  config.vm.provision "shell", inline: <<-SHELL
    ip a
SHELL
end
```
