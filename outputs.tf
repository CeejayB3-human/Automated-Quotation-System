###############################################################################
# Outputs — printed after terraform apply
###############################################################################

output "api_endpoint" {
  description = "The HTTPS endpoint sales reps hit to generate a quotation."
  value       = module.api_gateway.api_endpoint
}

output "catalog_bucket_name" {
  description = "Upload your product catalog PDFs and spec sheets here."
  value       = module.s3.catalog_bucket_name
}

output "output_bucket_name" {
  description = "Generated quotation PDFs are stored here."
  value       = module.s3.output_bucket_name
}

output "knowledge_base_id" {
  description = "Bedrock Knowledge Base ID — needed to manually trigger re-sync after catalog updates."
  value       = module.bedrock.knowledge_base_id
}

output "knowledge_base_data_source_id" {
  description = "Bedrock Knowledge Base Data Source ID — used with the sync command."
  value       = module.bedrock.data_source_id
}

output "orchestrator_lambda_name" {
  description = "Name of the orchestrator Lambda for CloudWatch log tailing."
  value       = module.lambda.orchestrator_name
}

output "pdf_lambda_name" {
  description = "Name of the PDF generator Lambda for CloudWatch log tailing."
  value       = module.lambda.pdf_generator_name
}

output "sync_command" {
  description = "Run this AWS CLI command to re-sync the Knowledge Base after uploading new catalog files."
  value       = "aws bedrock-agent start-ingestion-job --knowledge-base-id ${module.bedrock.knowledge_base_id} --data-source-id ${module.bedrock.data_source_id} --region ${var.aws_region}"
}
