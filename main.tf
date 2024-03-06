provider "aws" {
  region = local.region
}

locals {
  region              = var.region
  namespace           = "avm-${var.environment}"
  workspace_namespace = "avm-${terraform.workspace}-${var.environment}"
  environment         = var.environment
  domain_name         = "${terraform.workspace}.${var.root_domain_name}"
  account_id          = data.aws_caller_identity.current.account_id

  vpc_cidr = "10.0.0.0/16"
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)

  tags = {
    Name         = local.namespace
    Environment  = var.environment
    map-migrated = "mig5TZY31HX9S"
  }
}

data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {}

################################################################################
# VPC Module
################################################################################
data "aws_vpc" "vpc" {
  id = "vpc-09a3c73e6d7db4347"
}


data "aws_subnets" "avm" {
  filter {
    name   = "vpc-id"
    values = ["vpc-09a3c73e6d7db4347"]
  }
}

data "aws_subnet" "avm" {
  for_each = toset(data.aws_subnets.avm.ids)
  id       = each.value
}

data "aws_subnet" "app_subnet_1" {
  filter {
    name   = "tag:aws:cloudformation:logical-id"
    values = ["rAppSubnet1"]
  }
}
data "aws_subnet" "app_subnet_2" {
  filter {
    name   = "tag:aws:cloudformation:logical-id"
    values = ["rAppSubnet2"]
  }
}
data "aws_subnet" "database_subnet_1" {
  filter {
    name   = "tag:aws:cloudformation:logical-id"
    values = ["rDataSubnet1"]
  }
}
data "aws_subnet" "database_subnet_2" {
  filter {
    name   = "tag:aws:cloudformation:logical-id"
    values = ["rDataSubnet2"]
  }
}

resource "aws_db_subnet_group" "avm" {
  name       = "avm-database-subnet-group"
  subnet_ids = [data.aws_subnet.database_subnet_1.id, data.aws_subnet.database_subnet_2.id]

  tags = {
    Name = "My DB subnet group"
  }
}

################################################################################
# ECS Module
################################################################################

module "ecs" {
  source  = "terraform-aws-modules/ecs/aws"
  version = "~> 5.2"

  cluster_name = "${local.namespace}-cluster"

  create_cloudwatch_log_group            = true
  cloudwatch_log_group_retention_in_days = 365

  # capacity provider
  fargate_capacity_providers = {
    FARGATE = {
      default_capacity_provider_strategy = {
        weight = 50
        base   = 20
      }
    }
    FARGATE_SPOT = {
      default_capacity_provider_strategy = {
        weight = 50
      }
    }
  }

  tags = local.tags
}

################################################################################
# ALB Module
################################################################################

module "alb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "~> 8.7"

  name               = "avm-sit-alb"
  internal           = true
  load_balancer_type = "application"
  idle_timeout       = 3600

  vpc_id                = data.aws_vpc.vpc.id
  subnets               = ["${data.aws_subnet.app_subnet_1.id}", "${data.aws_subnet.app_subnet_2.id}"]
  security_groups       = [aws_security_group.lb.id]
  create_security_group = false

  tags = local.tags
}

resource "aws_lb_listener" "http_listener" {
  load_balancer_arn = module.alb.lb_arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = module.server.target_group_arn
  }
}

resource "aws_lb_listener" "https_listener" {
  load_balancer_arn = module.alb.lb_arn
  port              = 443
  protocol          = "HTTPS"
  certificate_arn   = "arn:aws:acm:me-central-1:767397974420:certificate/e08588e4-2df6-4688-82ea-3c8e0d19c06e"
  default_action {
    type             = "forward"
    target_group_arn = module.server.target_group_arn
  }
}

resource "aws_lb_listener_rule" "chat_https" {
  listener_arn = aws_lb_listener.https_listener.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = module.server.chat_target_group_id
  }

  condition {
    host_header {
      values = ["chat.avm-genaipilot.adcbmis.local"]
    }
  }
}

