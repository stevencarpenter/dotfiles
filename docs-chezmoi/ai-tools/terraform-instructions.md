# Custom Terraform Instructions for AI Tools

## Overview

This document provides custom instructions and best practices for AI coding assistants (GitHub Copilot, OpenAI Codex, Claude) when working with Terraform code. Use these guidelines to ensure AI-generated Terraform code follows best practices and standards.

## General Instructions for AI Assistants

When generating or modifying Terraform code, always follow these principles:

### 1. Version Constraints

**Always specify provider versions:**
```hcl
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
```

**Use semantic versioning:**
- `~> 5.0` - Allow minor and patch updates
- `>= 5.0, < 6.0` - Explicit range
- Avoid `latest` or unpinned versions

### 2. Resource Naming Conventions

**Use lowercase with underscores:**
```hcl
resource "aws_s3_bucket" "application_data" {
  # Good
}

resource "aws_s3_bucket" "ApplicationData" {
  # Bad - no camelCase
}
```

**Naming pattern:**
- `{resource_type}_{purpose}_{environment}` for multiple environments
- `{resource_type}_{purpose}` for single environment

**Examples:**
```hcl
resource "aws_s3_bucket" "logs_production" { }
resource "aws_instance" "web_server" { }
resource "aws_db_instance" "main_database" { }
```

### 3. Variables and Outputs

**All variables must have descriptions:**
```hcl
variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}
```

**Use appropriate types:**
```hcl
variable "instance_count" {
  description = "Number of instances to create"
  type        = number
  default     = 1
}

variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "subnet_ids" {
  description = "List of subnet IDs"
  type        = list(string)
}
```

**All outputs should have descriptions:**
```hcl
output "bucket_name" {
  description = "Name of the created S3 bucket"
  value       = aws_s3_bucket.data.id
}

output "bucket_arn" {
  description = "ARN of the created S3 bucket"
  value       = aws_s3_bucket.data.arn
}
```

### 4. Resource Tagging

**Always include tags:**
```hcl
resource "aws_instance" "web" {
  ami           = var.ami_id
  instance_type = var.instance_type

  tags = merge(
    var.common_tags,
    {
      Name        = "web-server-${var.environment}"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Project     = var.project_name
    }
  )
}
```

**Standard tags to include:**
- `Name` - Human-readable resource name
- `Environment` - dev, staging, prod
- `ManagedBy` - "Terraform"
- `Project` - Project or application name
- `Owner` - Team or person responsible
- `CostCenter` - For billing/accounting

### 5. Use Data Sources

**Prefer data sources over hardcoded values:**
```hcl
# Good - use data source
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

resource "aws_instance" "web" {
  ami = data.aws_ami.ubuntu.id
}

# Bad - hardcoded AMI
resource "aws_instance" "web" {
  ami = "ami-0123456789abcdef0"
}
```

### 6. Use Locals for Computed Values

```hcl
locals {
  common_tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
    Project     = var.project_name
  }

  bucket_name = "${var.project_name}-${var.environment}-data"

  availability_zones = slice(
    data.aws_availability_zones.available.names,
    0,
    var.az_count
  )
}
```

### 7. Security Best Practices

**Enable encryption by default:**
```hcl
resource "aws_s3_bucket" "data" {
  bucket = local.bucket_name
}

resource "aws_s3_bucket_server_side_encryption_configuration" "data" {
  bucket = aws_s3_bucket.data.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.bucket.arn
    }
  }
}
```

**Block public access:**
```hcl
resource "aws_s3_bucket_public_access_block" "data" {
  bucket = aws_s3_bucket.data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
```

**Use security groups with least privilege:**
```hcl
resource "aws_security_group" "web" {
  name_prefix = "${var.project_name}-web-"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTPS from load balancer"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-web-sg"
  })
}
```

### 8. Use Modules for Reusability

**Structure:**
```
modules/
  vpc/
    main.tf
    variables.tf
    outputs.tf
    README.md
  s3-bucket/
    main.tf
    variables.tf
    outputs.tf
    README.md
```

**Module usage:**
```hcl
module "vpc" {
  source = "./modules/vpc"

  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones
  environment        = var.environment

  tags = local.common_tags
}

module "s3_bucket" {
  source = "./modules/s3-bucket"

  bucket_name = local.bucket_name
  environment = var.environment

  enable_encryption = true
  kms_key_arn      = aws_kms_key.bucket.arn

  tags = local.common_tags
}
```

### 9. State Management

**Backend configuration:**
```hcl
terraform {
  backend "s3" {
    bucket         = "my-terraform-state"
    key            = "infrastructure/terraform.tfstate"
    region         = "us-west-2"
    encrypt        = true
    dynamodb_table = "terraform-locks"
    kms_key_id     = "arn:aws:kms:us-west-2:123456789012:key/12345678-1234-1234-1234-123456789012"
  }
}
```

**State locking with DynamoDB:**
```hcl
resource "aws_dynamodb_table" "terraform_locks" {
  name         = "terraform-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Name      = "Terraform State Lock Table"
    ManagedBy = "Terraform"
  }
}
```

### 10. Error Handling and Validation

**Use lifecycle rules:**
```hcl
resource "aws_instance" "web" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type

  lifecycle {
    create_before_destroy = true
    prevent_destroy       = true
    ignore_changes = [
      ami,  # Ignore AMI changes after creation
    ]
  }
}
```

**Validate variables:**
```hcl
variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"

  validation {
    condition = contains([
      "t3.micro", "t3.small", "t3.medium",
      "t3.large", "t3.xlarge"
    ], var.instance_type)
    error_message = "Instance type must be a valid t3 instance type."
  }
}
```

### 11. Dependencies and Ordering

