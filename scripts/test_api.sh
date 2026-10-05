#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Quick end-to-end test of the Quotation Generator API
# Usage:  ./scripts/test_api.sh <API_ENDPOINT>
# Example: ./scripts/test_api.sh https://abc123.execute-api.us-east-1.amazonaws.com/dev
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

API_ENDPOINT="${1:-}"

if [[ -z "$API_ENDPOINT" ]]; then
  API_ENDPOINT=$(terraform output -raw api_endpoint 2>/dev/null || echo "")
fi

if [[ -z "$API_ENDPOINT" ]]; then
  echo "ERROR: Provide the API endpoint as an argument or run from the Terraform directory."
  exit 1
fi

echo ">>> Testing health check..."
curl -sf "${API_ENDPOINT}/health" | jq .

echo ""
echo ">>> Generating a test quotation..."
curl -sf -X POST "${API_ENDPOINT}/quotation" \
  -H "Content-Type: application/json" \
  -d '{
    "requirements": "I need to cable a 3-floor office building with 40 devices per floor. Include switches, patch panels, Cat6 cabling, and a rack for each floor."
  }' | jq '{
    quotation_id: .quotation_id,
    download_url: .download_url,
    total: .recommendations.total_usd,
    product_count: (.recommendations.recommended_products | length)
  }'

echo ""
echo "✅ Test complete. Copy the download_url to get your PDF."
