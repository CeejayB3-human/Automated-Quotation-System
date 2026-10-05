output "knowledge_base_id"      { value = aws_bedrockagent_knowledge_base.catalog.id }
output "knowledge_base_arn"     { value = aws_bedrockagent_knowledge_base.catalog.arn }
output "data_source_id"         { value = aws_bedrockagent_data_source.catalog_s3.data_source_id }
output "opensearch_endpoint"    { value = aws_opensearchserverless_collection.vector_store.collection_endpoint }
