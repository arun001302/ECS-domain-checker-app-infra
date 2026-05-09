# ── CloudWatch Log Groups ─────────────────────────────────────────────────────
# All container stdout/stderr goes here automatically via awslogs driver
# This is how you do `kubectl logs` equivalent in ECS —
# you go to CloudWatch Log Groups instead
resource "aws_cloudwatch_log_group" "backend" {
  name              = "/ecs/${var.project_name}-${var.environment}/backend"
  retention_in_days = 30

  tags = {
    Name = "${var.project_name}-${var.environment}-backend-logs"
  }
}

resource "aws_cloudwatch_log_group" "frontend" {
  name              = "/ecs/${var.project_name}-${var.environment}/frontend"
  retention_in_days = 30

  tags = {
    Name = "${var.project_name}-${var.environment}-frontend-logs"
  }
}

# ── IAM Role for ECS Task Execution ──────────────────────────────────────────
# This role is used by the ECS AGENT to:
# - Pull images from ECR
# - Write logs to CloudWatch
# This is NOT the role your application code uses — that would be the Task Role
# EKS equivalent: the node instance profile or IRSA for kubelet operations
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "${var.project_name}-${var.environment}-ecs-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-ecs-execution-role"
  }
}

# Attach the AWS managed policy for ECS task execution
# Grants: ECR pull, CloudWatch logs write, SSM parameter read
resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ── IAM Role for ECS Tasks (Application Role) ─────────────────────────────────
# This role is assumed BY your application code running inside the container
# Add permissions here for anything your app needs to call (S3, DynamoDB, etc.)
# EKS equivalent: IRSA (IAM Roles for Service Accounts)
resource "aws_iam_role" "ecs_task_role" {
  name = "${var.project_name}-${var.environment}-ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-ecs-task-role"
  }
}

# ── Security Group for ECS Tasks ──────────────────────────────────────────────
# Controls inbound/outbound traffic to the ECS tasks
# Tasks are in private subnets — only the ALB can reach them
resource "aws_security_group" "ecs_tasks" {
  name        = "${var.project_name}-${var.environment}-ecs-tasks-sg"
  description = "Security group for ECS tasks"
  vpc_id      = var.vpc_id

  # Allow inbound on port 5000 from ALB (backend)
  ingress {
    from_port       = 5000
    to_port         = 5000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
    description     = "Allow ALB to reach backend"
  }

  # Allow inbound on port 80 from ALB (frontend)
  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
    description     = "Allow ALB to reach frontend"
  }

  # Allow all outbound — tasks need to reach ECR, CloudWatch, external APIs
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-ecs-tasks-sg"
  }
}

# ── Security Group for ALB ────────────────────────────────────────────────────
# ALB is in public subnets — accepts traffic from the internet
resource "aws_security_group" "alb" {
  name        = "${var.project_name}-${var.environment}-alb-sg"
  description = "Security group for Application Load Balancer"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTP from internet"
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTPS from internet"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-alb-sg"
  }
}

# ── ECS Cluster ───────────────────────────────────────────────────────────────
# The logical grouping for all our services
# Fargate means AWS manages the underlying EC2 instances — you never see them
# EKS equivalent: the EKS cluster itself, but without node groups to manage
resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-${var.environment}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
    # Container Insights enables detailed CloudWatch metrics per task/service
    # CPU, memory, network, storage metrics at the container level
    # At GoDaddy this feeds into your Grafana dashboards
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-cluster"
  }
}

# ── ECS Cluster Capacity Providers ───────────────────────────────────────────
# Tells the cluster to use Fargate and Fargate Spot
# Fargate Spot is up to 70% cheaper but can be interrupted (good for dev)
resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name = aws_ecs_cluster.main.name

  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
    base              = 1
  }
}

# ── Backend Task Definition ───────────────────────────────────────────────────
# This is the ECS equivalent of a Kubernetes Pod spec
# Defines exactly what runs inside the task: image, CPU, memory, ports, logs
resource "aws_ecs_task_definition" "backend" {
  family       = "${var.project_name}-${var.environment}-backend"
  network_mode = "awsvpc"
  # awsvpc gives each task its own ENI and private IP
  # Required for Fargate — equivalent to how every K8s pod gets its own IP
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.backend_cpu
  memory                   = var.backend_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "backend"
      image     = var.backend_image
      essential = true # If this container dies, the whole task is stopped

      portMappings = [
        {
          containerPort = 5000
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          name  = "PORT"
          value = "5000"
        },
        {
          name  = "FLASK_ENV"
          value = "production"
        }
      ]

      # Health check — ECS calls this to determine if the task is healthy
      # Unhealthy tasks are stopped and replaced by the service
      # Equivalent to Kubernetes livenessProbe
      healthCheck = {
        command     = ["CMD-SHELL", "python -c \"import urllib.request; urllib.request.urlopen('http://localhost:5000/health')\" || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60 # Give the container 60s to start before health checks begin
      }

      # Log configuration — sends all stdout/stderr to CloudWatch
      # This is how you see container logs — equivalent to kubectl logs
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.backend.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "backend"
        }
      }
    }
  ])

  tags = {
    Name = "${var.project_name}-${var.environment}-backend-td"
  }
}

