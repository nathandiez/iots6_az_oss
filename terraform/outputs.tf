# terraform/outputs.tf - Azure outputs for IoTS6

output "instance_id" {
  description = "ID of the Azure VM"
  value       = module.aziots6-vm.vm_id
}

output "vm_name" {
  description = "Name of the Azure VM"
  value       = module.aziots6-vm.vm_name
}

output "public_ip" {
  description = "Public IP address of the Azure VM"
  value       = module.aziots6-vm.public_ip
}

output "vm_ip" {
  description = "Public IP address (alias for compatibility)"
  value       = module.aziots6-vm.public_ip
}

output "private_ip" {
  description = "Private IP address of the Azure VM"
  value       = module.aziots6-vm.private_ip
}

output "public_dns" {
  description = "Public DNS name of the Azure VM"
  value       = module.aziots6-vm.fqdn
}

output "ssh_connection" {
  description = "SSH connection string"
  value       = module.aziots6-vm.ssh_connection
}

output "resource_group_id" {
  description = "ID of the resource group"
  value       = azurerm_resource_group.main.id
}

output "vnet_id" {
  description = "ID of the virtual network"
  value       = azurerm_virtual_network.main.id
}

output "subnet_id" {
  description = "ID of the subnet"
  value       = azurerm_subnet.internal.id
}

output "security_group_id" {
  description = "ID of the network security group"
  value       = azurerm_network_security_group.main.id
}