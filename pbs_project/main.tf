# 파일 위치: pbs_project/main.tf

# =================================================================
# 1. VPC & Network
# =================================================================
# VPC (네트워크) 모듈 호출
module "vpc" {
  source = "./modules/vpc"

  name     = "${var.project_name}-vpc"
  vpc_cidr = var.vpc_cidr # 아키텍처 그림에 있는 CIDR
}
# SG (보안그룹) 모듈 호출
module "sg" {
  source = "./modules/security_group"

  name = var.project_name
  vpc_id = module.vpc.vpc_id  # vpc_id는 vpc 모듈이 뱉어내는 결과값(output)
}
# =================================================================
# 2. Security & Secrets
# =================================================================
module "kms" {
  source = "./modules/kms"

  name = var.project_name
}
# Secret  Manager (DB 금고 비밀번호)
module "secrets_manager" {
  source = "./modules/secrets_manager"

  name = var.project_name
  kms_key_id = module.kms.key_id
}
# =================================================================
# 3. Compute & Storage (Bastion, EFS, RDS)
# =================================================================

# IAM (EC2 권한 관리)
module "iam" {
  source = "./modules/iam"
  name   = var.project_name
}

# Bastion Host (관리용 서버)
module "bastion" {
  source = "./modules/bastion"

  name                 = var.project_name
  vpc_id               = module.vpc.vpc_id
  subnet_id            = module.vpc.public_subnets[0] # 첫 번째 퍼블릭 서브넷에 배치
  iam_instance_profile = module.iam.instance_profile_name
}

# EFS module
module "efs" {
  source = "./modules/efs"

  project_name = var.project_name
  environment  = var.environment
  vpc_id       = module.vpc.vpc_id
  
  # [중요] 아키텍처상 Private Data Subnet에 배치
  subnet_ids   = module.vpc.database_subnets
  
  # KMS 모듈에서 만든 키 사용
  kms_key_arn  = module.kms.key_arn
  
  # EKS 노드 그룹의 보안 그룹 ID (EKS 모듈 또는 SG 모듈 output 참조)
  # 예: module.eks.node_security_group_id 또는 module.security_group.eks_node_sg_id
  node_security_group_ids = [module.eks.node_security_group_id] # eks의 생성 후 sg id 넘길 수 있음
}
module "rds" {
  source = "./modules/rds"

  name = var.project_name
  vpc_id = module.vpc.vpc_id

  # DB 전용 서브넷에 넣음
  subnets    = module.vpc.database_subnets 
  
  # DB 전용 보안그룹 적용
  sg_id      = module.sg.rds_sg_id         
  
  # 아까 만든 비밀번호 금고 주소 전달
  secret_arn = module.secrets_manager.secret_arn

  # Secrets Manager가 비밀번호 생성을 완전히 끝낼 때까지 RDS 생성을 대기시킴.
  # secrets manager 모듈이 secret(pw 금고)를 만들고 비밀번호를 넣는 중, RDS 모듈이 secret에 pw를 요구하여, 데이터 조회시도
  # But pw가 아직 저장되지 않았거나 secret이 완전히 준비되지 않아서, 리소스를 찾을 수 없는 에러
  depends_on = [module.secrets_manager]
}

# =================================================================
# 4. EKS Cluster
# =================================================================

variable "bootstrap_mode" {
  description = "초기 설치 시 Helm 제외 모드"
  type        = bool
  default     = false
}

# EKS module
module "eks" {
  source = "./modules/eks"

  project_name = var.project_name
  environment  = var.environment
  vpc_id       = module.vpc.vpc_id
  
  # 노드는 반드시 Private App Subnet에 배치
  subnet_ids   = module.vpc.private_subnets 

  # IAM 모듈(Role 생성)이 완전히 끝날 때까지 기다렸다가 시작
  depends_on = [module.iam]
}

# [팀원 일괄 등록] terraform.tfvars 파일의 명단을 읽어와 자동 적용

# 1. 입장권 발급 (반복문)
resource "aws_eks_access_entry" "team_members" {
  # 변수에 있는 명단(set)을 하나씩 꺼내서 반복
  for_each      = toset(var.team_members)
  
  cluster_name  = module.eks.cluster_name
  principal_arn = each.value # 명단에 있는 ARN 하나씩 대입
  type          = "STANDARD"
}

# 2. 관리자 권한 부여 (반복문)
resource "aws_eks_access_policy_association" "team_members_policy" {
  for_each      = toset(var.team_members)

  cluster_name  = module.eks.cluster_name
  principal_arn = each.value
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  # 입장권이 먼저 만들어져야 권한을 줄 수 있음
  depends_on = [aws_eks_access_entry.team_members]
}

# [필수 요구사항] EFS CSI Driver 자동 설치
#resource "aws_eks_addon" "efs_csi_driver" {
#  # EKS 모듈에서 cluster_name을 뱉어내야 합니다!
#  cluster_name = module.eks.cluster_name 
#  addon_name   = "aws-efs-csi-driver"
#  addon_version = "v2.0.7-eksbuild.1" # 최신 버전 사용 권장
  
#  resolve_conflicts_on_create = "OVERWRITE"
#  resolve_conflicts_on_update = "OVERWRITE"

#  depends_on = [module.eks] # 클러스터가 다 만들어진 뒤에 설치
#}

# 이미 설치된 드라이버를 내 테라폼으로 가져와!" (Import)
# destroy 후 첫 apply 시 import 지우기
#import {
#  to = aws_eks_addon.efs_csi_driver
  
  # 형식: "클러스터이름:애드온이름"
  # 아까 에러 로그에 뜬 실제 클러스터 이름을 정확히 넣었습니다.
