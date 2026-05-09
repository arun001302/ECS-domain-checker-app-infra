variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
}

variable "account_id" {
  description = "AWS account ID"
  type        = string
}

variable "project_name" {
  description = "Name of the project, used for resource naming"
  type        = string
}

variable "environment" {
  description = "Deployment environment (prod, staging, dev)"
  type        = string
}