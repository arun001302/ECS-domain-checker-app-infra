variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "account_id" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "backend_image" {
  type = string
}

variable "frontend_image" {
  type = string
}

variable "backend_cpu" {
  type    = number
  default = 512 # 0.5 vCPU
}

variable "backend_memory" {
  type    = number
  default = 1024 # 1 GB
}

variable "frontend_cpu" {
  type    = number
  default = 512
}

variable "frontend_memory" {
  type    = number
  default = 1024
}

variable "backend_desired_count" {
  type    = number
  default = 2 # 2 tasks for HA across AZs
}

variable "frontend_desired_count" {
  type    = number
  default = 2
}