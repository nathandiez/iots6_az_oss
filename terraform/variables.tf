# terraform/variables.tf - Azure version for IoTS6

variable "azure_location" {
  description = "Azure region for resources"
  type        = string
  default     = "East US"
}

variable "resource_group" {
  description = "Name of the Azure resource group"
  type        = string
  default     = "rg-iots6"
}

variable "project_name" {
  description = "Name of the project (used for resource naming)"
  type        = string
  default     = "aziots6"
}

variable "vm_name" {
  description = "Name of the Azure VM"
  type        = string
  default     = "aziots6"
}

variable "instance_type" {
  description = "Azure VM size"
  type        = string
  default     = "Standard_B2s"
}

variable "disk_size_gb" {
  description = "OS disk size in GB"
  type        = number
  default     = 40
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

variable "ssh_key_name" {
  description = "Name for the SSH key"
  type        = string
  default     = "aziots6-key"
}

variable "enable_local_exec" {
  description = "Enable local-exec provisioners for automated deployment"
  type        = bool
  default     = false
}

# Database variables for service URLs
variable "postgres_db" {
  description = "PostgreSQL database name"
  type        = string
  default     = "iotdb"
}

variable "postgres_user" {
  description = "PostgreSQL username"
  type        = string
  default     = "iotuser"
}

variable "postgres_password" {
  description = "PostgreSQL password"
  type        = string
  default     = "iotpass"
  sensitive   = true
}