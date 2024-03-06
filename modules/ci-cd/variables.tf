variable "region" {
  description = "AWS region used to provision resources (i.e. us-east-1/us-west-1)"
  type        = string
}

variable "environment" {
  description = "Environment used for creating resources (will be appended to various resources)"
  type        = string
}

variable "s3_bucket_name_webapp" {
  description = "The S3 bucket name for the webapp"
  type        = string
}

variable "s3_bucket_name_chat" {
  description = "The S3 bucket name for the chat"
  type        = string
}

variable "secretsmanager_secret_id_webapp" {
  description = "The Secrets Manager secret ID for the webapp"
  type        = string
}

variable "secretsmanager_secret_id_chat" {
  description = "The Secrets Manager secret ID for the chat"
  type        = string
}

variable "secretsmanager_secret_id_server" {
  description = "The Secrets Manager secret ID for the server"
  type        = string
}

variable "secretsmanager_secret_id_registry" {
  description = "The Secrets Manager secret ID for the container registry"
  type        = string
}

variable "ecr_repository_url_webapp" {
  description = "The ECR repository URL for the webapp"
  type        = string
}

variable "ecr_repository_url_chat" {
  description = "The ECR repository URL for the chat"
  type        = string
}

variable "ecr_repository_url_server" {
  description = "The ECR repository URL for the server"
  type        = string
}

variable "ecr_repository_image_tag" {
  description = "The ECR repository image tag"
  type        = string
  default     = "latest"
}

variable "ecs_cluster_name" {
  description = "The ECS cluster name"
  type        = string
}

variable "ecs_service_name_server" {
  description = "The ECS service name for the server"
  type        = string
}

variable "sns_topic_alerts_arn" {
  description = "The SNS topic ARN to send alerts to"
  type        = string
}

variable "statistic_period" {
  description = "The number of seconds that make each statistic period."
  type        = number
  default     = 60
}

variable "container_registry_repository_chat" {
  description = "The GitHub Container registry repository URL"
  type        = string
  default     = "ghcr.io/addvaluemachine/avm-chat"
}

variable "container_registry_repository_webapp" {
  description = "The GitHub Container registry repository URL"
  type        = string
  default     = "ghcr.io/addvaluemachine/avm-webapp"
}

variable "container_registry_repository_server" {
  description = "The GitHub Container registry repository URL"
  type        = string
  default     = "ghcr.io/addvaluemachine/avm-server"
}
