output "orchestrator_invoke_arn"  { value = aws_lambda_function.orchestrator.invoke_arn }
output "orchestrator_arn"         { value = aws_lambda_function.orchestrator.arn }
output "orchestrator_name"        { value = aws_lambda_function.orchestrator.function_name }
output "pdf_generator_arn"        { value = aws_lambda_function.pdf_generator.arn }
output "pdf_generator_name"       { value = aws_lambda_function.pdf_generator.function_name }
output "orchestrator_dev_url"     {
  value = length(aws_lambda_function_url.orchestrator_dev) > 0 ? aws_lambda_function_url.orchestrator_dev[0].function_url : null
}
