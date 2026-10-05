"""
Orchestrator Lambda
-------------------
1. Receives customer requirements from API Gateway
2. Queries Bedrock Knowledge Base (RAG over product catalog)
3. Passes retrieved context + requirements to Claude
4. Parses structured product recommendations
5. Invokes the PDF Generator Lambda
6. Returns a presigned S3 URL to download the quotation
"""

import json
import logging
import os
import uuid
from datetime import datetime

import boto3

logger = logging.getLogger()
logger.setLevel(os.environ.get("LOG_LEVEL", "INFO"))

KNOWLEDGE_BASE_ID = os.environ["KNOWLEDGE_BASE_ID"]
CLAUDE_MODEL_ID   = os.environ["CLAUDE_MODEL_ID"]
PDF_LAMBDA_NAME   = os.environ["PDF_LAMBDA_NAME"]
OUTPUT_BUCKET     = os.environ["OUTPUT_BUCKET"]
AWS_REGION        = os.environ["AWS_REGION_NAME"]

bedrock_agent = boto3.client("bedrock-agent-runtime", region_name=AWS_REGION)
bedrock       = boto3.client("bedrock-runtime", region_name=AWS_REGION)
lambda_client = boto3.client("lambda", region_name=AWS_REGION)
s3_client     = boto3.client("s3", region_name=AWS_REGION)


# ── Helpers ──────────────────────────────────────────────────────────────

def retrieve_catalog_context(query: str, num_results: int = 10) -> str:
    """Query the Bedrock Knowledge Base and return retrieved text chunks."""
    response = bedrock_agent.retrieve(
        knowledgeBaseId=KNOWLEDGE_BASE_ID,
        retrievalQuery={"text": query},
        retrievalConfiguration={
            "vectorSearchConfiguration": {"numberOfResults": num_results}
        },
    )
    chunks = [r["content"]["text"] for r in response.get("retrievalResults", [])]
    return "\n\n---\n\n".join(chunks)


def build_prompt(requirements: str, catalog_context: str) -> str:
    return f"""You are an expert network infrastructure sales engineer for Netpro.
A customer has the following requirements:

<customer_requirements>
{requirements}
</customer_requirements>

Below are the relevant product excerpts from the Netpro catalog:

<catalog_context>
{catalog_context}
</catalog_context>

Based ONLY on the products listed in the catalog context above, recommend the right
products, quantities and prices to fulfil the customer's requirements.

Respond with a single JSON object (no markdown fences, no extra text) in this exact format:
{{
  "customer_summary": "One-sentence summary of the customer's project",
  "recommended_products": [
    {{
      "product_name": "...",
      "sku": "...",
      "description": "...",
      "quantity": 0,
      "unit_price_usd": 0.00,
      "subtotal_usd": 0.00
    }}
  ],
  "total_usd": 0.00,
  "notes": "Any important notes about the recommendation"
}}

Rules:
- Only recommend products that appear in the catalog context.
- If a required product is not in the catalog, mention it in the notes field.
- Calculate quantities based on the customer's requirements.
- Do not invent SKUs or prices.
"""


def invoke_claude(prompt: str) -> dict:
    """Call Claude via Bedrock and parse the JSON response."""
    body = {
        "anthropic_version": "bedrock-2023-05-31",
        "max_tokens": 2048,
        "messages": [{"role": "user", "content": prompt}],
    }
    response = bedrock.invoke_model(
        modelId=CLAUDE_MODEL_ID,
        body=json.dumps(body),
        contentType="application/json",
        accept="application/json",
    )
    result_text = json.loads(response["body"].read())["content"][0]["text"]
    return json.loads(result_text)


def generate_presigned_url(bucket: str, key: str, expiry: int = 3600) -> str:
    return s3_client.generate_presigned_url(
        "get_object",
        Params={"Bucket": bucket, "Key": key},
        ExpiresIn=expiry,
    )


# ── Main handler ─────────────────────────────────────────────────────────

def lambda_handler(event, context):
    # Health check
    if event.get("requestContext", {}).get("http", {}).get("method") == "GET":
        return {"statusCode": 200, "body": json.dumps({"status": "ok"})}

    try:
        body = json.loads(event.get("body", "{}"))
        requirements = body.get("requirements", "").strip()

        if not requirements:
            return {
                "statusCode": 400,
                "body": json.dumps({"error": "requirements field is required"}),
            }

        quotation_id = str(uuid.uuid4())[:8].upper()
        logger.info(f"[{quotation_id}] Processing: {requirements[:120]}")

        # Step 1 — RAG: retrieve relevant catalog entries
        catalog_context = retrieve_catalog_context(requirements)
        logger.debug(f"[{quotation_id}] Retrieved {len(catalog_context)} chars of context")

        # Step 2 — Ask Claude to recommend products
        prompt       = build_prompt(requirements, catalog_context)
        structured   = invoke_claude(prompt)
        logger.info(f"[{quotation_id}] Claude recommended {len(structured.get('recommended_products', []))} products")

        # Step 3 — Invoke PDF generator Lambda
        pdf_payload = {
            "quotation_id": quotation_id,
            "requirements":  requirements,
            "recommendations": structured,
            "generated_at": datetime.utcnow().isoformat() + "Z",
        }
        pdf_response = lambda_client.invoke(
            FunctionName=PDF_LAMBDA_NAME,
            InvocationType="RequestResponse",
            Payload=json.dumps(pdf_payload),
        )
        pdf_result = json.loads(pdf_response["Payload"].read())
        s3_key = pdf_result["s3_key"]

        # Step 4 — Generate presigned download URL (valid 1 hour)
        download_url = generate_presigned_url(OUTPUT_BUCKET, s3_key)

        return {
            "statusCode": 200,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({
                "quotation_id":    quotation_id,
                "download_url":    download_url,
                "recommendations": structured,
                "expires_in":      "1 hour",
            }),
        }

    except json.JSONDecodeError as e:
        logger.error(f"Claude returned non-JSON response: {e}")
        return {"statusCode": 500, "body": json.dumps({"error": "AI response parsing failed"})}
    except Exception as e:
        logger.exception(f"Unhandled error: {e}")
        return {"statusCode": 500, "body": json.dumps({"error": "Internal server error"})}
