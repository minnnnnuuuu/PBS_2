resource "aws_s3_bucket" "this" {
  bucket = var.bucket_name
  force_destroy = true # 개발용이라 삭제 편하게 (운영에선 false 권장)

  tags = var.tags
}

# 퍼블릭 액세스 차단 (보안)
resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}