resource "aws_lb_listener_rule" "chat_http" {
  listener_arn = aws_lb_listener.http_listener.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = module.server.chat_target_group_id
  }

  condition {
    host_header {
      values = ["chat.avm-genaipilot.adcbmis.local"]
    }
  }
}

resource "aws_lb_listener_rule" "admin_https" {
  listener_arn = aws_lb_listener.https_listener.arn
  priority     = 200

  action {
    type             = "forward"
    target_group_arn = module.server.web_target_group_id
  }

  condition {
    host_header {
      values = ["admin.avm-genaipilot.adcbmis.local"]
    }
  }
}

resource "aws_lb_listener_rule" "admin_http" {
  listener_arn = aws_lb_listener.http_listener.arn
  priority     = 200

  action {
    type             = "forward"
    target_group_arn = module.server.web_target_group_id
  }

  condition {
    host_header {
      values = ["admin.avm-genaipilot.adcbmis.local"]
    }
  }
}

resource "aws_wafv2_web_acl_association" "this" {
  resource_arn = module.alb.lb_arn
  web_acl_arn  = aws_wafv2_web_acl.web_acl_alb.arn
}

data "aws_ec2_managed_prefix_list" "cloudfront" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

resource "aws_security_group" "lb" {
  name   = "${local.namespace}-alb-sg"
  vpc_id = data.aws_vpc.vpc.id
}

resource "aws_security_group_rule" "lb_ingress_cloudfront" {
  description       = "HTTPS from CloudFront"
  security_group_id = aws_security_group.lb.id
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = [data.aws_vpc.vpc.cidr_block]
}

resource "aws_security_group_rule" "lb_ingress_https" {
  description       = "HTTPS from CloudFront"
  security_group_id = aws_security_group.lb.id
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = [data.aws_vpc.vpc.cidr_block, "10.124.32.0/23", "10.124.60.0/23", "10.125.32.0/23", "10.125.60.0/23"]
}

