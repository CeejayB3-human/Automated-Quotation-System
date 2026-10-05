###############################################################################
# S3 Module — Catalog bucket + Output bucket
###############################################################################

# ── Product Catalog Bucket ─────────────────────────────────────────────────
resource "aws_s3_bucket" "catalog" {
  bucket        = "${var.name_prefix}-catalog-${var.unique_id}"
  force_destroy = var.environment != "prod"

  tags = {
    Name    = "${var.name_prefix}-catalog"
    Purpose = "Stores product catalog PDFs and spec sheets for Bedrock RAG ingestion"
  }
}

resource "aws_s3_bucket_versioning" "catalog" {
  bucket = aws_s3_bucket.catalog.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "catalog" {
  bucket = aws_s3_bucket.catalog.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "catalog" {
  bucket                  = aws_s3_bucket.catalog.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle: move old catalog versions to Glacier after 90 days
resource "aws_s3_bucket_lifecycle_configuration" "catalog" {
  bucket = aws_s3_bucket.catalog.id

  rule {
    id     = "archive-old-versions"
    status = "Enabled"

    noncurrent_version_transition {
      noncurrent_days = 90
      storage_class   = "GLACIER"
    }
  }
}

# ── Output Bucket (Generated PDFs) ────────────────────────────────────────
resource "aws_s3_bucket" "output" {
  bucket        = "${var.name_prefix}-output-${var.unique_id}"
  force_destroy = var.environment != "prod"

  tags = {
    Name    = "${var.name_prefix}-output"
    Purpose = "Stores AI-generated quotation PDFs"
  }
}

resource "aws_s3_bucket_versioning" "output" {
  bucket = aws_s3_bucket.output.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "output" {
  bucket = aws_s3_bucket.output.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "output" {
  bucket                  = aws_s3_bucket.output.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Automatically delete quotation PDFs after 365 days
resource "aws_s3_bucket_lifecycle_configuration" "output" {
  bucket = aws_s3_bucket.output.id

  rule {
    id     = "expire-old-quotations"
    status = "Enabled"

    expiration {
      days = 365
    }
  }
}

# CORS for the output bucket — allows frontend to fetch presigned URLs
resource "aws_s3_bucket_cors_configuration" "output" {
  bucket = aws_s3_bucket.output.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "HEAD"]
    allowed_origins = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3600
  }
}
