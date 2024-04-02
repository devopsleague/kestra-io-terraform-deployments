terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~>5.42.0"
    }
  }
}

provider "aws" {
  region  = "eu-central-1"
  profile = "kestra"
  default_tags {
    tags = {
      project = "scriptRunner"
    }
  }
}

# Get the S3 bucket or replace with a resource to create a new bucket
data "aws_s3_bucket" "kestra_bucket" {
  bucket = "kestra-product-de"
}

# Get the default VPC for this region
data "aws_vpc" "default" {
  default = true
}

# Get the subnet IDs in the default VPC for this region
data "aws_subnets" "all_default_subnets" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_security_group" "aws_batch_sg" {
  name        = "kestraAwsBatchSG"
  vpc_id      = data.aws_vpc.default.id
  description = "batch VPC security group"

  egress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    cidr_blocks = [
      "0.0.0.0/0",
    ]
  }
}

resource "aws_iam_role" "batch_service_role" {
  name = "batchServiceRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "batch.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "batch_service_role_policy_attachment" {
  role       = aws_iam_role.batch_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBatchServiceRole"
}

resource "aws_batch_compute_environment" "aws_batch_compute_environment" {
  compute_environment_name = "kestraFargateEnvironment"

  compute_resources {
    max_vcpus = 256
    security_group_ids = [
      aws_security_group.aws_batch_sg.id,
    ]
    subnets = data.aws_subnets.all_default_subnets.ids
    type    = "FARGATE"
  }
  service_role = aws_iam_role.batch_service_role.arn
  type         = "MANAGED"
  depends_on = [
    aws_iam_role_policy_attachment.batch_service_role_policy_attachment
  ]
}

resource "aws_batch_job_queue" "aws_batch_job_queue" {
  name     = "kestraJobQueue"
  state    = "ENABLED"
  priority = "1"
  compute_environment_order {
    order               = 1
    compute_environment = aws_batch_compute_environment.aws_batch_compute_environment.arn
  }
}

resource "aws_iam_role" "aws_ecs_task_execution_role" {
  name = "kestraEcsTaskExecutionRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_policy_attachment" {
  role       = aws_iam_role.aws_ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Create an ECS task role that includes S3 access permissions
resource "aws_iam_role" "ecs_task_role" {
  name = "ecsTaskRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      },
    ]
  })
}

resource "aws_iam_policy" "ecs_task_role_s3_policy" {
  name = "ecsTaskRoleS3Policy"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ],
        Resource = "*",
        Effect   = "Allow"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_role_s3_policy_attachment" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = aws_iam_policy.ecs_task_role_s3_policy.arn
}
