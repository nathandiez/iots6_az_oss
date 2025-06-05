# aks-main.tf - Azure Kubernetes Service cluster for IoTS6
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

# Azure provider configuration
provider "azurerm" {
  features {}
}

# Resource group
resource "azurerm_resource_group" "aks" {
  name     = "rg-iots6"
  location = "East US"
}

# AKS Cluster with 3 nodes
resource "azurerm_kubernetes_cluster" "main" {
  name                = "cluster-iots6"
  location            = azurerm_resource_group.aks.location
  resource_group_name = azurerm_resource_group.aks.name
  dns_prefix          = "dns-iots6"

  default_node_pool {
    name       = "default"
    node_count = 3
    vm_size    = "Standard_B2s"  # Same size as your current VM
    
    # Enable auto-scaling (optional, but recommended)
    enable_auto_scaling = true
    min_count          = 3
    max_count          = 5
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin = "kubenet"
    service_cidr   = "10.1.0.0/16"
    dns_service_ip = "10.1.0.10"
  }

  tags = {
    Environment = "IoT"
    Project     = "aziots6"
  }
}

# Output kubeconfig for kubectl access
resource "local_file" "kubeconfig" {
  content  = azurerm_kubernetes_cluster.main.kube_config_raw
  filename = "${path.module}/kubeconfig"
}

# Outputs
output "cluster_name" {
  value = azurerm_kubernetes_cluster.main.name
}

output "resource_group_name" {
  value = azurerm_resource_group.aks.name
}

output "kubeconfig_path" {
  value = "${path.module}/kubeconfig"
}

output "cluster_fqdn" {
  value = azurerm_kubernetes_cluster.main.fqdn
}