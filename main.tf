# 配置Azure提供者（适配中国版，核心修改点1）
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {}
  # 关键：指定Azure中国环境
  environment = "china" 
  # 可选：如果需要指定特定的ARM端点，也可以加（一般不用）
  # arm_endpoint = "https://management.chinacloudapi.cn/"
}

# 1. 创建资源组（适配中国版区域，核心修改点2）
resource "azurerm_resource_group" "aks_demo" {
  name     = "aks-demo-rg"
  location = "China East 2" # Azure中国常用区域：China East 2/China North 2
}

# 2. 创建ACR（Azure容器注册表，中国版后缀自动为azurecr.cn）
resource "azurerm_container_registry" "aks_demo" {
  name                = "aksdemoreg${random_string.suffix.result}" # 名称必须全局唯一
  resource_group_name = azurerm_resource_group.aks_demo.name
  location            = azurerm_resource_group.aks_demo.location
  sku                 = "Basic" # 免费版，够用
  admin_enabled       = true    # 启用管理员账户（方便推送镜像）
}

# 3. 创建AKS集群（适配中国版，核心修改点3）
resource "azurerm_kubernetes_cluster" "aks_demo" {
  name                = "aks-demo-cluster"
  resource_group_name = azurerm_resource_group.aks_demo.name
  location            = azurerm_resource_group.aks_demo.location
  dns_prefix          = "aksdemocluster"
  kubernetes_version  = "1.30.0" # 建议确认当前支持的最新版本

  # 自动更新配置已经移到 node_pool 内部了
  default_node_pool {
    name       = "default"
    node_count = 1
    vm_size    = "Standard_D2s_v3"

    # 核心修复：启用自动升级，满足订阅策略（放在 default_node_pool 内部）
    auto_upgrade_channel = "stable" 
    
    # 如果你还想启用节点资源自动升级（可选）
    upgrade_settings {
      auto_upgrade = true
    }
  }

  identity {
    type = "SystemAssigned"
  }

  # 自动关联ACR权限
  acr_attach {
    id = azurerm_container_registry.aks_demo.id
  }

  # 让AKS有权限访问ACR
  depends_on = [azurerm_container_registry.aks_demo]
}

# 生成随机后缀（避免ACR名称重复）
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# 输出关键信息（后续CI/CD要用）
output "acr_login_server" {
  value = azurerm_container_registry.aks_demo.login_server
}

output "acr_admin_username" {
  value = azurerm_container_registry.aks_demo.admin_username
}

output "acr_admin_password" {
  value     = azurerm_container_registry.aks_demo.admin_password
  sensitive = true # 敏感信息加密输出
}

output "aks_kubeconfig" {
  value     = azurerm_kubernetes_cluster.aks_demo.kube_config_raw
  sensitive = true
}