#  id = "pbs-project-dev-cluster:aws-efs-csi-driver"
#}


# =================================================================
# 5. Kubernetes Providers & Helm
# =================================================================

# EKS 클러스터 인증 정보를 가져옴
#  Helm Provider 설정 (EKS와 통신하기 위한 설정)
data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_name
}

# 헬름 모듈
provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.cluster.token
  }
}

# 쿠버 모듈 변경
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}

# 8. AWS Load Balancer Controller 설치 (Helm Chart)

resource "helm_release" "aws_lbc" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = "1.7.1"

  # 1. 게이트웨이 기능 활성화 (아까 모듈 안에 있던 설정)
  set {
    name  = "featureGates"
    value = "GatewayAPI=true"
  }

  # 2. 클러스터 이름 (모듈 결과값 참조)
  set {
    name  = "clusterName"
    value = module.eks.cluster_name
  }

  set {
    name  = "serviceAccount.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.eks.lbc_role_arn
  }

  set {
    name  = "region"
    value = "ap-northeast-2"
  }

  set {
    name  = "vpcId"
    value = module.vpc.vpc_id
  }

  # EKS 모듈 생성 후 실행
  depends_on = [module.eks]
}

# ArgoCD 설치 (Helm) - 하이브리드 배포의 사령탑
# =================================================================
resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd"
  create_namespace = true
  version          = "5.51.6" # 버전은 최신 안정화 버전에 따라 변경 가능

  # EKS 클러스터가 생성된 후에 설치
  depends_on = [module.eks]
  
  # 필요시 values 설정 (기본값으로 써도 무방)
  set {
    name  = "server.service.type"
    value = "LoadBalancer" # ArgoCD 접속용 LB 생성 (나중에 Ingress로 변경 권장)
  }
}

# 모니터링 스택 (Prometheus + Grafana)
# =================================================================
resource "helm_release" "kube_prometheus_stack" {
  name             = "prometheus-stack"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  namespace        = "monitoring"
  create_namespace = true
  version          = "56.0.0" # 안정적인 버전 사용

  depends_on = [module.eks]

  # 그라파나 관리자 비밀번호 설정 (원하는 대로 바꾸세요)
  set {
    name  = "grafana.adminPassword"
    value = "pbs1234!" 
  }

  # (선택) 로드밸런서로 그라파나 외부 노출 (테스트용)
  # 보안상 나중에는 Ingress로 바꾸고 VPN 내부에서만 접속하는 게 좋습니다.
  set {
    name  = "grafana.service.type"
    value = "LoadBalancer"
  }
}

# =================================================================
# 6. WAF & ECR
# =================================================================
# WAF (웹 방화벽)
module "waf" {
  source = "./modules/waf"
  name   = var.project_name
}
# ECR (도커 이미지 저장소) - 직접 생성 방식
# 1. 저장소 생성
resource "aws_ecr_repository" "app_repo" {
  name                 = "${var.project_name}-repo"
  image_tag_mutability = "MUTABLE"
  force_delete         = true  # 안에 이미지가 있어도 삭제 가능하게

  image_scanning_configuration {
    scan_on_push = true
  }
}

# 2. 수명 주기 정책 (오래된 이미지 삭제)
resource "aws_ecr_lifecycle_policy" "app_repo_policy" {
  repository = aws_ecr_repository.app_repo.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images"
        selection    = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action       = {
          type = "expire"
        }
      }
    ]
  })
}
# =================================================================
# 7. VPN Connection (On-Premise)
# =================================================================
module "vpn" {
  source = "./modules/vpn"

  # [1] VPC 정보 넘겨주기 (기존에 만든 VPC 모듈에서 가져옴)
  vpc_id                  = module.vpc.vpc_id
  private_route_table_ids = module.vpc.private_route_table_ids

  # [2] 학교 정보 입력 (팀원에게 받으면 여기를 수정하세요!)
  school_public_ip = "203.252.xxx.xxx"  # <- 팀원에게 받은 IP
  school_cidr      = "192.168.xx.0/24"  # <- 팀원에게 받은 CIDR

  # [3] 태그 설정
  tags = {
    Environment = "dev"
    Project     = "PBS"
  }
}

# =================================================================
# 8. DNS & ACM (Route53 - 100% 자동화 버전)
# =================================================================
# [수정] Route53 Zone (새로 만드는 게 아니라, 미리 만들어둔 걸 가져옴)
# =================================================================

# 1. 이미 존재하는 Zone 정보를 읽어옵니다.
data "aws_route53_zone" "main" {
  name         = "y.com."  # 끝에 점(.)을 찍는 것이 정석입니다.
  private_zone = false
}

# 2. ACM 인증서 (이건 매번 새로 만들어도 됨)
resource "aws_acm_certificate" "cert" {
  domain_name       = "y.com"   # ★ 실제 도메인으로 변경
  validation_method = "DNS"

  # 서브도메인(*.y.com)도 같이 커버하려면 아래 주석 해제
  # subject_alternative_names = ["*.y.com"]

  tags = {
    Name = "${var.project_name}-cert"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# 3. [100% 자동화 핵심] 인증서 검증용 DNS 레코드를 "자동으로" 등록
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.main.zone_id # 가져온 Zone ID 사용
}

# 4. ACM 검증 대기 (이게 끝나야 다음 단계로 넘어감)
resource "aws_acm_certificate_validation" "cert" {
  certificate_arn         = aws_acm_certificate.cert.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}


