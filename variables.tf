variable "azure_region" {
  description = "Azure中国区域"
  type        = string
  default     = "China North 3" # 优先选这个，网络更稳定
}

variable "acr_name" {
  type    = string
  default = "fzhacr"
}

