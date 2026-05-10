# Domain Health Checker — Infrastructure

Terraform infrastructure for the Domain Health Checker microservices application, deployed on AWS ECS Fargate. This repository manages all AWS resources following infrastructure-as-code best practices.

## Architecture Overview

```
Internet
    │
    ▼
Application Load Balancer (Public Subnets)
    │
    ├── /api/*  ──▶  Backend ECS Service (Private Subnets)
    │                Flask REST API — DNS/SSL/HTTP checks
    │
    └── /*  ──────▶  Frontend ECS Service (Private Subnets)
                     React + Nginx — Domain Health UI
```

## Infrastructure Components

| Component | Technology | Details |
|---|---|---|
| Container Orchestration | ECS Fargate | Serverless containers, no EC2 to manage |
| Container Registry | Amazon ECR | Private repos, scan-on-push, lifecycle policies |
| Load Balancing | ALB | Path-based routing, health checks |
| Networking | VPC | Public/private subnets across 2 AZs |
| Outbound Traffic | NAT Gateway | Private subnet egress per AZ |
| CI/CD | GitHub Actions | OIDC auth, automatic ECS deployment |
| Auto Scaling | ECS Service Auto Scaling | CPU 70%, Memory 80% target tracking |
| Monitoring | CloudWatch | Container Insights, dashboard, alarms |
| IaC | Terraform | Modular structure, remote-ready state |

## Repository Structure

```
microservices-infra/
├── main.tf                 # Root module — wires all modules together
├── variables.tf            # Input variables
├── outputs.tf              # Output values (ALB URL, ECR URLs, etc.)
├── terraform.tfvars        # Variable values (gitignored)
└── modules/
    ├── vpc/                # VPC, subnets, IGW, NAT Gateways, route tables
    ├── ecr/                # ECR repositories, lifecycle policies, IAM policies
    └── ecs/                # ECS cluster, task definitions, services,
                            # ALB, target groups, auto scaling, CloudWatch
```

## Network Design

```
VPC: 10.0.0.0/16
├── Public Subnet AZ-a  10.0.1.0/24  → ALB, NAT Gateway
├── Public Subnet AZ-b  10.0.2.0/24  → ALB, NAT Gateway
├── Private Subnet AZ-a 10.0.3.0/24  → ECS Tasks
└── Private Subnet AZ-b 10.0.4.0/24  → ECS Tasks
```

ECS tasks run in private subnets with no public IPs. All inbound traffic flows through the ALB. Outbound traffic (ECR pulls, external API calls) routes through NAT Gateways.

## ECS Task Definitions

| Service | CPU | Memory | Port | Health Check |
|---|---|---|---|---|
| Backend | 0.5 vCPU | 1 GB | 5000 | GET /health |
| Frontend | 0.5 vCPU | 1 GB | 80 | GET /health |

Both services run with `desired_count = 2` across 2 availability zones for high availability.

## Auto Scaling

| Policy | Metric | Target | Scale Out | Scale In |
|---|---|---|---|---|
| Backend CPU | ECSServiceAverageCPUUtilization | 70% | 60s cooldown | 300s cooldown |
| Backend Memory | ECSServiceAverageMemoryUtilization | 80% | 60s cooldown | 300s cooldown |
| Frontend CPU | ECSServiceAverageCPUUtilization | 70% | 60s cooldown | 300s cooldown |
| Frontend Memory | ECSServiceAverageMemoryUtilization | 80% | 60s cooldown | 300s cooldown |

Min tasks: 2 per service | Max tasks: 4 per service

## CloudWatch Monitoring

Dashboard: `domain-checker-prod-dashboard`

Metrics tracked:
- Backend CPU and Memory utilization
- Frontend CPU utilization
- ALB request count
- ALB p95 response time
- ALB 5xx error count

Alarms configured:
- Backend/Frontend CPU > 85% for 2 consecutive minutes
- Backend Memory > 85% for 2 consecutive minutes
- ALB 5xx errors > 10 per minute
- ALB p95 latency > 2 seconds

## CI/CD Pipeline

GitHub Actions workflow triggers on every push to `master`:

```
Push to master
      │
      ▼
Configure AWS (OIDC — no stored credentials)
      │
      ▼
Build linux/amd64 Docker images
      │
      ▼
Push to ECR (tagged with git SHA + latest)
      │
      ▼
Force new ECS deployment (backend + frontend)
      │
      ▼
Wait for services to stabilize
      │
      ▼
✅ Deployment complete
```

OIDC authentication means no AWS credentials are stored in GitHub Secrets. GitHub proves its identity to AWS on each run and receives a short-lived scoped token.

## Prerequisites

- Terraform >= 1.5.0
- AWS CLI configured with appropriate permissions
- AWS SSO profile configured for your account

## Usage

**Refresh AWS credentials:**
```bash
aws sso login --profile SandboxAdmin-831959027212
```

**Deploy all infrastructure:**
```bash
terraform init
terraform plan
terraform apply
```

**Tear down (stop incurring costs):**
```bash
terraform destroy
```

**Key outputs after apply:**
```
alb_dns_name              → Application URL
ecr_backend_url           → Backend ECR repository
ecr_frontend_url          → Frontend ECR repository
cluster_name              → ECS cluster name
github_actions_role_arn   → IAM role for GitHub Actions OIDC
```

## Cost Estimate (us-east-1)

| Resource | Cost |
|---|---|
| NAT Gateway x2 | ~$2.16/day |
| ALB | ~$0.19/day |
| ECS Fargate (4 tasks) | ~$0.10/day |
| ECR Storage | ~$0.01/day |
| **Total** | **~$2.46/day** |

> Destroy infrastructure when not in use to avoid NAT Gateway charges.

## Key Design Decisions

**Why ECS Fargate over EC2?**
No node or instance management. AWS handles the underlying infrastructure — you define what to run, not where to run it.

**Why private subnets for ECS tasks?**
Tasks are never directly exposed to the internet. All traffic flows through the ALB which acts as the single entry point. This follows the same network pattern used in enterprise EKS deployments.

**Why OIDC for GitHub Actions?**
Eliminates long-lived AWS credentials stored in GitHub Secrets. Each pipeline run gets a short-lived token scoped to exactly the permissions needed — ECR push and ECS service update.

**Why multi-stage Docker builds?**
Builder stage contains compilers and build tools. Runner stage contains only the compiled artifact. Result: backend image ~150MB vs ~900MB, frontend image ~30MB vs ~400MB. Smaller images mean faster ECR pulls, faster ECS task starts, and a smaller CVE attack surface.

**Why two NAT Gateways?**
One per AZ. If a single NAT Gateway fails, only one AZ loses outbound connectivity instead of the entire application. This is the HA pattern used in production environments.

## Application Repository

[ECS-domain-checker-app-data](https://github.com/arun001302/ECS-domain-checker-app-data)
