provider "aws" {
  region = var.aws_region
}

# --- AMI Data Source ---
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

# --- VPC & Networking ---
resource "aws_vpc" "mesh_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = { Name = "inference-mesh-vpc" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.mesh_vpc.id
}

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.mesh_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.mesh_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "${var.aws_region}b"
  map_public_ip_on_launch = true
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.mesh_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public_rt.id
}

# --- Security Groups ---
resource "aws_security_group" "alb_sg" {
  name        = "alb-sg"
  description = "Allow HTTP inbound to ALB"
  vpc_id      = aws_vpc.mesh_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "worker_sg" {
  name        = "worker-sg"
  description = "Allow ALB and internal mesh traffic"
  vpc_id      = aws_vpc.mesh_vpc.id

  ingress {
    description     = "API Traffic from ALB"
    from_port       = 3111
    to_port         = 3111
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }
  ingress {
    description = "Internal Mesh Routing"
    from_port   = 49134
    to_port     = 49134
    protocol    = "tcp"
    self        = true
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# --- IAM Role for SSM ---
resource "aws_iam_role" "ssm_role" {
  name = "mesh-ec2-ssm-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_attach" {
  role       = aws_iam_role.ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ssm_profile" {
  name = "mesh-ec2-ssm-profile"
  role = aws_iam_role.ssm_role.name
}

# --- Application Load Balancer ---
resource "aws_lb" "mesh_alb" {
  name               = "inference-mesh-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [aws_subnet.public_a.id, aws_subnet.public_b.id]
  idle_timeout       = 300
}

resource "aws_lb_target_group" "api_tg" {
  name     = "mesh-api-tg-3111"
  port     = 3111
  protocol = "HTTP"
  vpc_id   = aws_vpc.mesh_vpc.id

  health_check {
    path                = "/v1/chat/completions"
    matcher             = "200-499"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.mesh_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api_tg.arn
  }
}

# --- TypeScript Hub (The Caller Worker) ---
resource "aws_instance" "ts_worker" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.ts_instance_type
  subnet_id              = aws_subnet.public_a.id
  vpc_security_group_ids = [aws_security_group.worker_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.ssm_profile.name

  user_data = file("${path.module}/../deploy-scripts/ts-setup.sh")

  tags = { Name = "typescript-caller-hub" }
}

resource "aws_lb_target_group_attachment" "ts_attach" {
  target_group_arn = aws_lb_target_group.api_tg.arn
  target_id        = aws_instance.ts_worker.id
  port             = 3111
}

# --- Python AI Engine (The Inference Worker) ---
resource "aws_instance" "python_worker" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.python_instance_type
  subnet_id              = aws_subnet.public_a.id
  vpc_security_group_ids = [aws_security_group.worker_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.ssm_profile.name

  root_block_device {
    volume_size = var.python_volume_size_gb
    volume_type = "gp3"
  }

  # Dynamically pass the TypeScript worker's private IP into the Python setup script
  user_data = templatefile("${path.module}/../deploy-scripts/python-setup.sh", {
    TS_PRIVATE_IP = aws_instance.ts_worker.private_ip
  })

  tags = { Name = "python-inference-engine" }
}
