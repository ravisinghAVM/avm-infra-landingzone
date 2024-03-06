locals {
  environment         = var.environment
  namespace           = "avm-${var.environment}"
  workspace_namespace = "avm-${terraform.workspace}-${var.environment}"
  server_namespace    = "${local.namespace}-server"
  domain_name         = var.domain_name
  firebase_project_id   = var.firebase_project_id
  firebase_private_key  = var.firebase_private_key
  firebase_client_email = var.firebase_client_email

  tags = {
    Name        = local.server_namespace
    Environment = var.environment
  }
}

data "aws_caller_identity" "current" {}

data "aws_subnets" "subnets" {
  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }
}

data "aws_rds_cluster" "this" {
  cluster_identifier = var.rds_cluster_identifier
}

data "aws_ecs_cluster" "this" {
  cluster_name = var.ecs_cluster_name
}

data "aws_secretsmanager_secret" "this" {
  arn = aws_secretsmanager_secret_version.this.arn
  depends_on = [
    aws_secretsmanager_secret_version.this
  ]
}

data "aws_secretsmanager_secret_version" "this" {
  secret_id = data.aws_secretsmanager_secret.this.id
  depends_on = [
    data.aws_secretsmanager_secret_version.this
  ]
}

################################################################################
# ECS Resources
################################################################################

resource "aws_ecs_task_definition" "this" {
  family                   = local.server_namespace
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 1024
  memory                   = 2048
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode(
    [
      {
        name : local.server_namespace,
        image : "${module.ecr.repository_url}:${var.ecr_image_tag}",
        cpu : 1024,
        memory : 2048,
        logConfiguration : {
          "logDriver" : "awslogs",
          "options" : {
            "awslogs-region" : var.region,
            "awslogs-group" : aws_cloudwatch_log_group.this.name,
            "awslogs-stream-prefix" : "ec2"
          }
        },
        portMappings : [
          {
            protocol : "tcp",
            containerPort : 443,
            hostPort : 443,
          }
        ]
        environment = [
          {
            "name" : "AWS_REGION",
            "value" : var.region,
          }
        ]
        secrets = [
          for k, v in jsondecode(data.aws_secretsmanager_secret_version.this.secret_string) :
          { name = k, valueFrom : "${aws_secretsmanager_secret.this.arn}:${k}::" }
        ]
      }
  ])
}

resource "aws_ecs_service" "this" {
  name                               = local.server_namespace
  cluster                            = data.aws_ecs_cluster.this.id
  task_definition                    = aws_ecs_task_definition.this.arn
  desired_count                      = 1
  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 100
  launch_type                        = "FARGATE"

  network_configuration {
    security_groups  = [aws_security_group.security_group_ecs_service.id]
    subnets          = toset(data.aws_subnets.subnets.ids)
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_alb_target_group.this.arn
    container_name   = local.server_namespace
    container_port   = 443
  }

  lifecycle {
    ignore_changes = [task_definition, ]
  }
}

resource "aws_alb_target_group" "this" {
  name                 = "${local.server_namespace}-tg"
  port                 = 443
  protocol             = "HTTPS"
  vpc_id               = var.vpc_id
  target_type          = "ip"
  deregistration_delay = "30"

  stickiness {
    type = "lb_cookie"
  }

  health_check {
    protocol          = "HTTPS"
    path              = "/health"
    interval          = 30
    healthy_threshold = 2
    matcher           = "200"
  }
}

