output "vm_id" {
  description = "ID of the created VM"
  value       = proxmox_virtual_environment_vm.vm.id
}

output "vm_name" {
  description = "Name of the VM"
  value       = proxmox_virtual_environment_vm.vm.name
}

output "mac_address" {
  description = "MAC address of VM network interface"
  value       = proxmox_virtual_environment_vm.vm.network_device[0].mac_address
}

output "ipv4_addresses" {
  description = "IPv4 addresses assigned to the VM"
  value       = proxmox_virtual_environment_vm.vm.ipv4_addresses
}

output "primary_ip" {
  description = "Primary IP address of the VM (first non-loopback)"
  value       = try(
    proxmox_virtual_environment_vm.vm.ipv4_addresses != null ? 
      (length(proxmox_virtual_environment_vm.vm.ipv4_addresses) > 0 ? 
        (length(proxmox_virtual_environment_vm.vm.ipv4_addresses[0]) > 0 ? 
          proxmox_virtual_environment_vm.vm.ipv4_addresses[0][0] : 
          "No IP assigned yet") : 
        "No IP assigned yet") : 
      "No IP assigned yet", 
    "No IP assigned yet"
  )
}