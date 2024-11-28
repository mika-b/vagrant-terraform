# -*- encoding: utf-8 -*-
require File.expand_path('../lib/vagrant-terraform/version', __FILE__)

Gem::Specification.new do |gem|
  gem.authors       = ["Mika Båtsman"]
  gem.email         = ["mika.batsman@gmail.com"]
  gem.description   = %q{Vagrant provider for proxmox using terraform}
  gem.summary       = %q{This vagrant plugin provides the ability to create, control, and destroy virtual machines under proxmox}
  gem.homepage      = "https://github.com/mika-b/vagrant-terraform"
  gem.licenses      = ['MIT']

  gem.files         = `git ls-files`.split($\)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.name          = "vagrant-terraform"
  gem.require_paths = ["lib"]
  gem.version       = VagrantPlugins::TerraformProvider::VERSION

  gem.add_runtime_dependency 'filesize', '~> 0'
  gem.required_ruby_version = '>= 3.0.0'
end
