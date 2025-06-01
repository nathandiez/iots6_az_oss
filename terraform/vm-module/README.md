# Terraform Proxmox VM Module

A reusable Terraform module for creating virtual machines on Proxmox.

## Features

- Clones from a template VM
- Configures CPU, memory, and disk
- Sets up networking with either DHCP or static IP
- Configures cloud-init for user access
- Supports custom tags

## Usage

```hcl
module "my_vm" {
  source = "git::https://github.com/yourusername/terraform-proxmox.git"
  
  vm_name     = "my-server"
  mac_address = "52:54:00:12:34:56"
  
  # Optional: override defaults
  cores       = 4
  memory      = 4096
  disk_size   = 40
  tags        = ["terraform-managed", "production"]
  
  # Optional: use static IP instead of DHCP
  use_dhcp    = false
  static_ip   = "192.168.1.100/24"
  gateway     = "192.168.1.1"
}

output "server_ip" {
  value = module.my_vm.primary_ip
}
```

## Requirements

- Terraform 1.0+
- Proxmox provider plugin (bpg/proxmox ~> 0.76)
- A Proxmox template VM to clone

## Input Variables

| Name                | Description                              | Type         | Default                    |
| ------------------- | ---------------------------------------- | ------------ | -------------------------- |
| vm_name             | Name of the virtual machine              | string       | (Required)                 |
| node_name           | Name of the Proxmox node                 | string       | "proxmox-asus"             |
| tags                | Tags to apply to the VM                  | list(string) | ["terraform-managed"]      |
| template_id         | ID of the template to clone              | number       | 9002                       |
| cores               | Number of CPU cores                      | number       | 2                          |
| memory              | Memory in MB                             | number       | 2048                       |
| mac_address         | MAC address for the VM                   | string       | (Required)                 |
| disk_size           | Disk size in GB                          | number       | 25                         |
| datastore_id        | Proxmox datastore ID for VM disks        | string       | "local-lvm"                |
| dns_servers         | List of DNS servers                      | list(string) | ["192.168.6.1", "8.8.8.8"] |
| ssh_username        | Username for SSH access                  | string       | "nathan"                     |
| ssh_public_key_path | Path to SSH public key file              | string       | "~/.ssh/id_ed25519.pub"  |
| use_dhcp            | Whether to use DHCP for IP configuration | bool         | true                       |
| static_ip           | Static IP address in CIDR notation       | string       | ""                         |
| gateway             | Network gateway                          | string       | ""                         |

## Outputs

| Name           | Description                         |
| -------------- | ----------------------------------- |
| vm_id          | ID of the created VM                |
| vm_name        | Name of the VM                      |
| mac_address    | MAC address of VM network interface |
| ipv4_addresses | IPv4 addresses assigned to the VM   |
| primary_ip     | Primary IP address of the VM        |

## Example: Using With Multiple Projects

### Adding as a Git Submodule

```bash
# In your project
cd your-project/terraform
git submodule add https://github.com/yourusername/terraform-proxmox.git base-module
```

### Using in Your Project

```hcl
module "app_server" {
  source = "./base-module"
  
  vm_name     = "app-server"
  mac_address = "52:54:00:12:34:56"
}
```