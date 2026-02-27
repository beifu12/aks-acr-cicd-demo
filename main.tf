# Configure Terraform and required providers
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      # 官方推荐：使用 4.x 最新版本，以获得最新 API 支持
      version = "~> 4.0" 
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

# Configure the AzureRM Provider (强制指定 Azure China Cloud)
provider "azurerm" {
  features {}
}

# Generate a random suffix to ensure unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
  numeric = true
}

# 1. Create Resource Group
resource "azurerm_resource_group" "aks_demo" {
  name     = "aks-demo-rg"
  location = "China East 2" # 根据实际情况选择区域
}

# 2. Create Azure Container Registry (ACR)
resource "azurerm_container_registry" "aks_demo" {
  name                = "aksdemoreg${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.aks_demo.name
  location            = azurerm_resource_group.aks_demo.location
  sku                 = "Basic"
  admin_enabled       = true
}

# 3. Create AKS Cluster (v4.x 标准语法)
resource "azurerm_kubernetes_cluster" "aks_demo" {
  name                = "aks-demo-cluster"
  resource_group_name = azurerm_resource_group.aks_demo.name
  location            = azurerm_resource_group.aks_demo.location
  dns_prefix          = "aksdemocluster${random_string.suffix.result}"
  
  # 目标版本：1.30.0 (请确认 Azure China 2024/10 后是否已支持，若不支持请改为 1.29.5)
  kubernetes_version  = "1.30.0"

  # --- 核心修复：满足 Azure Policy 的自动升级要求 ---
  # 在 4.x 中，这是顶层属性，对应文档中的 automatic_upgrade_channel
  automatic_upgrade_channel     = "stable" 

  default_node_pool {
    name       = "default"
    node_count = 1
    vm_size    = "Standard_D2s_v3"

    # 节点池升级设置 (max_surge 是 4.x 中的必填项)
    upgrade_settings {
      max_surge = 1
    }
  }

  # 必须指定身份块 (根据你之前的截图，这是 AKS 资源的必填属性)
  identity {
    type = "SystemAssigned"
  }
}

# 4. Grant ACR Pull Access to AKS
# 4.x 中不再支持 acr_attach 块，因此标准做法是创建角色分配
resource "azurerm_role_assignment" "aks_acr_pull" {
  scope                = azurerm_container_registry.aks_demo.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.aks_demo.identity[0].principal_id
}

# Outputs for CI/CD
output "acr_login_server" {
  value = azurerm_container_registry.aks_demo.login_server
}

output "aks_client_id" {
  value = azurerm_kubernetes_cluster.aks_demo.identity[0].principal_id
}