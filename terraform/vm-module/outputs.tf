# terraform/vm-module/outputs.tf for IoTs6

output "vm_id" {
  description = "ID of the created VM"
  value       = azurerm_linux_virtual_machine.main.id
}

output "vm_name" {
  description = "Name of the VM"
  value       = azurerm_linux_virtual_machine.main.name
}

output "public_ip" {
  description = "Public IP address of the VM"
  value       = azurerm_public_ip.main.ip_address
}

output "private_ip" {
  description = "Private IP address of the VM"
  value       = azurerm_network_interface.main.private_ip_address
}

output "fqdn" {
  description = "Fully qualified domain name"
  value       = azurerm_public_ip.main.fqdn
}

output "ssh_connection" {
  description = "SSH connection string"
  value       = "${var.admin_username}@${azurerm_public_ip.main.ip_address}"
}