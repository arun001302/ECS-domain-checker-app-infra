# ── Data Sources ─────────────────────────────────────────────────────────────
# Fetch available AZs in the region dynamically
# This means the code works in any region without hardcoding AZ names
data "aws_availability_zones" "available" {
  state = "available"
}

# ── VPC ──────────────────────────────────────────────────────────────────────
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true # Required for ECS service discovery via Cloud Map
  enable_dns_support   = true # Required for Route53 private hosted zones

  tags = {
    Name = "${var.project_name}-${var.environment}-vpc"
  }
}

# ── Internet Gateway ──────────────────────────────────────────────────────────
# Allows resources in public subnets to reach the internet
# ALB needs this to receive traffic from users
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-${var.environment}-igw"
  }
}

# ── Public Subnets ────────────────────────────────────────────────────────────
# ALB lives here — needs to be publicly accessible
# We create one per AZ for high availability
resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true # Instances get public IPs automatically

  tags = {
    Name = "${var.project_name}-${var.environment}-public-subnet-${count.index + 1}"
    Type = "public"
  }
}

# ── Private Subnets ───────────────────────────────────────────────────────────
# ECS Fargate tasks live here — never directly exposed to internet
# Traffic flows: Internet → ALB (public) → ECS tasks (private)
# This is equivalent to how GoDaddy runs EKS worker nodes in private subnets
resource "aws_subnet" "private" {
  count = length(var.private_subnet_cidrs)

  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "${var.project_name}-${var.environment}-private-subnet-${count.index + 1}"
    Type = "private"
  }
}

# ── Elastic IPs for NAT Gateways ──────────────────────────────────────────────
# NAT Gateway needs a static public IP
# ECS tasks in private subnets use NAT Gateway to reach internet
# (needed to pull from ECR, call external APIs like DNS checks)
resource "aws_eip" "nat" {
  count  = length(var.public_subnet_cidrs)
  domain = "vpc"

  tags = {
    Name = "${var.project_name}-${var.environment}-nat-eip-${count.index + 1}"
  }

  depends_on = [aws_internet_gateway.main]
}

# ── NAT Gateways ──────────────────────────────────────────────────────────────
# One per public subnet (one per AZ) for high availability
# ECS tasks in private subnets route outbound traffic through here
# EKS equivalent: same pattern — worker nodes in private subnets use NAT GW
resource "aws_nat_gateway" "main" {
  count = length(var.public_subnet_cidrs)

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = {
    Name = "${var.project_name}-${var.environment}-nat-gw-${count.index + 1}"
  }

  depends_on = [aws_internet_gateway.main]
}

# ── Public Route Table ────────────────────────────────────────────────────────
# Routes all outbound traffic from public subnets to the internet gateway
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-public-rt"
  }
}

# ── Private Route Tables ──────────────────────────────────────────────────────
# One per AZ — routes outbound traffic from private subnets through NAT Gateway
# Each private subnet gets its own route table pointing to its AZ's NAT GW
# This way if one AZ's NAT GW fails, only that AZ is affected
resource "aws_route_table" "private" {
  count  = length(var.private_subnet_cidrs)
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[count.index].id
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-private-rt-${count.index + 1}"
  }
}

# ── Route Table Associations ──────────────────────────────────────────────────
resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}