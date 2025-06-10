# terraform/main.tf - Azure version of IoTS6 with local-exec provisioners
terraform {
  required_version = ">= 1.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# Resource group
resource "azurerm_resource_group" "main" {
  name     = var.resource_group
  location = var.azure_location
}

# Virtual network
resource "azurerm_virtual_network" "main" {
  name                = "${var.project_name}-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  tags = {
    Project = var.project_name
  }
}

# Subnet
resource "azurerm_subnet" "internal" {
  name                 = "${var.project_name}-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.2.0/24"]
}

# Network Security Group and rules for IoT services
resource "azurerm_network_security_group" "main" {
  name                = "${var.project_name}-nsg"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  security_rule {
    name                       = "SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "MQTT"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "1883"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "PostgreSQL"
    priority                   = 1003
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "5432"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "HTTP"
    priority                   = 1004
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "HTTPS"
    priority                   = 1005
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Grafana"
    priority                   = 1006
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3000"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = {
    Project = var.project_name
  }
}

# Call the VM module
module "aziots6-vm" {
  source = "./vm-module"
  
  vm_name             = var.vm_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  subnet_id           = azurerm_subnet.internal.id
  network_security_group_id = azurerm_network_security_group.main.id
  
  vm_size = var.instance_type
  disk_size_gb = var.disk_size_gb
  admin_username = var.admin_username
  ssh_public_key_path = var.ssh_public_key_path
}

# Wait for VM to be ready
resource "time_sleep" "wait_for_vm" {
  depends_on = [module.aziots6-vm]
  create_duration = "60s"
}

# Run Ansible playbook after VM is ready (conditional)
resource "null_resource" "run_ansible" {
  count = var.enable_local_exec ? 1 : 0

  depends_on = [
    time_sleep.wait_for_vm
  ]

  triggers = {
    vm_id = module.aziots6-vm.vm_id
  }

  # Wait for SSH and update inventory
  provisioner "local-exec" {
    command = "${path.module}/scripts/wait-for-ssh.sh"
    environment = {
      VM_IP = module.aziots6-vm.public_ip
    }
  }

  # Run Ansible playbook
  provisioner "local-exec" {
    command = "${path.module}/scripts/run-ansible.sh"
    environment = {
      VM_IP = module.aziots6-vm.public_ip
    }
  }

  # Verify deployment
  provisioner "local-exec" {
    command = "${path.module}/scripts/verify-deployment.sh"
    environment = {
      VM_IP = module.aziots6-vm.public_ip
    }
  }
}

# Outputs
output "vm_id" {
  value = module.aziots6-vm.vm_id
  description = "Azure VM ID"
}

output "server_ip" {
  value = module.aziots6-vm.public_ip
  description = "Server IP address"
}

output "vm_ip" {
  value = module.aziots6-vm.public_ip
  description = "VM IP address"
}

output "vm_private_ip" {
  value = module.aziots6-vm.private_ip
  description = "VM private IP address"
}

output "vm_name" {
  value = module.aziots6-vm.vm_name
  description = "VM name"
}

# Service URLs for IoT stack
output "service_urls" {
  value = {
    timescaledb = "postgresql://${var.postgres_user}:${var.postgres_password}@${module.aziots6-vm.public_ip}:5432/${var.postgres_db}"
    mosquitto   = "mqtt://${module.aziots6-vm.public_ip}:1883"
    ssh_access  = "${var.admin_username}@${module.aziots6-vm.public_ip}"
  }
  description = "IoT service connection URLs"
}