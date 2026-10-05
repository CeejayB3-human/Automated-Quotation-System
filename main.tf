###############################################################################
# AI Product Catalog & Quotation Generator
# Netpro Sales Tool — Main Terraform Configuration
###############################################################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }

  # Uncomment and configure for remote state (recommended for team use)
  # backend "s3" {
  #   bucket         = "netpro-terraform-state"
  #   key            = "quotation-generator/terraform.tfstate"
  #   region         = "us-east-1"
  #   encrypt        = true
  #   dynamodb_table = "netpro-terraform-locks"
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "NetproQuotationGenerator"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Owner       = var.owner_tag
    }
  }
}

###############################################################################
# Random suffix to ensure globally unique resource names
###############################################################################
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  name_prefix = "${var.project_name}-${var.environment}"
  unique_id   = random_id.suffix.hex
}

###############################################################################
# S3 Buckets
###############################################################################
module "s3" {
  source      = "./modules/s3"
  name_prefix = local.name_prefix
  unique_id   = local.unique_id
  environment = var.environment
}

###############################################################################
# IAM Roles & Policies
###############################################################################
module "iam" {
  source              = "./modules/iam"
  name_prefix         = local.name_prefix
  catalog_bucket_arn  = module.s3.catalog_bucket_arn
  output_bucket_arn   = module.s3.output_bucket_arn
  knowledge_base_id   = module.bedrock.knowledge_base_id
  aws_region          = var.aws_region
  aws_account_id      = data.aws_caller_identity.current.account_id
}

###############################################################################
# Amazon Bedrock Knowledge Base
###############################################################################
module "bedrock" {
  source              = "./modules/bedrock"
  name_prefix         = local.name_prefix
  unique_id           = local.unique_id
  catalog_bucket_arn  = module.s3.catalog_bucket_arn
  catalog_bucket_name = module.s3.catalog_bucket_name
  bedrock_kb_role_arn = module.iam.bedrock_kb_role_arn
  aws_region          = var.aws_region
  aws_account_id      = data.aws_caller_identity.current.account_id
  environment         = var.environment
}

###############################################################################
# Lambda Functions
###############################################################################
module "lambda" {
  source                    = "./modules/lambda"
  name_prefix               = local.name_prefix
  lambda_role_arn           = module.iam.lambda_role_arn
  knowledge_base_id         = module.bedrock.knowledge_base_id
  output_bucket_name        = module.s3.output_bucket_name
  claude_model_id           = var.claude_model_id
  aws_region                = var.aws_region
  environment               = var.environment
  lambda_timeout            = var.lambda_timeout
  lambda_memory             = var.lambda_memory
}

###############################################################################
# API Gateway
###############################################################################
module "api_gateway" {
  source                         = "./modules/api_gateway"
  name_prefix                    = local.name_prefix
  environment                    = var.environment
  orchestrator_lambda_invoke_arn = module.lambda.orchestrator_invoke_arn
  orchestrator_lambda_name       = module.lambda.orchestrator_name
}

###############################################################################
# Data Sources
###############################################################################
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
