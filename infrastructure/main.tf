# ==========================
# VPC
# ==========================
resource "aws_vpc" "capstone" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name    = "${var.project_name}-vpc"
    Project = var.project_name
  }
}

# ==========================
# Subnet
# ==========================
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.capstone.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = {
    Name    = "${var.project_name}-public-subnet"
    Project = var.project_name
  }
}

# ==========================
# Internet Gateway
# ==========================
resource "aws_internet_gateway" "capstone" {
  vpc_id = aws_vpc.capstone.id

  tags = {
    Name    = "${var.project_name}-igw"
    Project = var.project_name
  }
}

# ==========================
# Route Table
# ==========================
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.capstone.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.capstone.id
  }

  tags = {
    Name    = "${var.project_name}-rt"
    Project = var.project_name
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# ==========================
# Security Group (Splunk)
# ==========================
resource "aws_security_group" "splunk" {
  name_prefix = "${var.project_name}-splunk-"
  vpc_id      = aws_vpc.capstone.id
  description = "Splunk server security group"

  # SSH access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SSH access"
  }

  # Splunk Web UI
  ingress {
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Splunk Web UI"
  }

  # Splunk Forwarder (internal only)
  ingress {
    from_port   = 9997
    to_port     = 9997
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
    description = "Splunk forwarder input"
  }

  # Splunk management
  ingress {
    from_port   = 8089
    to_port     = 8089
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
    description = "Splunk management port"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound traffic"
  }

  tags = {
    Name    = "${var.project_name}-splunk-sg"
    Project = var.project_name
  }
}

# ==========================
# Key Pair (SSH Access)
# ==========================
resource "aws_key_pair" "capstone" {
  key_name   = "${var.project_name}-key"
  public_key = file("${path.module}/capstone-key.pub")

  tags = {
    Name    = "${var.project_name}-key"
    Project = var.project_name
  }
}

# ==========================
# EC2 (Splunk Server)
# ==========================
resource "aws_instance" "splunk" {
  ami                    = "ami-02fd066b86800f60c"
  instance_type          = "t3.medium"
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.splunk.id]
  key_name               = aws_key_pair.capstone.key_name

  root_block_device {
    volume_size           = 30
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name    = "${var.project_name}-splunk-server"
    Project = var.project_name
    Role    = "SIEM"
  }
}

# ==========================
# S3 Bucket (Shared Artifacts)
# ==========================
resource "aws_s3_bucket" "artifacts" {
  bucket = "${var.project_name}-artifacts-${random_id.bucket_suffix.hex}"

  tags = {
    Name    = "${var.project_name}-artifacts"
    Project = var.project_name
  }
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  versioning_configuration {
    status = "Enabled"
  }
}

# S3 Folder Structure
resource "aws_s3_object" "folders" {
  for_each = toset([
    "nmap-scans/",
    "logs/",
    "cve-catalog/",
    "dashboards/",
    "incident-reports/"
  ])

  bucket  = aws_s3_bucket.artifacts.id
  key     = each.value
  content = ""
}

# ==========================
# CloudTrail (Audit Logging)
# ==========================
resource "aws_s3_bucket" "cloudtrail" {
  bucket = "${var.project_name}-cloudtrail-${random_id.bucket_suffix.hex}"

  tags = {
    Name    = "${var.project_name}-cloudtrail"
    Project = var.project_name
  }
}

resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.cloudtrail.arn
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.cloudtrail.arn}/AWSLogs/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      }
    ]
  })
}

resource "aws_cloudtrail" "capstone" {
  name                          = "${var.project_name}-trail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail.id
  include_global_service_events = true
  is_multi_region_trail         = false
  enable_log_file_validation    = true

  depends_on = [aws_s3_bucket_policy.cloudtrail]

  tags = {
    Name    = "${var.project_name}-trail"
    Project = var.project_name
  }
}

# ==========================
# IAM Users (Team Members)
# ==========================
resource "aws_iam_user" "team" {
  for_each = var.team_members
  name     = each.value

  tags = {
    Role    = each.key
    Project = var.project_name
  }
}

resource "aws_iam_access_key" "team" {
  for_each = aws_iam_user.team
  user     = each.value.name
}