resource "aws_vpc_security_group_egress_rule" "example" {
  security_group_id = aws_security_group.lb.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_cloudwatch_metric_alarm" "cloudwatch_alarm_alb_unhealthy_hosts" {
  alarm_name          = "${local.namespace}-alb-unhealthy-hosts"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = var.statistic_period
  statistic           = "Minimum"
  threshold           = var.alb_unhealthy_hosts_threshold
  alarm_description   = "Unhealthy host count too high"

  alarm_actions = aws_sns_topic.sns_topic_alerts.*.arn
  ok_actions    = aws_sns_topic.sns_topic_alerts.*.arn

  dimensions = {
    LoadBalancer = module.alb.lb_id
  }

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "cloudwatch_alarm_alb_response_time" {
  alarm_name          = "${local.namespace}-alb-response-time"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = var.statistic_period
  statistic           = "Average"
  threshold           = var.alb_response_time_threshold
  alarm_description   = "Average API response time is too high"

  alarm_actions = aws_sns_topic.sns_topic_alerts.*.arn
  ok_actions    = aws_sns_topic.sns_topic_alerts.*.arn

  dimensions = {
    LoadBalancer = module.alb.lb_id
  }

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "cloudwatch_alarm_alb_target_5xx_count" {
  alarm_name          = "${local.namespace}-alb-5xx-count"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "HTTPCode_ELB_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = var.statistic_period
  statistic           = "Sum"
  threshold           = var.alb_5xx_response_threshold
  alarm_description   = "Average API 5XX load balancer error code count is too high"

  alarm_actions = aws_sns_topic.sns_topic_alerts.*.arn
  ok_actions    = aws_sns_topic.sns_topic_alerts.*.arn

  dimensions = {
    LoadBalancer = module.alb.lb_id
  }

  tags = local.tags
}

################################################################################
# RDS Module
################################################################################

module "cluster" {
  source = "terraform-aws-modules/rds-aurora/aws"

  name              = "${local.workspace_namespace}-cluster"
  engine            = "aurora-postgresql"
  engine_mode       = "provisioned"
  engine_version    = "15.3"
  storage_encrypted = true

  port                        = var.rds_port
  database_name               = var.rds_database_name
  master_username             = var.rds_master_username
  master_password             = var.rds_master_password != "" ? var.rds_master_password : random_password.password[0].result
  manage_master_user_password = false

  vpc_id                 = data.aws_vpc.vpc.id
  vpc_security_group_ids = [module.security_group_rds.security_group_id]
  db_subnet_group_name   = aws_db_subnet_group.avm.name
  create_security_group  = false

  apply_immediately            = true
  skip_final_snapshot          = true
  performance_insights_enabled = true
  deletion_protection          = true
  monitoring_interval          = 60

  serverlessv2_scaling_configuration = {
    min_capacity = 1
    max_capacity = 16
  }

  instance_class = "db.serverless"
  instances = {
    1 = {
      identifier = "${local.workspace_namespace}-instance-1"
    }
  }

  tags = {
    Name         = local.namespace
    Environment  = var.environment
    map-migrated = "comm5TZY31HX9S"
  }
}

module "security_group_rds" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.1"

  name            = "${local.namespace}-rds-sg"
  description     = "Control traffic to/from RDS instances"
  vpc_id          = data.aws_vpc.vpc.id
  use_name_prefix = false

  # ingress
  ingress_with_cidr_blocks = [
    {
      from_port   = var.rds_port
      to_port     = var.rds_port
      protocol    = "tcp"
      description = "Allow inbound traffic from existing Security Groups"
      cidr_blocks = data.aws_vpc.vpc.cidr_block
    }
  ]

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "cloudwatch_alarm_rds_cpu_usage" {
  alarm_name          = "${local.namespace}-rds-cpu-usage"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = var.statistic_period
  statistic           = "Average"
  threshold           = var.rds_cpu_usage_threshold
  alarm_description   = "Average database CPU utilization too high"

  alarm_actions = aws_sns_topic.sns_topic_alerts.*.arn
  ok_actions    = aws_sns_topic.sns_topic_alerts.*.arn

  dimensions = {
    DBClusterIdentifier = module.cluster.cluster_id
  }

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "cloudwatch_alarm_rds_local_storage" {
  alarm_name          = "${local.namespace}-rds-local-storage"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "FreeLocalStorage"
  namespace           = "AWS/RDS"
  period              = var.statistic_period
  statistic           = "Average"
  threshold           = var.rds_local_storage_threshold
  alarm_description   = "Average database local storage too low"

  alarm_actions = aws_sns_topic.sns_topic_alerts.*.arn
  ok_actions    = aws_sns_topic.sns_topic_alerts.*.arn

  dimensions = {
    DBClusterIdentifier = module.cluster.cluster_id
  }

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "cloudwatch_alarm_rds_freeable_memory" {
  alarm_name          = "${local.namespace}-rds-freeable-memory"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "FreeableMemory"
  namespace           = "AWS/RDS"
  period              = var.statistic_period
  statistic           = "Average"
  threshold           = var.rds_freeable_memory_threshold
  alarm_description   = "Average database random access memory too low"

  alarm_actions = aws_sns_topic.sns_topic_alerts.*.arn
  ok_actions    = aws_sns_topic.sns_topic_alerts.*.arn

  dimensions = {
    DBClusterIdentifier = module.cluster.cluster_id
  }

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "cloudwatch_alarm_rds_disk_queue_depth_high" {
  alarm_name          = "${local.namespace}-rds-disk-queue-depth-high"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "DiskQueueDepth"
  namespace           = "AWS/RDS"
  period              = var.statistic_period
  statistic           = "Average"
  threshold           = var.rds_freeable_memory_threshold
  alarm_description   = "Average database disk queue depth too high"

  alarm_actions = aws_sns_topic.sns_topic_alerts.*.arn
  ok_actions    = aws_sns_topic.sns_topic_alerts.*.arn

  dimensions = {
    DBClusterIdentifier = module.cluster.cluster_id
  }

  tags = local.tags
}

################################################################################
# ElastiCache Module
################################################################################

resource "aws_elasticache_replication_group" "redis" {
  count                = 0
  replication_group_id = "${local.namespace}-cluster"
  description          = "Redis cluster"

  engine                     = "redis"
  node_type                  = "cache.t4g.medium"
  engine_version             = "7.0"
  port                       = var.redis_port
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  num_cache_clusters         = 1

  security_group_ids         = [module.security_group_redis.security_group_id]
  subnet_group_name          = join("", aws_elasticache_subnet_group.default.*.name)
  apply_immediately          = true
  automatic_failover_enabled = false

  lifecycle {
    ignore_changes = [node_type, ]
  }

  tags = local.tags
}

resource "aws_elasticache_subnet_group" "default" {
  count       = 0
  name        = "${local.namespace}-redis"
  description = "Allowed subnets for Redis cluster instances"
  subnet_ids  = toset(data.aws_subnets.avm.ids)

  tags = local.tags
}

module "security_group_redis" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.1"

  name            = "${local.namespace}-redis-sg"
  description     = "Security Group for Redis cluster"
  vpc_id          = data.aws_vpc.vpc.id
  use_name_prefix = false

  ingress_cidr_blocks = ["${data.aws_vpc.vpc.cidr_block}"]
  ingress_with_cidr_blocks = [
    {
      from_port   = var.redis_port
      to_port     = var.redis_port
      protocol    = "tcp"
      description = "Allow inbound traffic from existing Security Groups"
      cidr_blocks = "${data.aws_vpc.vpc.cidr_block}"
    }
  ]
  egress_rules = ["all-all"]

  tags = local.tags
}

################################################################################
# Security Module
################################################################################

resource "aws_cloudwatch_event_rule" "cloudwatch_event_rule_guardduty" {
  name        = "${local.namespace}-guardduty-finding-events"
  description = "AWS GuardDuty event findings"
  event_pattern = jsonencode(
    {
      "detail-type" : [
        "GuardDuty Finding"
      ],
      "source" : [
        "aws.guardduty"
      ]
  })
}

resource "aws_cloudwatch_event_target" "cloudwatch_event_target_alerts" {
  rule      = aws_cloudwatch_event_rule.cloudwatch_event_rule_guardduty.name
  target_id = "${local.namespace}-send-to-sns-alerts"
  arn       = aws_sns_topic.sns_topic_alerts.arn

  input_transformer {
    input_paths = {
      title       = "$.detail.title"
      description = "$.detail.description"
      eventTime   = "$.detail.service.eventFirstSeen"
      region      = "$.detail.region"
    }

    input_template = "\"GuardDuty finding in <region> first seen at <eventTime>: <title> <description>\""
  }
}

################################################################################
# Supporting Resources
################################################################################

resource "random_password" "password" {
  count   = var.rds_master_password != "" ? 0 : 1
  length  = 20
  special = false
}

resource "aws_sns_topic" "sns_topic_alerts" {
  name = "${local.namespace}-alerts"
}

resource "aws_sns_topic_subscription" "sns_topic_subscription_notifications" {
  topic_arn = aws_sns_topic.sns_topic_alerts.arn
  protocol  = "email"
  endpoint  = var.notifications_email
}

resource "aws_wafv2_web_acl" "web_acl_alb" {
  name  = "${local.namespace}-alb-waf"
  scope = "REGIONAL"

  default_action {
    allow {}
  }

  rule {
    name     = "AWS-AWSManagedRulesAmazonIpReputationList"
    priority = 0

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesAmazonIpReputationList"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWS-AWSManagedRulesAmazonIpReputationList"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWS-AWSManagedRulesCommonRuleSet"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWS-AWSManagedRulesCommonRuleSet"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWS-AWSManagedRulesKnownBadInputsRuleSet"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWS-AWSManagedRulesKnownBadInputsRuleSet"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${local.namespace}-cloudfront-waf"
    sampled_requests_enabled   = true
  }

  tags = local.tags
}

resource "aws_secretsmanager_secret" "this" {
  name = "${local.namespace}-container-registry"

  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "this" {
  secret_id = aws_secretsmanager_secret.this.id
  secret_string = jsonencode(
    {
      "CONTAINER_REGISTRY_USERNAME" : var.container_registry_username,
      "CONTAINER_REGISTRY_TOKEN" : var.container_registry_token != "" ? var.container_registry_token : "<REPLACE_ME>",
  })

  lifecycle {
    ignore_changes = [secret_string, ]
  }
}

################################################################################
# Server Module
################################################################################

module "server" {
  source = "./modules/server"

  region                          = local.region
  environment                     = local.environment
  domain_name                     = local.domain_name
  vpc_id                          = data.aws_vpc.vpc.id
  load_balancer_security_group_id = aws_security_group.lb.id
  ecs_cluster_name                = module.ecs.cluster_name
  rds_cluster_identifier          = module.cluster.cluster_id
  rds_master_password             = var.rds_master_password != "" ? var.rds_master_password : random_password.password[0].result
  firebase_project_id             = var.firebase_project_id
  firebase_private_key            = var.firebase_private_key
  firebase_client_email           = var.firebase_client_email

  depends_on = [
    module.ecs
  ]
}

################################################################################
# Web Module
################################################################################

module "web" {
  source = "./modules/web"

  region                       = local.region
  environment                  = local.environment
  domain_name                  = local.domain_name
  firebase_api_key             = var.firebase_api_key
  firebase_auth_domain         = var.firebase_auth_domain
  firebase_project_id          = var.firebase_project_id
  firebase_storage_bucket      = var.firebase_storage_bucket
  firebase_messaging_sender_id = var.firebase_messaging_sender_id
  firebase_app_id              = var.firebase_app_id
  firebase_measurement_id      = var.firebase_measurement_id

}

################################################################################
# Chat Module
################################################################################

module "chat" {
  source = "./modules/chat"

  region                       = local.region
  environment                  = local.environment
  domain_name                  = local.domain_name
  firebase_api_key             = var.firebase_api_key
  firebase_auth_domain         = var.firebase_auth_domain
  firebase_project_id          = var.firebase_project_id
  firebase_storage_bucket      = var.firebase_storage_bucket
  firebase_messaging_sender_id = var.firebase_messaging_sender_id
  firebase_app_id              = var.firebase_app_id
  firebase_measurement_id      = var.firebase_measurement_id
}

################################################################################
# CI/CD Module
################################################################################

module "ci-cd" {
  source = "./modules/ci-cd"

  region                            = local.region
  environment                       = local.environment
  s3_bucket_name_webapp             = module.web.s3_bucket_name
  s3_bucket_name_chat               = module.chat.s3_bucket_name
  secretsmanager_secret_id_webapp   = module.web.secretsmanager_secret_id
  secretsmanager_secret_id_chat     = module.chat.secretsmanager_secret_id
  secretsmanager_secret_id_server   = module.server.secretsmanager_secret_id
  secretsmanager_secret_id_registry = aws_secretsmanager_secret.this.id
  ecr_repository_url_webapp         = module.web.ecr_repository_url
  ecr_repository_url_chat           = module.chat.ecr_repository_url
  ecr_repository_url_server         = module.server.ecr_repository_url
  ecs_cluster_name                  = module.ecs.cluster_name
  ecs_service_name_server           = module.server.ecs_service_name
  sns_topic_alerts_arn              = aws_sns_topic.sns_topic_alerts.arn #

  depends_on = [
    module.web,
    module.chat,
    module.server,
  ]
}

################################################################################
# Vanta Module
################################################################################

module "vanta" {
  source = "./modules/vanta"

  count       = 0
  region      = local.region
  environment = local.environment
}
