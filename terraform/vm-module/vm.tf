# vm.tf

terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.76"
    }
  }
}

resource "proxmox_virtual_environment_vm" "vm" {
  name      = var.vm_name
  node_name = var.node_name
  tags      = var.tags

  # VM Template Source
  clone {
    vm_id = var.template_id
    full  = false
  }

  # QEMU Guest Agent
  agent {
    enabled = true
    trim    = true
  }

  # Hardware Configuration
  cpu {
    cores = var.cores
  }
  
  memory {
    dedicated = var.memory
  }
  
  network_device {
    bridge      = "vmbr0"
    mac_address = var.mac_address
    model       = "virtio"
    firewall    = false  # Sometimes helps with DHCP issues
  }

  # Disk Configuration
  disk {
    interface    = "scsi0"
    datastore_id = var.datastore_id
    size         = var.disk_size
    # Removed iothread that was causing warnings
  }

  # Operating System Type
  operating_system {
    type = "l26"
  }

  # Cloud-Init Configuration
  initialization {
    datastore_id = var.datastore_id
    
    # The hostname goes inside the ip_config
    ip_config {
      ipv4 {
        address = var.use_dhcp ? "dhcp" : var.static_ip
        gateway = var.use_dhcp ? null : var.gateway
      }
    }

    dns {
      servers = var.dns_servers
    }

    user_account {
      username = var.ssh_username
      keys     = [file(var.ssh_public_key_path)]
    }
  }
}