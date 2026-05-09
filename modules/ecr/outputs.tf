output "backend_repository_url" {
  description = "ECR URL for backend image"
  value       = aws_ecr_repository.backend.repository_url
}

output "frontend_repository_url" {
  description = "ECR URL for frontend image"
  value       = aws_ecr_repository.frontend.repository_url
}

output "backend_repository_name" {
  description = "ECR repository name for backend"
  value       = aws_ecr_repository.backend.name
}

output "frontend_repository_name" {
  description = "ECR repository name for frontend"
  value       = aws_ecr_repository.frontend.name
}
