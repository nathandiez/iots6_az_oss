terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.76"
    }
  }
}

# Variable to control whether to run provisioners
variable "enable_local-exec" {
  description = "Whether to run the local-exec provisioners (IP detection and Ansible)"
  type        = bool
  default     = false
}

provider "proxmox" {
  endpoint = "https://192.168.5.6:8006"
  insecure = true
}

module "nedv1-iots6_server" {
  source = "./vm-module"
  
  vm_name     = "nedv1-iots6"
  mac_address = "52:54:00:12:23:22"
  cores       = 4
  memory      = 4096
  disk_size   = 40
}

# Wait for VM to get IP and be accessible
resource "time_sleep" "wait_for_vm" {
  depends_on = [module.nedv1-iots6_server]
  create_duration = "60s"
}

# Run Ansible playbook after VM is ready (conditional)
resource "null_resource" "run_ansible" {
  count = var.enable_local-exec ? 1 : 0

  depends_on = [
    time_sleep.wait_for_vm
  ]

  triggers = {
    vm_id = module.nedv1-iots6_server.vm_id
  }

  # Wait for SSH and update inventory
  provisioner "local-exec" {
    command = "./scripts/wait-for-ssh.sh"
  }

  # Run Ansible playbook
  provisioner "local-exec" {
    command = "./scripts/run-ansible.sh"
  }

  # Verify deployment
  provisioner "local-exec" {
    command = "./scripts/verify-deployment.sh"
  }
}

# Outputs - find the real IP from the arrays
locals {
  all_ips = try(module.nedv1-iots6_server.ipv4_addresses, [])
  
  valid_ip = try(
    flatten([
      for ip_array in local.all_ips : [
        for ip in ip_array : ip
        if ip != "127.0.0.1" && ip != "172.17.0.1" && ip != "" && ip != null
      ]
    ])[0],
    null
  )
}

output "server_ip" {
  value = local.valid_ip != null ? local.valid_ip : "Not yet available - VM may still be starting"
  description = "Server IP address"
}

output "vm_id" {
  value = module.nedv1-iots6_server.vm_id
  description = "Proxmox VM ID"
}

output "vm_ip" {
  value = local.valid_ip != null ? local.valid_ip : "Not yet available - VM may still be starting"
  description = "VM IP address"
}


output "vm_name" {
  value = module.nedv1-iots6_server.vm_name
}

output "mac_address" {
  value = module.nedv1-iots6_server.mac_address
}

# Service URLs (will be available after deployment)
output "service_urls" {
  value = local.valid_ip != null ? {
    timescaledb = "postgresql://iotuser:iotpass@${local.valid_ip}:5432/iotdb"
    mosquitto   = "mqtt://${local.valid_ip}:1883"
    ssh_access  = "nathan@${local.valid_ip}"
  } : {
    timescaledb = "Not yet available - VM may still be starting"
    mosquitto   = "Not yet available - VM may still be starting"
    ssh_access  = "Not yet available - VM may still be starting"
  }
  description = "IoT service connection URLs"
}