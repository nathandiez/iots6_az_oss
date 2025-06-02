# main.tf for Azure IoTS6 deployment

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

# Variable to control whether to run provisioners
variable "enable_local-exec" {
  description = "Whether to run the local-exec provisioners (IP detection and Ansible)"
  type        = bool
  default     = false
}

# Azure provider configuration
provider "azurerm" {
  features {}
}

# Resource group
resource "azurerm_resource_group" "main" {
  name     = "rg-aziots6"
  location = "East US"
}

# Virtual network
resource "azurerm_virtual_network" "main" {
  name                = "vnet-aziots6"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
}

# Subnet
resource "azurerm_subnet" "internal" {
  name                 = "subnet-internal"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.2.0/24"]
}

# Network Security Group and rules for IoT services
resource "azurerm_network_security_group" "main" {
  name                = "nsg-aziots6"
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

  # Optional: Add HTTP port if you plan to add web frontend
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
  # Add this security rule to your main.tf file in the azurerm_network_security_group "main" resource

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
}

# Call the VM module
module "aziots6-vm" {
  source = "./vm-module"
  
  vm_name             = "aziots6"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  subnet_id           = azurerm_subnet.internal.id
  network_security_group_id = azurerm_network_security_group.main.id
  
  # Larger VM for IoT services (TimescaleDB, MQTT, etc.)
  vm_size = "Standard_B2s"  # 2 vCPU, 4GB RAM
  disk_size_gb = 40
}

# Wait for VM to be ready
resource "time_sleep" "wait_for_vm" {
  depends_on = [module.aziots6-vm]
  create_duration = "60s"
}

# Run Ansible playbook after VM is ready (conditional)
resource "null_resource" "run_ansible" {
  count = var.enable_local-exec ? 1 : 0

  depends_on = [
    time_sleep.wait_for_vm
  ]

  triggers = {
    vm_id = module.aziots6-vm.vm_id
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
    timescaledb = "postgresql://iotuser:iotpass@${module.aziots6-vm.public_ip}:5432/iotdb"
    mosquitto   = "mqtt://${module.aziots6-vm.public_ip}:1883"
    ssh_access  = "nathan@${module.aziots6-vm.public_ip}"
  }
  description = "IoT service connection URLs"
}