**Explicit dependencies when needed:**
```hcl
resource "aws_s3_bucket" "data" {
  bucket = local.bucket_name
}

resource "aws_s3_bucket_policy" "data" {
  bucket = aws_s3_bucket.data.id
  policy = data.aws_iam_policy_document.bucket_policy.json

  depends_on = [
    aws_s3_bucket_public_access_block.data
  ]
}
```

### 12. Comments and Documentation

**Add comments for complex logic:**
```hcl
# Calculate the number of subnets needed based on availability zones
# Each AZ gets one public and one private subnet
locals {
  # Total number of AZs to use (max 3)
  az_count = min(length(data.aws_availability_zones.available.names), 3)

  # CIDR blocks for public subnets (first half of range)
  public_subnet_cidrs = [
    for i in range(local.az_count) :
    cidrsubnet(var.vpc_cidr, 4, i)
  ]

  # CIDR blocks for private subnets (second half of range)
  private_subnet_cidrs = [
    for i in range(local.az_count) :
    cidrsubnet(var.vpc_cidr, 4, i + local.az_count)
  ]
}
```

### 13. Testing and Validation

**Use terraform validate:**
```bash
terraform validate
```

**Format code:**
```bash
terraform fmt -recursive
```

**Plan before apply:**
```bash
terraform plan -out=tfplan
terraform apply tfplan
```

## Project Structure

**Recommended structure:**
```
terraform/
├── environments/
│   ├── dev/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── terraform.tfvars
│   │   └── outputs.tf
│   ├── staging/
│   └── prod/
├── modules/
│   ├── vpc/
│   ├── compute/
│   └── storage/
├── global/
│   ├── iam/
│   └── route53/
└── README.md
```

## AI Assistant Prompts

### For GitHub Copilot

Add to `.github/copilot-instructions.md`:

```markdown
## Terraform Code Generation Guidelines

When generating Terraform code:

1. Always use Terraform 1.5+ syntax
2. Include provider version constraints
3. Add comprehensive variable descriptions
4. Use data sources instead of hardcoded values
5. Enable encryption by default
6. Add security group rules with descriptions
7. Use merge() for tags with common_tags
8. Follow resource naming: lowercase_with_underscores
9. Add lifecycle rules where appropriate
10. Include validation blocks for variables
```

### For OpenAI Codex CLI

```bash
# Create terraform-specific alias
alias tfc='codex suggest "Generate Terraform code following best practices:"'

# Example usage
tfc "S3 bucket with encryption and versioning"
tfc "VPC with public and private subnets across 3 AZs"
tfc "ECS cluster with Fargate"
```

### For Claude/MCP

Add system prompt in MCP config:

```markdown
When working with Terraform:
- Use semantic versioning for providers
- Always validate variables with validation blocks
- Enable encryption and security features by default
- Use data sources for dynamic values
- Include comprehensive tags
- Add detailed descriptions to all variables and outputs
- Follow naming convention: lowercase_with_underscores
- Use locals for computed values
- Implement proper state locking
```

## Common Patterns

### VPC with Subnets

```hcl
module "vpc" {
  source = "./modules/vpc"

  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs

  enable_nat_gateway = true
  single_nat_gateway = var.environment != "prod"

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-vpc"
  })
}
```

### Application Load Balancer

```hcl
resource "aws_lb" "main" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.public_subnet_ids

  enable_deletion_protection = var.environment == "prod"

  access_logs {
    bucket  = aws_s3_bucket.logs.id
    enabled = true
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-alb"
  })
}
```

### RDS Database

```hcl
resource "aws_db_instance" "main" {
  identifier        = "${var.project_name}-db"
  engine            = "postgres"
  engine_version    = "15.3"
  instance_class    = var.db_instance_class
  allocated_storage = var.db_allocated_storage

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password  # Use AWS Secrets Manager in production

  vpc_security_group_ids = [aws_security_group.database.id]
  db_subnet_group_name   = aws_db_subnet_group.main.name

  backup_retention_period = var.environment == "prod" ? 30 : 7
  backup_window          = "03:00-04:00"
  maintenance_window     = "sun:04:00-sun:05:00"

  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  storage_encrypted = true
  kms_key_id       = aws_kms_key.database.arn

  deletion_protection = var.environment == "prod"
  skip_final_snapshot = var.environment != "prod"
  final_snapshot_identifier = var.environment == "prod" ? "${var.project_name}-final-snapshot" : null

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-database"
  })
}
```

### ECS Service

```hcl
resource "aws_ecs_service" "app" {
  name            = "${var.project_name}-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.app.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = "app"
    container_port   = var.container_port
  }

  depends_on = [aws_lb_listener.app]

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-ecs-service"
  })
}
```

## Pre-commit Hooks

Add to `.pre-commit-config.yaml`:

```yaml
repos:
  - repo: https://github.com/antonbabenko/pre-commit-terraform
    rev: v1.83.5
    hooks:
      - id: terraform_fmt
      - id: terraform_validate
      - id: terraform_docs
      - id: terraform_tflint
      - id: terraform_tfsec
```

## Additional Resources

- [Terraform Best Practices](https://www.terraform-best-practices.com/)
- [AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Terraform Style Guide](https://developer.hashicorp.com/terraform/language/syntax/style)
- [Security Best Practices](https://www.hashicorp.com/resources/terraform-security-best-practices)

## Integration with AI Tools

### IntelliJ IDEA

See [IntelliJ IDEA Copilot Setup](./intellij-copilot-setup.md) for IDE-specific configuration.

### Copilot CLI

See [Copilot CLI Setup](./copilot-cli-setup.md) for terminal integration.

### OpenAI Codex

See [OpenAI Codex CLI Setup](./openai-codex-cli-setup.md) for CLI usage.
