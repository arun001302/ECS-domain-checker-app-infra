terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Once we set up S3 backend for state we'll uncomment this
  # For now state is stored locally
  # backend "s3" {
  #   bucket         = "domain-checker-terraform-state"
  #   key            = "prod/terraform.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "terraform-state-lock"
  #   encrypt        = true
  # }
}

provider "aws" {
  region  = var.aws_region
  profile = "SandboxAdmin-831959027212"

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Owner       = "platform-team"
    }
  }
}

# ── VPC Module ──────────────────────────────────────────────────────────────
module "vpc" {
  source = "./modules/vpc"

  project_name = var.project_name
  environment  = var.environment
  aws_region   = var.aws_region
}

# ── ECR Module ──────────────────────────────────────────────────────────────
module "ecr" {
  source = "./modules/ecr"

  project_name = var.project_name
  environment  = var.environment
  account_id   = var.account_id
}

# ── ECS Module ──────────────────────────────────────────────────────────────
module "ecs" {
  source = "./modules/ecs"

  project_name       = var.project_name
  environment        = var.environment
  aws_region         = var.aws_region
  account_id         = var.account_id
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  public_subnet_ids  = module.vpc.public_subnet_ids
  backend_image      = "${module.ecr.backend_repository_url}:latest"
  frontend_image     = "${module.ecr.frontend_repository_url}:latest"
}