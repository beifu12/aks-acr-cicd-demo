# --- Terraform 配置与 Provider 声明 ---
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0" 
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
  # 建议：在这里添加 backend 块将 tfstate 存入 Azure Storage Account，防止 GitHub Action 运行冲突
}

provider "azurerm" {
  features {}
  environment = "china" # 关键配置：确保所有 API 调用指向世纪互联环境
}

# 生成随机后缀，防止资源名称冲突（Azure 很多资源名称是全局唯一的）
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
  numeric = true
}

# 1. 创建资源组
resource "azurerm_resource_group" "aks_demo" {
  name     = "aks-demo-rg"
  location = "China North 3" # 华北3（张家口）是目前 Azure China 较新的区域，资源较充足
}

# 使用 data 块来引用 Azure 中已经存在的 ACR
data "azurerm_container_registry" "existing_acr" {
  name                = var.acr_name           # 引用你定义的 "fzhacr"
  resource_group_name = "test" # 必须提供现有 ACR 所在的 RG
}

# 3. 创建 AKS 集群
resource "azurerm_kubernetes_cluster" "aks_demo" {
  name                = "aks-demo-cluster"
  resource_group_name = azurerm_resource_group.aks_demo.name
  location            = azurerm_resource_group.aks_demo.location
  dns_prefix          = "aksdemocluster${random_string.suffix.result}"
  
  # 注意：Azure China 的 K8s 版本通常比 Global 慢一到两个小版本
  # 如果 1.33.2 报错，请尝试使用 az aks get-versions --location chinanorth3 查询
  kubernetes_version  = "1.33.2"

  # --- 4.x 特有属性 ---
  automatic_upgrade_channel = "stable" 

  default_node_pool {
    name       = "default"
    node_count = 1
    vm_size    = "Standard_D2s_v3"

    # 4.x 必填：定义升级时的临时节点数量，1 表示升级时会多开一个节点平滑迁移任务
    upgrade_settings {
      max_surge = 1
    }
  }

  # 系统分配标识 (Managed Identity)
  # 这是目前最安全的方式，无需管理 Service Principal 的密钥过期问题
  identity {
    type = "SystemAssigned"
  }

  # 建议添加：网络配置
  network_profile {
    network_plugin = "azure" # 使用 Azure CNI（每个 Pod 拿一个私有 IP），比 kubenet 性能更好
    load_balancer_sku = "standard"
  }
}

# 4. 核心授权：将 ACR 绑定到 AKS
# 逻辑：授权 AKS 的“身份 (Identity)” 拥有对 ACR 的“拉取权限 (AcrPull)”
resource "azurerm_role_assignment" "aks_acr_pull" {
  # 注意这里：引用的是 data.azurerm_container_registry... 的 ID
  scope                = data.azurerm_container_registry.existing_acr.id
  role_definition_name = "AcrPull"
  # 这里使用 principal_id，它是 Identity 的全局唯一 ID
  principal_id         = azurerm_kubernetes_cluster.aks_demo.identity[0].principal_id
  # 建议：跳过分配检查，加速部署流程
  skip_service_principal_aad_check = true
}

# --- 输出参数 (用于 GitHub Actions 步骤间的传递) ---

output "acr_login_server" {
  description = "ACR 的登录地址，例如：xxx.azurecr.cn"
  value       = azurerm_container_registry.aks_demo.login_server
}

output "resource_group_name" {
  value = azurerm_resource_group.aks_demo.name
}

output "aks_cluster_name" {
  value = azurerm_kubernetes_cluster.aks_demo.name
}