variable "bucket_name" {
  description = "S3 버킷 이름"
  type        = string
}

variable "tags" {
  description = "태그"
  type        = map(string)
  default     = {}
}