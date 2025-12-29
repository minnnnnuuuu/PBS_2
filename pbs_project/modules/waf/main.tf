# modules/waf/main.tf

variable "name" {}

resource "aws_wafv2_web_acl" "this" {
  name        = "${var.name}-web-acl"
  description = "WAF for ALB - Common Rules + Known Bad Inputs"
  scope       = "REGIONAL" # ALB용은 REGIONAL, CloudFront용은 CLOUDFRONT

  default_action {
    allow {} # 기본적으로 다 통과시키고, 나쁜 놈만 막음
  }

  # 규칙 1: AWS 관리형 공통 규칙 (OWASP Top 10 등)
  rule {
    name     = "AWS-AWSManagedRulesCommonRuleSet"
    priority = 10

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWS-AWSManagedRulesCommonRuleSet"
      sampled_requests_enabled   = true
    }
  }

  # 규칙 2: 알려진 나쁜 입력값 차단 (Bad Inputs)
  rule {
    name     = "AWS-AWSManagedRulesKnownBadInputsRuleSet"
    priority = 20

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWS-AWSManagedRulesKnownBadInputsRuleSet"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.name}-web-acl"
    sampled_requests_enabled   = true
  }
}