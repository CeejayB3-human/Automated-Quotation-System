###############################################################################
# API Gateway Module — HTTP API (v2)
###############################################################################

resource "aws_apigatewayv2_api" "quotation" {
  name          = "${var.name_prefix}-api"
  protocol_type = "HTTP"
  description   = "Netpro AI Quotation Generator API"

  cors_configuration {
    allow_headers  = ["Content-Type", "Authorization"]
    allow_methods  = ["POST", "OPTIONS"]
    allow_origins  = ["*"]
    max_age        = 3600
  }

  tags = {
    Name = "${var.name_prefix}-api"
  }
}

# ── Lambda integration ─────────────────────────────────────────────────────
resource "aws_apigatewayv2_integration" "orchestrator" {
  api_id                 = aws_apigatewayv2_api.quotation.id
  integration_type       = "AWS_PROXY"
  integration_uri        = var.orchestrator_lambda_invoke_arn
  payload_format_version = "2.0"
  timeout_milliseconds   = 29000
}

# ── Routes ─────────────────────────────────────────────────────────────────
resource "aws_apigatewayv2_route" "generate_quotation" {
  api_id    = aws_apigatewayv2_api.quotation.id
  route_key = "POST /quotation"
  target    = "integrations/${aws_apigatewayv2_integration.orchestrator.id}"
}

resource "aws_apigatewayv2_route" "health" {
  api_id    = aws_apigatewayv2_api.quotation.id
  route_key = "GET /health"
  target    = "integrations/${aws_apigatewayv2_integration.orchestrator.id}"
}

# ── Stage ──────────────────────────────────────────────────────────────────
resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.quotation.id
  name        = var.environment
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gw.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      routeKey       = "$context.routeKey"
      status         = "$context.status"
      protocol       = "$context.protocol"
      responseLength = "$context.responseLength"
      errorMessage   = "$context.error.message"
    })
  }

  default_route_settings {
    throttling_burst_limit = 50
    throttling_rate_limit  = 20
  }

  tags = {
    Name = "${var.name_prefix}-api-stage"
  }
}

# ── CloudWatch Logs ────────────────────────────────────────────────────────
resource "aws_cloudwatch_log_group" "api_gw" {
  name              = "/aws/apigateway/${var.name_prefix}"
  retention_in_days = 30
}

# ── Lambda permission ──────────────────────────────────────────────────────
resource "aws_lambda_permission" "api_gw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.orchestrator_lambda_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.quotation.execution_arn}/*/*"
}
