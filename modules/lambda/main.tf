###############################################################################
# Lambda Module — Orchestrator + PDF Generator
###############################################################################

# ── Package Lambda source code ────────────────────────────────────────────
data "archive_file" "orchestrator" {
  type        = "zip"
  source_dir  = "${path.root}/lambda_src/orchestrator"
  output_path = "${path.module}/orchestrator.zip"
}

data "archive_file" "pdf_generator" {
  type        = "zip"
  source_dir  = "${path.root}/lambda_src/pdf_generator"
  output_path = "${path.module}/pdf_generator.zip"
}

# ── CloudWatch Log Groups (with retention) ────────────────────────────────
resource "aws_cloudwatch_log_group" "orchestrator" {
  name              = "/aws/lambda/${var.name_prefix}-orchestrator"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_group" "pdf_generator" {
  name              = "/aws/lambda/${var.name_prefix}-pdf-generator"
  retention_in_days = 30
}

# ── Orchestrator Lambda ───────────────────────────────────────────────────
resource "aws_lambda_function" "orchestrator" {
  function_name    = "${var.name_prefix}-orchestrator"
  description      = "Receives customer requirements, queries Bedrock KB, calls Claude, triggers PDF generation"
  role             = var.lambda_role_arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  timeout          = var.lambda_timeout
  memory_size      = var.lambda_memory
  filename         = data.archive_file.orchestrator.output_path
  source_code_hash = data.archive_file.orchestrator.output_base64sha256

  environment {
    variables = {
      KNOWLEDGE_BASE_ID    = var.knowledge_base_id
      OUTPUT_BUCKET        = var.output_bucket_name
      CLAUDE_MODEL_ID      = var.claude_model_id
      PDF_LAMBDA_NAME      = "${var.name_prefix}-pdf-generator"
      AWS_REGION_NAME      = var.aws_region
      LOG_LEVEL            = var.environment == "prod" ? "WARNING" : "DEBUG"
    }
  }

  tracing_config {
    mode = "Active"
  }

  depends_on = [aws_cloudwatch_log_group.orchestrator]

  tags = {
    Name = "${var.name_prefix}-orchestrator"
  }
}

# ── PDF Generator Lambda ──────────────────────────────────────────────────
resource "aws_lambda_function" "pdf_generator" {
  function_name    = "${var.name_prefix}-pdf-generator"
  description      = "Renders Claude recommendations into a branded PDF quotation and saves to S3"
  role             = var.lambda_role_arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  timeout          = var.lambda_timeout
  memory_size      = var.lambda_memory
  filename         = data.archive_file.pdf_generator.output_path
  source_code_hash = data.archive_file.pdf_generator.output_base64sha256

  environment {
    variables = {
      OUTPUT_BUCKET = var.output_bucket_name
      AWS_REGION_NAME = var.aws_region
      LOG_LEVEL     = var.environment == "prod" ? "WARNING" : "DEBUG"
    }
  }

  tracing_config {
    mode = "Active"
  }

  layers = [
    # AWS provides a public layer with common Python libs.
    # For WeasyPrint/ReportLab, build and publish your own layer:
    # See: scripts/build_lambda_layer.sh
    # aws_lambda_layer_version.pdf_libs.arn
  ]

  depends_on = [aws_cloudwatch_log_group.pdf_generator]

  tags = {
    Name = "${var.name_prefix}-pdf-generator"
  }
}

# ── Lambda URL for local testing (dev only) ───────────────────────────────
resource "aws_lambda_function_url" "orchestrator_dev" {
  count              = var.environment == "dev" ? 1 : 0
  function_name      = aws_lambda_function.orchestrator.function_name
  authorization_type = "NONE"

  cors {
    allow_credentials = false
    allow_origins     = ["*"]
    allow_methods     = ["POST"]
    allow_headers     = ["Content-Type"]
    max_age           = 86400
  }
}
