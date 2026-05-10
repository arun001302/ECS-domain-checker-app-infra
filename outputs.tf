output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "Public subnet IDs for ALB"
  value       = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Private subnet IDs for ECS tasks"
  value       = module.vpc.private_subnet_ids
}

output "ecr_backend_url" {
  description = "ECR URL for backend image"
  value       = module.ecr.backend_repository_url
}

output "ecr_frontend_url" {
  description = "ECR URL for frontend image"
  value       = module.ecr.frontend_repository_url
}

output "cluster_name" {
  description = "ECS cluster name"
  value       = module.ecs.cluster_name
}

output "alb_dns_name" {
  description = "Application URL"
  value       = module.ecs.alb_dns_name
}

output "backend_service_name" {
  value = module.ecs.backend_service_name
}

output "frontend_service_name" {
  value = module.ecs.frontend_service_name
}

output "github_actions_role_arn" {
  description = "IAM role ARN for GitHub Actions OIDC"
  value       = module.ecs.github_actions_role_arn
}
