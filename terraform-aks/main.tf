# terraform-aks/main.tf - Azure AKS cluster for IoTS6
terraform {
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

# Variables
variable "location" {
  description = "Azure region"
  type        = string
  default     = "East US"
}

variable "resource_group" {
  description = "Resource group name"
  type        = string
  default     = "rg-iots6-aks"
}

variable "cluster_name" {
  description = "AKS cluster name"
  type        = string
  default     = "iots6-aks"
}

variable "node_count" {
  description = "Number of nodes in the AKS cluster"
  type        = number
  default     = 3
}

variable "node_size" {
  description = "Size of the AKS nodes"
  type        = string
  default     = "Standard_D2s_v3"
}

# Data sources
data "azurerm_client_config" "current" {}

# Resource Group
resource "azurerm_resource_group" "aks" {
  name     = var.resource_group
  location = var.location

  tags = {
    Project = "iots6"
  }
}

# Virtual Network
resource "azurerm_virtual_network" "aks" {
  name                = "${var.cluster_name}-vnet"
  location            = azurerm_resource_group.aks.location
  resource_group_name = azurerm_resource_group.aks.name
  address_space       = ["10.0.0.0/16"]

  tags = {
    Project = "iots6"
  }
}

# Public Subnet
resource "azurerm_subnet" "public" {
  name                 = "${var.cluster_name}-public-subnet"
  resource_group_name  = azurerm_resource_group.aks.name
  virtual_network_name = azurerm_virtual_network.aks.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Private Subnet for AKS
resource "azurerm_subnet" "private" {
  name                 = "${var.cluster_name}-private-subnet"
  resource_group_name  = azurerm_resource_group.aks.name
  virtual_network_name = azurerm_virtual_network.aks.name
  address_prefixes     = ["10.0.10.0/24"]
}

# AKS Cluster
resource "azurerm_kubernetes_cluster" "main" {
  name                = var.cluster_name
  location            = azurerm_resource_group.aks.location
  resource_group_name = azurerm_resource_group.aks.name
  dns_prefix          = "${var.cluster_name}-dns"

  default_node_pool {
    name           = "default"
    node_count     = var.node_count
    vm_size        = var.node_size
    vnet_subnet_id = azurerm_subnet.private.id

    enable_auto_scaling = true
    min_count          = var.node_count
    max_count          = var.node_count + 2
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin = "kubenet"
    service_cidr   = "10.1.0.0/16"
    dns_service_ip = "10.1.0.10"
  }

  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  tags = {
    Project = "iots6"
  }
}

# Outputs
output "cluster_endpoint" {
  description = "Endpoint for AKS control plane"
  value       = azurerm_kubernetes_cluster.main.kube_config[0].host
  sensitive   = true
}

output "cluster_name" {
  description = "AKS cluster name"
  value       = azurerm_kubernetes_cluster.main.name
}

output "cluster_id" {
  description = "AKS cluster ID"
  value       = azurerm_kubernetes_cluster.main.id
}

output "resource_group_name" {
  description = "Resource group name"
  value       = azurerm_resource_group.aks.name
}

output "vnet_id" {
  description = "Virtual Network ID"
  value       = azurerm_virtual_network.aks.id
}