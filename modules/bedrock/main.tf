###############################################################################
# Bedrock Module — Knowledge Base + OpenSearch Serverless
###############################################################################

# ── OpenSearch Serverless Collection ──────────────────────────────────────
resource "aws_opensearchserverless_security_policy" "encryption" {
  name        = "${replace(var.name_prefix, "-", "")}enc"
  type        = "encryption"
  description = "Encryption policy for Netpro vector store"

  policy = jsonencode({
    Rules = [
      {
        ResourceType = "collection"
        Resource     = ["collection/${replace(var.name_prefix, "-", "")}-vs"]
      }
    ]
    AWSOwnedKey = true
  })
}

resource "aws_opensearchserverless_security_policy" "network" {
  name        = "${replace(var.name_prefix, "-", "")}net"
  type        = "network"
  description = "Network policy for Netpro vector store"

  policy = jsonencode([
    {
      Rules = [
        {
          ResourceType = "collection"
          Resource     = ["collection/${replace(var.name_prefix, "-", "")}-vs"]
        },
        {
          ResourceType = "dashboard"
          Resource     = ["collection/${replace(var.name_prefix, "-", "")}-vs"]
        }
      ]
      AllowFromPublic = true
    }
  ])
}

resource "aws_opensearchserverless_access_policy" "data" {
  name        = "${replace(var.name_prefix, "-", "")}data"
  type        = "data"
  description = "Data access policy for Bedrock Knowledge Base"

  policy = jsonencode([
    {
      Rules = [
        {
          ResourceType = "index"
          Resource     = ["index/${replace(var.name_prefix, "-", "")}-vs/*"]
          Permission   = [
            "aoss:CreateIndex",
            "aoss:DeleteIndex",
            "aoss:UpdateIndex",
            "aoss:DescribeIndex",
            "aoss:ReadDocument",
            "aoss:WriteDocument"
          ]
        },
        {
          ResourceType = "collection"
          Resource     = ["collection/${replace(var.name_prefix, "-", "")}-vs"]
          Permission   = [
            "aoss:CreateCollectionItems",
            "aoss:DeleteCollectionItems",
            "aoss:UpdateCollectionItems",
            "aoss:DescribeCollectionItems"
          ]
        }
      ]
      Principal = [
        var.bedrock_kb_role_arn,
        "arn:aws:iam::${var.aws_account_id}:root"
      ]
    }
  ])
}

resource "aws_opensearchserverless_collection" "vector_store" {
  name        = "${replace(var.name_prefix, "-", "")}-vs"
  type        = "VECTORSEARCH"
  description = "Vector store for Netpro product catalog embeddings"

  depends_on = [
    aws_opensearchserverless_security_policy.encryption,
    aws_opensearchserverless_security_policy.network,
    aws_opensearchserverless_access_policy.data
  ]

  tags = {
    Name = "${var.name_prefix}-vector-store"
  }
}

# ── Bedrock Knowledge Base ─────────────────────────────────────────────────
resource "aws_bedrockagent_knowledge_base" "catalog" {
  name        = "${var.name_prefix}-kb"
  description = "RAG knowledge base over Netpro product catalog, spec sheets, and pricing"
  role_arn    = var.bedrock_kb_role_arn

  knowledge_base_configuration {
    type = "VECTOR"
    vector_knowledge_base_configuration {
      embedding_model_arn = "arn:aws:bedrock:${var.aws_region}::foundation-model/amazon.titan-embed-text-v2:0"
    }
  }

  storage_configuration {
    type = "OPENSEARCH_SERVERLESS"
    opensearch_serverless_configuration {
      collection_arn    = aws_opensearchserverless_collection.vector_store.arn
      vector_index_name = "netpro-catalog-index"
      field_mapping {
        vector_field   = "embedding"
        text_field     = "text"
        metadata_field = "metadata"
      }
    }
  }

  tags = {
    Name = "${var.name_prefix}-knowledge-base"
  }

  depends_on = [aws_opensearchserverless_collection.vector_store]
}

# ── Knowledge Base Data Source (S3) ───────────────────────────────────────
resource "aws_bedrockagent_data_source" "catalog_s3" {
  knowledge_base_id = aws_bedrockagent_knowledge_base.catalog.id
  name              = "${var.name_prefix}-catalog-datasource"
  description       = "Product catalog PDFs and spec sheets from S3"

  data_source_configuration {
    type = "S3"
    s3_configuration {
      bucket_arn = var.catalog_bucket_arn
      # Optionally restrict to a subfolder:
      # inclusion_prefixes = ["catalogs/", "specs/", "pricing/"]
    }
  }

  vector_ingestion_configuration {
    chunking_configuration {
      chunking_strategy = "FIXED_SIZE"
      fixed_size_chunking_configuration {
        max_tokens         = 512
        overlap_percentage = 10
      }
    }
  }
}
