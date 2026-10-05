###############################################################################
# Input Variables
###############################################################################

variable "aws_region" {
  description = "AWS region to deploy resources. Bedrock is available in us-east-1 and us-west-2."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = contains(["us-east-1", "us-west-2", "eu-west-1", "ap-southeast-1"], var.aws_region)
    error_message = "Region must be one where Amazon Bedrock with Claude is available."
  }
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "project_name" {
  description = "Short project identifier used in resource names."
  type        = string
  default     = "netpro-quotation"
}

variable "owner_tag" {
  description = "Team or individual responsible for this deployment (used in tags)."
  type        = string
  default     = "netpro-sales-team"
}

variable "claude_model_id" {
  description = "Amazon Bedrock model ID for Claude. Use Sonnet for best balance of speed/quality."
  type        = string
  default     = "anthropic.claude-3-5-sonnet-20241022-v2:0"
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds. PDF generation can take up to 60s."
  type        = number
  default     = 120

  validation {
    condition     = var.lambda_timeout >= 30 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 30 and 900 seconds."
  }
}

variable "lambda_memory" {
  description = "Lambda memory in MB. Higher memory = faster PDF generation."
  type        = number
  default     = 512

  validation {
    condition     = contains([256, 512, 1024, 2048], var.lambda_memory)
    error_message = "Lambda memory must be 256, 512, 1024, or 2048 MB."
  }
}

variable "enable_waf" {
  description = "Whether to attach AWS WAF to the API Gateway (recommended for production)."
  type        = bool
  default     = false
}

variable "allowed_cidr_blocks" {
  description = "List of CIDR blocks allowed to access the API. Leave empty for public access."
  type        = list(string)
  default     = []
}
