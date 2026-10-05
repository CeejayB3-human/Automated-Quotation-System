output "catalog_bucket_name" { value = aws_s3_bucket.catalog.bucket }
output "catalog_bucket_arn"  { value = aws_s3_bucket.catalog.arn }
output "output_bucket_name"  { value = aws_s3_bucket.output.bucket }
output "output_bucket_arn"   { value = aws_s3_bucket.output.arn }
