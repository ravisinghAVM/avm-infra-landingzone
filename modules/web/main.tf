locals {
  environment         = var.environment
  namespace           = "avm-${var.environment}"
  workspace_namespace = "avm-${terraform.workspace}-${var.environment}"
  domain_name         = var.domain_name

  tags = {
    Name        = local.namespace
    Environment = var.environment
  }
}

data "aws_caller_identity" "current" {}

################################################################################
# S3
################################################################################

resource "aws_s3_bucket" "aws_s3_bucket_web" {
  bucket        = "admin.${local.domain_name}"
  force_destroy = true
}

resource "aws_s3_bucket_policy" "aws_s3_bucket_policy_vpc_endpoint" {
  bucket = aws_s3_bucket.aws_s3_bucket_web.id
  policy = jsonencode(
    {
      "Version" : "2012-10-17",
      "Statement" : [
        {
          "Principal" : "*",
          "Action" : "s3:GetObject",
          "Effect" : "Allow",
          "Resource" : ["${aws_s3_bucket.aws_s3_bucket_web.arn}",
          "${aws_s3_bucket.aws_s3_bucket_web.arn}/*"],
          "Condition" : {
            "StringEquals" : {
              "aws:SourceVpce" : "vpce-0935a11b53c486e1d"
            }
          }
        }
      ]
    }
  )
}

resource "aws_s3_bucket_cors_configuration" "aws_s3_bucket_web_cors" {
  bucket = aws_s3_bucket.aws_s3_bucket_web.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "PUT", "POST", "DELETE", "HEAD"]
    allowed_origins = ["*"]
    expose_headers  = []
    max_age_seconds = 3000
  }

  cors_rule {
    allowed_methods = ["GET"]
    allowed_origins = ["*"]
  }
}

################################################################################
# ECR Repository
################################################################################

module "ecr" {
  source  = "terraform-aws-modules/ecr/aws"
  version = "~> 1.6.0"

  repository_name                   = "avm-webapp"
  repository_read_write_access_arns = [data.aws_caller_identity.current.arn]
  create_lifecycle_policy           = true

  repository_image_tag_mutability = "MUTABLE"
  repository_encryption_type      = "KMS"
  repository_force_delete         = true

  repository_lifecycle_policy = jsonencode({
    rules = [
      {
        rulePriority = 1,
        description  = "Keep only tagged images",
        selection = {
          tagStatus   = "untagged",
          countType   = "imageCountMoreThan",
          countNumber = 1
        },
        action = {
          type = "expire"
        }
      }
    ]
  })

  tags = local.tags
}

################################################################################
# Supporting Resources
################################################################################

resource "aws_secretsmanager_secret" "this" {
  name = "${local.namespace}-webapp"

  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "this" {
  secret_id = aws_secretsmanager_secret.this.id
  secret_string = jsonencode(
    {
      "REACT_APP_FIREBASE_API_KEY" : var.firebase_api_key,
      "REACT_APP_FIREBASE_AUTH_DOMAIN" : var.firebase_auth_domain,
      "REACT_APP_FIREBASE_PROJECT_ID" : var.firebase_project_id,
      "REACT_APP_FIREBASE_STORAGE_BUCKET" : var.firebase_storage_bucket,
      "REACT_APP_FIREBASE_MESSAGING_SENDER_ID" : var.firebase_messaging_sender_id,
      "REACT_APP_FIREBASE_APP_ID" : var.firebase_app_id,
      "REACT_APP_FIREBASE_MEASUREMENT_ID" : var.firebase_measurement_id,
  })

  lifecycle {
    ignore_changes = [secret_string, ]
  }
}
