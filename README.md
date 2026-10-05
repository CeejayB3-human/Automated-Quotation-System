# Netpro AI Product Catalog & Quotation Generator

> An internal AI-powered sales tool that takes a customer's infrastructure requirements, searches the Netpro product catalog using RAG (Retrieval-Augmented Generation), and instantly produces a branded PDF quotation — all in seconds.

---

## Table of Contents

- [Solution Overview](#solution-overview)
- [Architecture](#architecture)
- [AWS Services Used](#aws-services-used)
- [Project Structure](#project-structure)
- [Prerequisites](#prerequisites)
- [Deployment Guide](#deployment-guide)
- [How to Use](#how-to-use)
- [Updating the Product Catalog](#updating-the-product-catalog)
- [API Reference](#api-reference)
- [Cost Estimate](#cost-estimate)
- [Troubleshooting](#troubleshooting)
- [Security Considerations](#security-considerations)

---

## Solution Overview

The Netpro Sales team receives customer requirements like:

> *"I need to cable a 3-floor office with 40 devices per floor. Include switches, patch panels, and Cat6 cabling."*

Previously, a sales engineer would manually search the catalog, calculate quantities, and write up a quotation in Word — taking 30–60 minutes per request.

**This solution automates that entire workflow:**

1. Sales rep types the requirement into a simple form or calls the API
2. The AI searches the real Netpro product catalog (not general knowledge)
3. Claude recommends the right products, quantities, and prices
4. A formal PDF quotation is generated and returned as a download link
5. Total time: **under 30 seconds**

---

## Architecture

```
Sales Rep
    │  POST /quotation  { "requirements": "..." }
    ▼
API Gateway (HTTP API)
    │
    ▼
Lambda: Orchestrator
    ├──► Bedrock Knowledge Base (RAG)
    │         └── OpenSearch Serverless (vector store)
    │                   ▲
    │              S3: Product Catalog
    │              (PDFs, spec sheets, pricing)
    │
    ├──► Amazon Bedrock + Claude 3.5 Sonnet
    │    (product recommendation + structured JSON)
    │
    └──► Lambda: PDF Generator
              └── S3: Output Bucket
                  (presigned URL returned to caller)
```

### Request Flow

```
Client → API Gateway → Orchestrator Lambda
                            │
                    ┌───────┴───────────────────┐
                    │                           │
              Bedrock KB Retrieve         (uses retrieved context)
              (RAG over catalog)                │
                    │                    Bedrock Claude
                    └──► Combined ──────► (structured JSON)
                                               │
                                     PDF Generator Lambda
                                               │
                                         S3 Output Bucket
                                               │
                                     Presigned URL ──► Client
```

---

## AWS Services Used

| Service | Purpose |
|---|---|
| **Amazon Bedrock Knowledge Bases** | RAG engine — indexes the product catalog and retrieves relevant chunks |
| **Amazon Bedrock (Claude 3.5 Sonnet)** | LLM — reads the retrieved context and generates structured product recommendations |
| **Amazon OpenSearch Serverless** | Vector store backing the Knowledge Base |
| **AWS Lambda (Python 3.12)** | Serverless compute for orchestration and PDF generation |
| **Amazon API Gateway (HTTP API v2)** | HTTPS endpoint for the sales team |
| **Amazon S3** | Stores the product catalog (input) and generated PDFs (output) |
| **AWS IAM** | Least-privilege roles for each service |
| **Amazon CloudWatch** | Logging and monitoring |
| **AWS X-Ray** | Distributed tracing (enabled on Lambda) |

---

## Project Structure

```
netpro-quotation-iac/
├── main.tf                          # Root module — wires everything together
├── variables.tf                     # Input variables
├── outputs.tf                       # Outputs after deploy (API URL, bucket names, etc.)
├── terraform.tfvars.example         # Example config — copy to terraform.tfvars
├── .gitignore
│
├── modules/
│   ├── s3/                          # Catalog bucket + output bucket
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   │
│   ├── iam/                         # IAM roles for Bedrock KB and Lambda
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   │
│   ├── bedrock/                     # Knowledge Base + OpenSearch Serverless
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   │
│   ├── lambda/                      # Orchestrator + PDF Generator Lambdas
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   │
│   └── api_gateway/                 # HTTP API Gateway
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
│
├── lambda_src/
│   ├── orchestrator/
│   │   └── handler.py               # RAG query → Claude → invoke PDF Lambda
│   └── pdf_generator/
│       ├── handler.py               # Render HTML → PDF → save to S3
│       └── requirements.txt
│
└── scripts/
    ├── build_lambda_layer.sh        # Build WeasyPrint Lambda layer with Docker
    └── test_api.sh                  # End-to-end API test
```

---

## Prerequisites

Before deploying, make sure you have:

1. **AWS CLI** configured (`aws configure`) with an account that has admin permissions
2. **Terraform** >= 1.5.0 installed ([install guide](https://developer.hashicorp.com/terraform/install))
3. **Docker** installed (needed to build the WeasyPrint Lambda layer)
4. **Amazon Bedrock model access** — you must manually request access to Claude models in the AWS Console:
   - Go to **Amazon Bedrock → Model access** in your AWS Console
   - Request access to: `Anthropic Claude 3.5 Sonnet` and `Amazon Titan Embeddings V2`
   - Access is typically granted within a few minutes

---

## Deployment Guide

### Step 1 — Clone and configure

```bash
git clone https://github.com/your-org/netpro-quotation-iac.git
cd netpro-quotation-iac

cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
```

### Step 2 — Build the WeasyPrint Lambda layer (for PDF output)

```bash
chmod +x scripts/build_lambda_layer.sh
./scripts/build_lambda_layer.sh
```

Copy the Layer ARN printed at the end and uncomment the `layers` block in `modules/lambda/main.tf`, replacing the placeholder ARN.

> **Skip this step** if you want to deploy quickly and test first — the PDF Lambda gracefully falls back to HTML output if the layer is missing.

### Step 3 — Deploy with Terraform

```bash
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

Terraform will print the key outputs at the end:

```
api_endpoint               = "https://abc123.execute-api.us-east-1.amazonaws.com/dev"
catalog_bucket_name        = "netpro-quotation-dev-catalog-a1b2c3d4"
output_bucket_name         = "netpro-quotation-dev-output-a1b2c3d4"
knowledge_base_id          = "KBXXXXXXXXXX"
sync_command               = "aws bedrock-agent start-ingestion-job ..."
```

### Step 4 — Upload your product catalog

Upload your PDFs, spec sheets, and pricing documents to the catalog S3 bucket:

```bash
# Upload all files in a local catalog folder
aws s3 sync ./your-catalog-folder/ s3://$(terraform output -raw catalog_bucket_name)/

# Or upload individual files
aws s3 cp netpro-products-2024.pdf s3://$(terraform output -raw catalog_bucket_name)/
aws s3 cp pricing-sheet.pdf s3://$(terraform output -raw catalog_bucket_name)/
aws s3 cp networking-specs.pdf s3://$(terraform output -raw catalog_bucket_name)/
```

**Supported file types:** PDF, TXT, HTML, DOCX, CSV, XLSX

### Step 5 — Sync the Knowledge Base

After uploading catalog files, trigger the RAG ingestion job:

```bash
# Copy and run the sync command from Terraform outputs
$(terraform output -raw sync_command)
```

Wait 2–5 minutes for ingestion to complete. Check status in the AWS Console under **Bedrock → Knowledge Bases**.

### Step 6 — Test it

```bash
chmod +x scripts/test_api.sh
./scripts/test_api.sh
```

Or test manually:

```bash
curl -X POST "$(terraform output -raw api_endpoint)/quotation" \
  -H "Content-Type: application/json" \
  -d '{
    "requirements": "3-floor office, 40 devices per floor, need switches, Cat6 cabling, and patch panels"
  }'
```

---

## How to Use

### API call from the sales tool

```bash
POST https://<api_endpoint>/quotation
Content-Type: application/json

{
  "requirements": "I need to cable a 3-floor office building with 40 devices per floor."
}
```

### Response

```json
{
  "quotation_id": "A1B2C3D4",
  "download_url": "https://s3.amazonaws.com/.../Netpro-Quotation-A1B2C3D4.pdf?...",
  "expires_in": "1 hour",
  "recommendations": {
    "customer_summary": "3-floor office cabling for 120 devices",
    "recommended_products": [
      {
        "product_name": "Cisco Catalyst 2960X-48TS-L Switch",
        "sku": "WS-C2960X-48TS-L",
        "description": "48-port GigE switch, LAN Base",
        "quantity": 3,
        "unit_price_usd": 2850.00,
        "subtotal_usd": 8550.00
      }
    ],
    "total_usd": 18420.00,
    "notes": "Quantities calculated for 40 devices per floor with 20% headroom."
  }
}
```

Open the `download_url` to get the PDF. The link expires in 1 hour.

---

## Updating the Product Catalog

Whenever Netpro updates their products or pricing:

```bash
# 1. Upload new/updated files
aws s3 cp updated-catalog-2025.pdf s3://$(terraform output -raw catalog_bucket_name)/

# 2. Re-sync the Knowledge Base
$(terraform output -raw sync_command)
```

The Knowledge Base will re-chunk and re-embed the new files. Old embeddings for unchanged files are not re-processed.

---

## API Reference

| Endpoint | Method | Description |
|---|---|---|
| `/quotation` | `POST` | Generate a product recommendation and PDF quotation |
| `/health` | `GET` | Health check |

### POST /quotation — Request body

| Field | Type | Required | Description |
|---|---|---|---|
| `requirements` | string | Yes | Customer's infrastructure requirements in plain text |

### POST /quotation — Response

| Field | Type | Description |
|---|---|---|
| `quotation_id` | string | Unique reference number |
| `download_url` | string | Presigned S3 URL for the PDF (expires in 1 hour) |
| `recommendations` | object | Structured product recommendations from Claude |
| `expires_in` | string | URL expiry window |

---

## Cost Estimate

For typical internal sales team usage (~100 quotations/month):

| Service | Estimated Monthly Cost |
|---|---|
| Amazon Bedrock (Claude 3.5 Sonnet — ~2K tokens/request) | ~$3–5 |
| Amazon Bedrock Titan Embeddings (one-time ingestion) | ~$0.50 |
| OpenSearch Serverless (1 OCU minimum) | ~$175 |
| Lambda (100 invocations × 10s) | < $1 |
| S3 (catalog storage + generated PDFs) | ~$1 |
| API Gateway | < $1 |
| **Total** | **~$180–185/month** |

> The bulk of the cost is the OpenSearch Serverless collection (~$175/month for 1 OCU). For lower-volume use cases, consider Amazon Bedrock Knowledge Bases with a different vector store like Amazon Aurora PostgreSQL pgvector, which can be cheaper at low volumes.

---

## Troubleshooting

**"Claude returned non-JSON response"**
- This means Claude's recommendation didn't parse correctly. Check the orchestrator Lambda logs in CloudWatch. Usually caused by a malformed prompt or the model returning explanatory text before the JSON.

**"PDF is actually HTML"**
- The WeasyPrint Lambda layer is missing. Run `scripts/build_lambda_layer.sh` and add the ARN to the Lambda configuration.

**Empty product recommendations**
- The Knowledge Base may not have been synced yet. Run the sync command from Terraform outputs and wait 2–5 minutes.

**Lambda timeout**
- Increase `lambda_timeout` in `terraform.tfvars` (default is 120s). PDF generation can be slow on first cold start.

**Bedrock access denied**
- You need to manually request model access in the AWS Console under **Bedrock → Model access**.

---

## Security Considerations

- All S3 buckets have public access blocked and server-side encryption enabled.
- IAM roles follow the principle of least privilege — each service only has the permissions it needs.
- API Gateway has rate limiting enabled (20 req/s burst of 50).
- Generated PDF presigned URLs expire after 1 hour.
- For production, set `allowed_cidr_blocks` in `terraform.tfvars` to restrict API access to your office IP.
- Consider enabling AWS WAF by setting `enable_waf = true` in `terraform.tfvars`.
- Terraform state contains sensitive resource IDs — use the S3 remote backend (uncomment the backend block in `main.tf`) for team deployments.

---

## Destroying the Stack

```bash
terraform destroy
```

> This will delete all resources including S3 buckets and their contents (in non-prod environments). Make sure to back up any important catalog files before destroying.

---

## Author

Deployed as part of the **AWS AI Competency** implementation by the Netpro team.

Built with: Terraform · Amazon Bedrock · Claude 3.5 Sonnet · AWS Lambda · Python 3.12
