variable "vm_name" {
  description = "Name of the virtual machine"
  type        = string
}

variable "node_name" {
  description = "Name of the Proxmox node"
  type        = string
  default     = "proxmox-asus"
}

variable "tags" {
  description = "Tags to apply to the VM"
  type        = list(string)
  default     = ["terraform-managed"]
}

variable "template_id" {
  description = "ID of the template to clone"
  type        = number
  default     = 9002
}

variable "cores" {
  description = "Number of CPU cores"
  type        = number
  default     = 2
}

variable "memory" {
  description = "Memory in MB"
  type        = number
  default     = 2048
}

variable "mac_address" {
  description = "MAC address for the VM"
  type        = string
}

variable "disk_size" {
  description = "Disk size in GB"
  type        = number
  default     = 25
}

variable "datastore_id" {
  description = "Proxmox datastore ID for VM disks"
  type        = string
  default     = "local-lvm"
}

variable "dns_servers" {
  description = "List of DNS servers"
  type        = list(string)
  default     = ["192.168.6.1", "8.8.8.8"]
}

variable "ssh_username" {
  description = "Username for SSH access"
  type        = string
  default     = "nathan"
}

variable "ssh_public_key_path" {
  description = "Path to SSH public key file"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

# Optional: Add these variables if you want to support static IP configuration
variable "use_dhcp" {
  description = "Whether to use DHCP for IP configuration"
  type        = bool
  default     = true
}

variable "static_ip" {
  description = "Static IP address in CIDR notation (e.g., 192.168.1.100/24)"
  type        = string
  default     = ""
}

variable "gateway" {
  description = "Network gateway"
  type        = string
  default     = ""
}