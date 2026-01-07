# pbs_project/modules/ecr/main.tf
# -----------------------------------------------------------
# [선우님 요청] ECR 저장소 이원화 및 수명 주기 관리
# -----------------------------------------------------------

# 1. AI 엔진 저장소 (기존 pbs-project-repo)
resource "aws_ecr_repository" "ai_engine_repo" {
  name                 = "pbs-project-repo"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
  image_scanning_configuration { scan_on_push = true }
}

# 2. 하이브리드 서비스 저장소 (신규 hybrid-service)
resource "aws_ecr_repository" "hybrid_service_repo" {
  name                 = "hybrid-service"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
  image_scanning_configuration { scan_on_push = true }
}

# 3. 수명 주기 정책 (두 저장소 공통 적용 - 최신 10개만 유지)
resource "aws_ecr_lifecycle_policy" "repo_policy" {
  for_each   = toset([aws_ecr_repository.ai_engine_repo.name, aws_ecr_repository.hybrid_service_repo.name])
  repository = each.value
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 images"
      selection    = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action       = { type = "expire" }
    }]
  })
}

# 4. 주소 출력 (Outputs)
output "ai_engine_repo_url" {
  description = "AI Engine ECR Repository URL"
  value       = aws_ecr_repository.ai_engine_repo.repository_url
}

output "hybrid_service_repo_url" {
  description = "Hybrid Service ECR Repository URL"
  value       = aws_ecr_repository.hybrid_service_repo.repository_url
}