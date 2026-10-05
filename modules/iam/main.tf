###############################################################################
# IAM Module — Roles and Policies
###############################################################################

# ── Bedrock Knowledge Base Role ───────────────────────────────────────────
data "aws_iam_policy_document" "bedrock_kb_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["bedrock.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.aws_account_id]
    }
  }
}

resource "aws_iam_role" "bedrock_kb" {
  name               = "${var.name_prefix}-bedrock-kb-role"
  assume_role_policy = data.aws_iam_policy_document.bedrock_kb_assume.json
}

data "aws_iam_policy_document" "bedrock_kb_policy" {
  # Read catalog files from S3
  statement {
    sid     = "ReadCatalogBucket"
    actions = ["s3:GetObject", "s3:ListBucket"]
    resources = [
      var.catalog_bucket_arn,
      "${var.catalog_bucket_arn}/*"
    ]
  }

  # Access Bedrock foundation models for embedding
  statement {
    sid     = "InvokeEmbeddingModel"
    actions = ["bedrock:InvokeModel"]
    resources = [
      "arn:aws:bedrock:${var.aws_region}::foundation-model/amazon.titan-embed-text-v2:0"
    ]
  }

  # OpenSearch Serverless — write vectors
  statement {
    sid     = "OpenSearchServerlessAccess"
    actions = ["aoss:APIAccessAll"]
    resources = [
      "arn:aws:aoss:${var.aws_region}:${var.aws_account_id}:collection/*"
    ]
  }
}

resource "aws_iam_role_policy" "bedrock_kb" {
  name   = "${var.name_prefix}-bedrock-kb-policy"
  role   = aws_iam_role.bedrock_kb.id
  policy = data.aws_iam_policy_document.bedrock_kb_policy.json
}

# ── Lambda Execution Role ─────────────────────────────────────────────────
data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name               = "${var.name_prefix}-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

data "aws_iam_policy_document" "lambda_policy" {
  # CloudWatch Logs
  statement {
    sid     = "CloudWatchLogs"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["arn:aws:logs:${var.aws_region}:${var.aws_account_id}:*"]
  }

  # Bedrock: invoke Claude and query Knowledge Base
  statement {
    sid     = "BedrockInvoke"
    actions = [
      "bedrock:InvokeModel",
      "bedrock:InvokeModelWithResponseStream"
    ]
    resources = [
      "arn:aws:bedrock:${var.aws_region}::foundation-model/anthropic.claude-3-5-sonnet-20241022-v2:0",
      "arn:aws:bedrock:${var.aws_region}::foundation-model/anthropic.claude-3-sonnet-20240229-v1:0",
      "arn:aws:bedrock:${var.aws_region}::foundation-model/anthropic.claude-3-haiku-20240307-v1:0"
    ]
  }

  statement {
    sid     = "BedrockKBRetrieve"
    actions = [
      "bedrock:Retrieve",
      "bedrock:RetrieveAndGenerate"
    ]
    resources = [
      "arn:aws:bedrock:${var.aws_region}:${var.aws_account_id}:knowledge-base/${var.knowledge_base_id}"
    ]
  }

  # S3: write generated PDFs to output bucket
  statement {
    sid     = "WriteOutputBucket"
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:DeleteObject"
    ]
    resources = [
      "${var.output_bucket_arn}/*"
    ]
  }

  # Lambda: orchestrator can invoke the PDF generator
  statement {
    sid     = "InvokePdfLambda"
    actions = ["lambda:InvokeFunction"]
    resources = [
      "arn:aws:lambda:${var.aws_region}:${var.aws_account_id}:function:${var.name_prefix}-pdf-generator"
    ]
  }
}

resource "aws_iam_role_policy" "lambda" {
  name   = "${var.name_prefix}-lambda-policy"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda_policy.json
}
