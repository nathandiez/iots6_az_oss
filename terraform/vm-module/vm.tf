# terraform/vm-module/vm.tf for IoTs6

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

# Public IP
resource "azurerm_public_ip" "main" {
  name                = "pip-${var.vm_name}"
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Static"
  sku                = "Standard"
}

# Network interface
resource "azurerm_network_interface" "main" {
  name                = "nic-${var.vm_name}"
  location            = var.location
  resource_group_name = var.resource_group_name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.main.id
  }
}

# Associate Network Security Group to Network Interface
resource "azurerm_network_interface_security_group_association" "main" {
  network_interface_id      = azurerm_network_interface.main.id
  network_security_group_id = var.network_security_group_id
}

# Virtual Machine
resource "azurerm_linux_virtual_machine" "main" {
  name                = var.vm_name
  resource_group_name = var.resource_group_name
  location            = var.location
  size                = var.vm_size
  admin_username      = var.admin_username

  # Disable password authentication, use SSH keys only
  disable_password_authentication = true

  network_interface_ids = [
    azurerm_network_interface.main.id,
  ]

  admin_ssh_key {
    username   = var.admin_username
    public_key = file(var.ssh_public_key_path)
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = var.disk_size_gb
  }

  source_image_reference {
    publisher = var.vm_image.publisher
    offer     = var.vm_image.offer
    sku       = var.vm_image.sku
    version   = var.vm_image.version
  }

  # Cloud-init to install basic packages and prepare for IoT services
  custom_data = base64encode(<<-EOF
    #cloud-config
    package_update: true
    packages:
      - curl
      - wget
      - python3-pip
      - apt-transport-https
      - ca-certificates
      - gnupg
      - lsb-release
      - postgresql-client  # For database connectivity testing
      - mosquitto-clients  # For MQTT testing
    
    # Set timezone
    timezone: America/New_York
    
    # Ensure SSH is enabled and running
    ssh_pwauth: false
    
    runcmd:
      # Ensure the admin user is in the sudo group
      - usermod -aG sudo ${var.admin_username}
      # Wait a bit for network to be fully ready
      - sleep 30
  EOF
  )
}