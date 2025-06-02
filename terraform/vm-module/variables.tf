# terraform/vm-module/variables.tf for IoTS6

variable "vm_name" {
  description = "Name of the virtual machine"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the Azure resource group"
  type        = string
}

variable "location" {
  description = "Azure region for resources"
  type        = string
}

variable "subnet_id" {
  description = "ID of the subnet to place the VM in"
  type        = string
}

variable "network_security_group_id" {
  description = "ID of the network security group"
  type        = string
}

variable "vm_size" {
  description = "Size of the Azure VM"
  type        = string
  default     = "Standard_B2s"  # 2 vCPU, 4GB RAM for IoT services
}

variable "admin_username" {
  description = "Admin username for the VM"
  type        = string
  default     = "nathan"
}

variable "ssh_public_key_path" {
  description = "Path to SSH public key file"
  type        = string
  default     = "~/.ssh/id_rsa_azure.pub"
}

# Ubuntu image configuration
variable "vm_image" {
  description = "VM image configuration"
  type = object({
    publisher = string
    offer     = string
    sku       = string
    version   = string
  })
  default = {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }
}

variable "disk_size_gb" {
  description = "OS disk size in GB"
  type        = number
  default     = 40  # Larger disk for TimescaleDB data
}