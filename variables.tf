variable "aws_region" {
  description = "AWS 리전"
  type        = string
  default     = "ap-northeast-2"
}

variable "cluster_name" {
  description = "EKS 클러스터 이름"
  type        = string
  default     = "seoul-cluster"
}

variable "project_name" {
  description = "프로젝트 이름"
  type        = string
  default     = "siseon"
}

variable "grafana_admin_password" {
  description = "Grafana 관리자 비밀번호"
  type        = string
  sensitive   = true
}

variable "gmail_app_password" {
  description = "Gmail 앱 비밀번호"
  type        = string
  sensitive   = true
}