# ── Frontend Task Definition ──────────────────────────────────────────────────
resource "aws_ecs_task_definition" "frontend" {
  family                   = "${var.project_name}-${var.environment}-frontend"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.frontend_cpu
  memory                   = var.frontend_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "frontend"
      image     = var.frontend_image
      essential = true

      portMappings = [
        {
          containerPort = 80
          protocol      = "tcp"
        }
      ]

      healthCheck = {
        command     = ["CMD-SHELL", "wget -qO- http://localhost:80/health || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 30
      }

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.frontend.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "frontend"
        }
      }
    }
  ])

  tags = {
    Name = "${var.project_name}-${var.environment}-frontend-td"
  }
}

# ── Application Load Balancer ─────────────────────────────────────────────────
# Lives in public subnets, routes traffic to ECS tasks in private subnets
# Path-based routing: /api/* → backend, /* → frontend
resource "aws_lb" "main" {
  name               = "${var.project_name}-${var.environment}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.public_subnet_ids

  enable_deletion_protection = false
  # Set to true in production at a real company to prevent accidental deletion

  tags = {
    Name = "${var.project_name}-${var.environment}-alb"
  }
}

# ── Target Groups ─────────────────────────────────────────────────────────────
# Target groups are the bridge between the ALB and ECS tasks
# ALB forwards requests to a target group, which routes to healthy tasks
# EKS equivalent: a Kubernetes Service that the Ingress points to
resource "aws_lb_target_group" "backend" {
  name        = "${var.project_name}-${var.environment}-backend-tg"
  port        = 5000
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"
  # target_type = "ip" is required for Fargate
  # Each task gets its own IP via awsvpc networking

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = "/health"
    matcher             = "200"
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-backend-tg"
  }
}

resource "aws_lb_target_group" "frontend" {
  name        = "${var.project_name}-${var.environment}-frontend-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = "/health"
    matcher             = "200"
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-frontend-tg"
  }
}

# ── ALB Listener ──────────────────────────────────────────────────────────────
# Listens on port 80 and routes based on path
resource "aws_lb_listener" "main" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  # Default action — send to frontend
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend.arn
  }
}

# ── ALB Listener Rules ────────────────────────────────────────────────────────
# Path-based routing: /api/* goes to backend target group
resource "aws_lb_listener_rule" "backend" {
  listener_arn = aws_lb_listener.main.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend.arn
  }

  condition {
    path_pattern {
      values = ["/api/*"]
    }
  }
}

# ── ECS Backend Service ───────────────────────────────────────────────────────
# Maintains desired count of tasks and registers them with the ALB target group
# EKS equivalent: a Kubernetes Deployment + Service combined
resource "aws_ecs_service" "backend" {
  name            = "${var.project_name}-${var.environment}-backend"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.backend.arn
  desired_count   = var.backend_desired_count
  launch_type     = "FARGATE"

  # Force new deployment when task definition changes
  force_new_deployment = true

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
    # false because tasks are in private subnets behind NAT Gateway
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.backend.arn
    container_name   = "backend"
    container_port   = 5000
  }

  depends_on = [
    aws_lb_listener.main,
    aws_iam_role_policy_attachment.ecs_task_execution_role_policy
  ]

  tags = {
    Name = "${var.project_name}-${var.environment}-backend-service"
  }
}

# ── ECS Frontend Service ──────────────────────────────────────────────────────
resource "aws_ecs_service" "frontend" {
  name            = "${var.project_name}-${var.environment}-frontend"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.frontend.arn
  desired_count   = var.frontend_desired_count
  launch_type     = "FARGATE"

  force_new_deployment = true

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.frontend.arn
    container_name   = "frontend"
    container_port   = 80
  }

  depends_on = [
    aws_lb_listener.main,
    aws_iam_role_policy_attachment.ecs_task_execution_role_policy
  ]

  tags = {
    Name = "${var.project_name}-${var.environment}-frontend-service"
  }
}