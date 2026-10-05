#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Build the WeasyPrint Lambda Layer using Docker (matches Lambda runtime)
# Run this script once, then publish the layer and paste the ARN into Lambda.
#
# Prerequisites:
#   - Docker installed and running
#   - AWS CLI configured
#   - Variables set below
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

LAYER_NAME="netpro-weasyprint-layer"
PYTHON_VERSION="3.12"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo ">>> Building WeasyPrint Lambda layer for Python ${PYTHON_VERSION}..."

mkdir -p ./layer/python

docker run --rm \
  -v "$(pwd)/layer:/layer" \
  "public.ecr.aws/lambda/python:${PYTHON_VERSION}" \
  bash -c "pip install weasyprint==60.2 -t /layer/python --no-cache-dir"

echo ">>> Zipping layer..."
cd layer && zip -r9 ../weasyprint_layer.zip . && cd ..

echo ">>> Publishing layer to AWS Lambda..."
LAYER_ARN=$(aws lambda publish-layer-version \
  --layer-name "${LAYER_NAME}" \
  --description "WeasyPrint for PDF generation" \
  --zip-file fileb://weasyprint_layer.zip \
  --compatible-runtimes "python${PYTHON_VERSION}" \
  --region "${REGION}" \
  --query 'LayerVersionArn' \
  --output text)

echo ""
echo "✅ Layer published successfully!"
echo "   ARN: ${LAYER_ARN}"
echo ""
echo "Add this ARN to your terraform.tfvars:"
echo "  pdf_layer_arn = \"${LAYER_ARN}\""

rm -f weasyprint_layer.zip
