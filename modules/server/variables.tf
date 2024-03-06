variable "region" {
  description = "AWS region used to provision resources (i.e. us-east-1/us-west-1)"
  type        = string
}

variable "environment" {
  description = "Environment used for creating resources (will be appended to various resources)"
  type        = string
}

variable "domain_name" {
  description = "The domain name"
  type        = string
}

# variable "certificate_arn" {
#   description = "The domain certificate ARN"
#   type        = string
# }

variable "vpc_id" {
  description = "The VPC ID"
  type        = string
}

variable "ecs_cluster_name" {
  description = "The ECS cluster name"
  type        = string
}

variable "load_balancer_security_group_id" {
  description = "The load balancer security group ID"
  type        = string
}

variable "autoscaling_min_instances" {
  description = "The minimum number of instances that should be running"
  type        = number
  default     = 1
}

variable "autoscaling_max_instances" {
  description = "The maximum number of instances that should be running"
  type        = number
  default     = 4
}

variable "autoscaling_cpu_low_threshold" {
  description = "Threshold for min CPU usage"
  type        = number
  default     = 20
}

variable "autoscaling_cpu_high_threshold" {
  description = "Threshold for max CPU usage"
  type        = number
  default     = 80
}

variable "rds_cluster_identifier" {
  description = "The RDS cluster ID"
  type        = string
}

variable "rds_master_password" {
  type        = string
  description = "The master password for the RDS instance"
}

variable "ecr_image_tag" {
  description = "The ECR image tag"
  type        = string
  default     = "latest"
}

variable "firebase_project_id" {
  description = "The firebase project id value from Firebase organisation"
  type        = string
}

variable "firebase_private_key" {
  description = "The firebase prvate key value from Firebase organisation"
  type        = string
}

variable "firebase_client_email" {
  description = "The firebase client email value from Firebase organisation"
  type        = string
}