resource "aws_security_group" "security_group_ecs_service" {
  name        = "${local.namespace}-server-sg"
  description = "Security Group allowing inbound traffic on port 443 from load-balancer"

  vpc_id = var.vpc_id

  # Ingress rule allowing traffic on port 443 from another Security Group
  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = ["${var.load_balancer_security_group_id}"]
  }

  ingress {
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = ["${var.load_balancer_security_group_id}"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
########################################Chat ECS Resources##########################

resource "aws_ecs_task_definition" "chat" {
  family                   = "${local.namespace}-chat"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 1024
  memory                   = 2048
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode(
    [
      {
        name : "${local.namespace}-chat"
        image : "767397974420.dkr.ecr.me-central-1.amazonaws.com/avm-chat:latest",
        cpu : 1024,
        memory : 2048,
        logConfiguration : {
          "logDriver" : "awslogs",
          "options" : {
            "awslogs-region" : var.region,
            "awslogs-group" : aws_cloudwatch_log_group.chat.name,
            "awslogs-stream-prefix" : "ec2"
          }
        },
        portMappings : [
          {
            protocol : "tcp",
            containerPort : 3000,
            hostPort : 3000,
          }
        ]
        environment = [
          {
            "name" : "AWS_REGION",
            "value" : var.region,
          }
        ]
        secrets = [
          for k, v in jsondecode(data.aws_secretsmanager_secret_version.this.secret_string) :
          { name = k, valueFrom : "${aws_secretsmanager_secret.this.arn}:${k}::" }
        ]
      }
  ])
}

resource "aws_ecs_service" "chat" {
  name                               = "${local.namespace}-chat"
  cluster                            = data.aws_ecs_cluster.this.id
  task_definition                    = aws_ecs_task_definition.chat.arn
  desired_count                      = 1
  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 100
  launch_type                        = "FARGATE"

  network_configuration {
    security_groups  = [aws_security_group.security_group_ecs_service.id]
    subnets          = toset(data.aws_subnets.subnets.ids)
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_alb_target_group.chat.arn
    container_name   = "${local.namespace}-chat"
    container_port   = 3000
  }

  lifecycle {
    ignore_changes = [task_definition, ]
  }
}

resource "aws_alb_target_group" "chat" {
  name                 = "${local.namespace}-chat-tg"
  port                 = 3000
  protocol             = "HTTP"
  vpc_id               = var.vpc_id
  target_type          = "ip"
  deregistration_delay = "30"

  stickiness {
    type = "lb_cookie"
  }

  health_check {
    protocol          = "HTTP"
    path              = "/"
    interval          = 30
    healthy_threshold = 2
    matcher           = "200"
  }
}

##################################Web App ECS resources#############################
resource "aws_ecs_task_definition" "web" {
  family                   = "${local.namespace}-web"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 1024
  memory                   = 2048
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode(
    [
      {
        name : "${local.namespace}-web"
        image : "767397974420.dkr.ecr.me-central-1.amazonaws.com/avm-webapp:latest",
        cpu : 1024,
        memory : 2048,
        logConfiguration : {
          "logDriver" : "awslogs",
          "options" : {
            "awslogs-region" : var.region,
            "awslogs-group" : aws_cloudwatch_log_group.web_app.name,
            "awslogs-stream-prefix" : "ec2"
          }
        },
        portMappings : [
          {
            protocol : "tcp",
            containerPort : 3000,
            hostPort : 3000,
          }
        ]
        environment = [
          {
            "name" : "AWS_REGION",
            "value" : var.region,
          }
        ]
        secrets = [
          for k, v in jsondecode(data.aws_secretsmanager_secret_version.this.secret_string) :
          { name = k, valueFrom : "${aws_secretsmanager_secret.this.arn}:${k}::" }
        ]
      }
  ])
}

resource "aws_ecs_service" "web" {
  name                               = "${local.namespace}-web"
  cluster                            = data.aws_ecs_cluster.this.id
  task_definition                    = aws_ecs_task_definition.web.arn
  desired_count                      = 1
  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 100
  launch_type                        = "FARGATE"

  network_configuration {
    security_groups  = [aws_security_group.security_group_ecs_service.id]
    subnets          = toset(data.aws_subnets.subnets.ids)
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_alb_target_group.web.arn
    container_name   = "${local.namespace}-web"
    container_port   = 3000
  }

  lifecycle {
    ignore_changes = [task_definition, ]
  }
}

resource "aws_alb_target_group" "web" {
  name                 = "${local.namespace}-web-tg"
  port                 = 3000
  protocol             = "HTTP"
  vpc_id               = var.vpc_id
  target_type          = "ip"
  deregistration_delay = "30"

  stickiness {
    type = "lb_cookie"
  }

  health_check {
    protocol          = "HTTP"
    path              = "/"
    interval          = 30
    healthy_threshold = 2
    matcher           = "200"
  }
}


################################################################################
# Autoscaling
################################################################################

resource "aws_appautoscaling_target" "this" {
  service_namespace  = "ecs"
  resource_id        = "service/${var.ecs_cluster_name}/${aws_ecs_service.this.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  min_capacity       = var.autoscaling_min_instances
  max_capacity       = var.autoscaling_max_instances
}

resource "aws_appautoscaling_policy" "autoscaling_up_policy" {
  name               = "${local.server_namespace}-scale-up-policy"
  depends_on         = [aws_appautoscaling_target.this]
  service_namespace  = aws_appautoscaling_target.this.service_namespace
  resource_id        = aws_appautoscaling_target.this.resource_id
  scalable_dimension = aws_appautoscaling_target.this.scalable_dimension

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = 60
    metric_aggregation_type = "Maximum"

    step_adjustment {
      metric_interval_lower_bound = 0
      scaling_adjustment          = 1
    }
  }
}

resource "aws_appautoscaling_policy" "autoscaling_down_policy" {
  name               = "${local.server_namespace}-scale-down-policy"
  depends_on         = [aws_appautoscaling_target.this]
  service_namespace  = aws_appautoscaling_target.this.service_namespace
  resource_id        = aws_appautoscaling_target.this.resource_id
  scalable_dimension = aws_appautoscaling_target.this.scalable_dimension

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = 300
    metric_aggregation_type = "Maximum"

    step_adjustment {
      metric_interval_upper_bound = 0
      scaling_adjustment          = -1
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "cloudwatch_alarm_cpu_usage_high" {
  alarm_name          = "${local.server_namespace}-cpu-usage-high"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = var.autoscaling_cpu_high_threshold

  alarm_actions = [aws_appautoscaling_policy.autoscaling_up_policy.arn]

  dimensions = {
    ClusterName = data.aws_ecs_cluster.this.cluster_name
    ServiceName = aws_ecs_service.this.name
  }

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "cloudwatch_alarm_cpu_usage_low" {
  alarm_name          = "${local.server_namespace}-cpu-usage-low"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = var.autoscaling_cpu_low_threshold

  alarm_actions = [aws_appautoscaling_policy.autoscaling_down_policy.arn]

  dimensions = {
    ClusterName = data.aws_ecs_cluster.this.cluster_name
    ServiceName = aws_ecs_service.this.name
  }

  tags = local.tags
}

################################################################################
# S3
################################################################################

resource "aws_s3_bucket" "aws_s3_bucket_documents" {
  bucket        = "${local.workspace_namespace}-${data.aws_caller_identity.current.account_id}-documents"
  force_destroy = true
}

resource "aws_s3_bucket" "aws_s3_bucket_assets" {
  bucket        = "${local.workspace_namespace}-${data.aws_caller_identity.current.account_id}-assets"
  force_destroy = true
}

resource "aws_s3_bucket" "aws_s3_bucket_logs" {
  bucket        = "${local.workspace_namespace}-${data.aws_caller_identity.current.account_id}-bucket-access-logs"
  force_destroy = true
}

resource "aws_s3_bucket_cors_configuration" "aws_s3_bucket_assets_cors" {
  bucket = aws_s3_bucket.aws_s3_bucket_assets.id

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

resource "aws_s3_bucket_cors_configuration" "aws_s3_bucket_documents_cors" {
  bucket = aws_s3_bucket.aws_s3_bucket_documents.id

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

resource "aws_s3_bucket_logging" "aws_s3_bucket_logging_documents" {
  bucket = aws_s3_bucket.aws_s3_bucket_documents.id

  target_bucket = aws_s3_bucket.aws_s3_bucket_logs.id
  target_prefix = aws_s3_bucket.aws_s3_bucket_documents.bucket
}

resource "aws_s3_bucket_logging" "aws_s3_bucket_logging_assets" {
  bucket = aws_s3_bucket.aws_s3_bucket_assets.id

  target_bucket = aws_s3_bucket.aws_s3_bucket_logs.id
  target_prefix = aws_s3_bucket.aws_s3_bucket_assets.bucket
}

################################################################################
# ECR Repository
################################################################################

module "ecr" {
  source  = "terraform-aws-modules/ecr/aws"
  version = "~> 1.6.0"

  repository_name                   = "avm-server"
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

resource "random_password" "password" {
  count   = 1
  length  = 30
  special = true
}

resource "aws_secretsmanager_secret" "this" {
  name = local.server_namespace

  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "this" {
  secret_id = aws_secretsmanager_secret.this.id
  secret_string = jsonencode(
    {
      "NODE_ENV" : "production",
      "AWS_DOCUMENTS_S3_BUCKET" : aws_s3_bucket.aws_s3_bucket_documents.bucket,
      "AWS_ASSETS_S3_BUCKET" : aws_s3_bucket.aws_s3_bucket_assets.bucket,
      "AWS_DEFAULT_KMS_KEY_ID" : aws_kms_key.kms_key_server.key_id,
      "DB_URI" : "postgres://${data.aws_rds_cluster.this.master_username}:${var.rds_master_password}@${data.aws_rds_cluster.this.endpoint}:${data.aws_rds_cluster.this.port}/${data.aws_rds_cluster.this.database_name}",
      "DB_VECTOR_URI" : "postgres://${data.aws_rds_cluster.this.master_username}:${var.rds_master_password}@${data.aws_rds_cluster.this.endpoint}:${data.aws_rds_cluster.this.port}/vectordb",
      "UI_HOST" : "https://${local.domain_name}"
      "API_KEY" : random_password.password[0].result,
      "FIREBASE_PRIVATE_KEY" : "${local.firebase_private_key}",
      "FIREBASE_CLIENT_EMAIL" : "${local.firebase_client_email}",
      "FIREBASE_PROJECT_ID" : "${local.firebase_project_id}",
      "GOOGLE_DRIVE_CLIENT_ID" : "<REPLACE_ME>",
      "GOOGLE_DRIVE_CLIENT_SECRET" : "<REPLACE_ME>",
      "AWS_SES_ACCESS_KEY" : "<REPLACE_ME>",
      "AWS_SES_SECRET_KEY" : "<REPLACE_ME>",
  })

  lifecycle {
    ignore_changes = [secret_string, ]
  }
}

resource "aws_kms_key" "kms_key_server" {
  description = "KMS for server side encryption"

  tags = local.tags
}

resource "aws_kms_alias" "kms_alias_server" {
  name          = "alias/${local.server_namespace}-kms-key"
  target_key_id = aws_kms_key.kms_key_server.key_id
}

resource "aws_cloudwatch_log_group" "this" {
  name              = local.server_namespace
  retention_in_days = 365
}

resource "aws_cloudwatch_log_group" "chat" {
  name              = "${local.server_namespace}-chat"
  retention_in_days = 365
}

resource "aws_cloudwatch_log_group" "web_app" {
  name              = "${local.server_namespace}-web-app"
  retention_in_days = 365
}

resource "aws_iam_role" "ecs_task_execution_role" {
  name = "${local.server_namespace}-ecsTaskExecutionRole"

  assume_role_policy = jsonencode(
    {
      "Version" : "2012-10-17",
      "Statement" : [
        {
          "Action" : "sts:AssumeRole",
          "Principal" : {
            "Service" : "ecs-tasks.amazonaws.com"
          },
          "Effect" : "Allow"
        }
      ]
  })
}

resource "aws_iam_role" "ecs_task_role" {
  name = "${local.server_namespace}-ecsTaskRole"

  assume_role_policy = jsonencode(
    {
      "Version" : "2012-10-17",
      "Statement" : [
        {
          "Action" : "sts:AssumeRole",
          "Principal" : {
            "Service" : "ecs-tasks.amazonaws.com"
          },
          "Effect" : "Allow"
        }
      ]
  })
}

resource "aws_iam_policy" "aws_iam_policy_secrets_manager" {
  name        = "${local.server_namespace}-secrets-manager-policy"
  description = "Access control for Secrets Manager"

  policy = jsonencode(
    {
      "Version" : "2012-10-17",
      "Statement" : [
        {
          "Action" : [
            "secretsmanager:GetResourcePolicy",
            "secretsmanager:GetSecretValue",
            "secretsmanager:DescribeSecret",
            "secretsmanager:ListSecretVersionIds"
          ],
          "Effect" : "Allow",
          "Resource" : [
            aws_secretsmanager_secret.this.arn
          ],
        }
      ]
  })
}

resource "aws_iam_policy" "aws_iam_policy_s3" {
  name        = "${local.namespace}-s3-policy"
  description = "Access control for S3 resources"

  policy = jsonencode(
    {
      "Version" : "2012-10-17",
      "Statement" : [
        {
          "Effect" : "Allow",
          "Action" : [
            "s3:*"
          ],
          "Resource" : [
            "arn:aws:s3:::${local.workspace_namespace}-*",
            "arn:aws:s3:::${local.workspace_namespace}-*/*",
          ]
        },
      ]
  })
}

resource "aws_iam_policy" "aws_iam_policy_bedrock" {
  name        = "${local.namespace}-bedrock-policy"
  description = "Access control for Bedrock resources"

  policy = jsonencode(
    {
      "Version" : "2012-10-17",
      "Statement" : [
        {
          "Effect" : "Allow",
          "Action" : [
            "bedrock:*"
          ],
          "Resource" : [
            "*",
          ]
        },
      ]
  })
}

resource "aws_iam_policy" "aws_iam_policy_sagemaker" {
  name        = "${local.namespace}-sagemaker-policy"
  description = "Access control for Sagemaker resources"

  policy = jsonencode(
    {
      "Version" : "2012-10-17",
      "Statement" : [
        {
          "Effect" : "Allow",
          "Action" : [
            "sagemaker:*"
          ],
          "Resource" : [
            "*",
          ]
        },
      ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_role_policy_attachment" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy_attachment" "secrets_manager_ecs_task_policy_attachment" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = aws_iam_policy.aws_iam_policy_secrets_manager.arn
}

resource "aws_iam_role_policy_attachment" "secrets_manager_ecs_task_execution_policy_attachment" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = aws_iam_policy.aws_iam_policy_secrets_manager.arn
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy_attachment" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy_attachment" "comprehend_ecs_task_policy_attachment" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = "arn:aws:iam::aws:policy/ComprehendFullAccess"
}

resource "aws_iam_role_policy_attachment" "comprehend_ecs_task_execution_policy_attachment" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/ComprehendFullAccess"
}

resource "aws_iam_role_policy_attachment" "comprehend_medical_ecs_task_policy_attachment" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = "arn:aws:iam::aws:policy/ComprehendMedicalFullAccess"
}

resource "aws_iam_role_policy_attachment" "comprehend_medical_ecs_task_execution_policy_attachment" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/ComprehendMedicalFullAccess"
}

resource "aws_iam_role_policy_attachment" "s3_ecs_task_role_policy_attachment" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = aws_iam_policy.aws_iam_policy_s3.arn
}

resource "aws_iam_role_policy_attachment" "s3_ecs_task_execution_policy_attachment" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = aws_iam_policy.aws_iam_policy_s3.arn
}

resource "aws_iam_role_policy_attachment" "bedrock_ecs_task_role_policy_attachment" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = aws_iam_policy.aws_iam_policy_bedrock.arn
}

resource "aws_iam_role_policy_attachment" "bedrock_ecs_task_execution_policy_attachment" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = aws_iam_policy.aws_iam_policy_bedrock.arn
}

resource "aws_iam_role_policy_attachment" "sagemaker_ecs_task_role_policy_attachment" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = aws_iam_policy.aws_iam_policy_sagemaker.arn
}

resource "aws_iam_role_policy_attachment" "sagemaker_ecs_task_execution_policy_attachment" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = aws_iam_policy.aws_iam_policy_sagemaker.arn
}
