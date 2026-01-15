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
  # oidc_provider_arn = module.eks.oidc_provider_arn
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
# pbs_project/main.tf 맨 아래

# 1. 정책 붙여넣기 (그대로)
resource "aws_iam_policy" "s3_access_policy" {
  name        = "pbs-ai-s3-access-policy"
  description = "Allow AI service to access S3 bucket"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = ["s3:GetObject", "s3:ListBucket", "s3:PutObject", "s3:DeleteObject", "s3:GetBucketLocation"]
        Effect   = "Allow"
        Resource = ["arn:aws:s3:::pbs-project-ai-data-dev-v1", "arn:aws:s3:::pbs-project-ai-data-dev-v1/*"]
      }
    ]
  })
}

# 2. 역할 모듈 붙여넣기
module "irsa_role" {
  source    = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version   = "~> 5.0"
  role_name = "hybrid-ai-sa-role"

  role_policy_arns = {
    policy = aws_iam_policy.s3_access_policy.arn
  }

  oidc_providers = {
    main = {
      # ❌ 수정 전: provider_arn = var.oidc_provider_arn
      # ✅ 수정 후: 루트 파일이므로 module.eks를 바로 봅니다.
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["default:hybrid-ai-sa"]
    }
  }
}

# 3. 아까 옮겨둔 Service Account (수정할 부분 있음!)
resource "kubernetes_service_account" "hybrid_ai_sa" {
  metadata {
    name      = "hybrid-ai-sa"
    namespace = "default"
    annotations = {
      # ❌ 수정 전: module.iam.irsa_role_arn
      # ✅ 수정 후: 바로 위에 있는 module.irsa_role을 참조
      "eks.amazonaws.com/role-arn" = module.irsa_role.iam_role_arn
    }
  }
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
  # rds_endpoint = module.rds.rds_endpoint

  project_name = var.project_name
  environment  = var.environment
  vpc_id       = module.vpc.vpc_id
  
  # [0104 추가] IAM 모듈에서 만든 노드 역할 ARN을 EKS 모듈로 전달!
  node_role_arn = module.iam.eks_node_role_arn

  # 노드는 반드시 Private App Subnet에 배치
  subnet_ids   = module.vpc.private_subnets 

  waf_acl_arn  = module.waf.web_acl_arn

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
# eks 모듈 안에 잘 있으심다.
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
#data "aws_eks_cluster_auth" "cluster" {
#  name = module.eks.cluster_name
#}
# provier.tf에 helm, kubernetes에 선언. 
# 위 내용은 data "aws_eks_cluster_auth" 코드는 인증 토큰을 "미리 가져와서" 프로바이더에게 넘겨주기 위해 썼던 것임.
# provider의 방식은 exec 부분이 인증 토큰을 직접 만들어내는 역할.

# 8. AWS Load Balancer Controller 설치 (Helm Chart)

# [수정 1] Gateway API CRD 설치 (버전을 v1.1.0으로 명시하여 LBC v2.10+와 호환)
resource "null_resource" "gateway_api_crds" {
  provisioner "local-exec" {
    # 아까 수동으로 치신 명령어입니다. 테라폼이 대신 실행하게 합니다.
    command = "kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.1.0/standard-install.yaml"
  }

  depends_on = [module.eks]
}

# [수정 2] LBC 일꾼 설치 (에러 났던 플래그들을 차트 설정에 맞게 수정)

resource "helm_release" "aws_lbc" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  
  # 최신 버전으로 업데이트 (v2.10.0 이상을 사용해야 Gateway API가 잘 돌아갑니다)
  version    = "1.11.0" # LBC App Version v2.11.0 대응 차트
# 추가---------------------------------------------------------
    set {
    name  = "podAnnotations.force-sync"
    value = timestamp()
  }

# -----------------------------------------------------------

  # [수정 3] Gateway API 활성화 방식 변경
  # "featureGates.GatewayAPI" 대신 "enableGatewayApi"를 사용하는 것이 최신 차트 방식입니다.
  set {
    #name  = "featureGates.GatewayAPI"
    name  = "enableGatewayApi"
    value = "true"
  }

  set {
    name  = "clusterName"
    value = module.eks.cluster_name
  }

  set {
    name  = "serviceAccount.create"
    value = "true" # 아까 eksctl로 만드셨거나 이미 있다면 false
  }

  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }

  # [중요] 아까 우리가 수술한 '권한(IAM Role)' 주소입니다.
  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.eks.lbc_role_arn
  }

  set {
    name  = "region"
    value = "ap-northeast-2"
  }

  # [중요] 아까 수동으로 넣었던 VPC ID를 자동 연결
  set {
    name  = "vpcId"
    value = module.vpc.vpc_id
  }

  # EKS 모듈 생성 후 실행
  depends_on = [module.eks, null_resource.gateway_api_crds]
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
/*
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
*/
# =================================================================
# 6. WAF & ECR
# =================================================================
# WAF (웹 방화벽)
module "waf" {
  source = "./modules/waf"
  name   = var.project_name
}
/*
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
*/
module "ecr" {
  source = "./modules/ecr"
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
  school_public_ip = "203.252.123.123"  # <- 팀원에게 받은 IP
  school_cidr      = "192.168.10.0/24"  # <- 팀원에게 받은 CIDR

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


# 1. Route53 모듈 호출 (인증서 발급 시킴)
module "route53_acm" {
  source       = "./modules/route53"
  domain_name  = "soldesk-group4-pbs-project.click"
  project_name = "pbs-project"
}

# ... (Ingress 리소스가 여기에 있거나 ingress.tf에 있음) ...

# 2. [완전 자동화 마침표] 최종 연결은 여기서!
# 이유: Ingress가 생성되어야 ALB 주소가 나오기 때문에, 
#       모듈보다는 여기서 연결하는 게 의존성 관리에 좋습니다.

resource "aws_route53_record" "root" {
  # 모듈이 찾아둔 Zone ID를 가져다 씁니다.
  zone_id = module.route53_acm.zone_id
  name    = "soldesk-group4-pbs-project.click"
  type    = "A"

  # [추가] "이미 있으면 덮어씌워라" 라는 명령입니다.
  allow_overwrite = true

  alias {
    # Ingress가 만든 ALB 주소
    name                   = kubernetes_ingress_v1.web_ingress.status.0.load_balancer.0.ingress.0.hostname
    zone_id                = "ZWKZPGTI48KDX" # 서울 리전 ALB Zone ID
    evaluate_target_health = true
  }
}
# [추가] ArgoCD 서브도메인 연결 (argocd.soldesk...)
# =================================================================

resource "aws_route53_record" "argocd" {
  # 1. 모듈에서 가져온 Zone ID (기존과 동일)
  zone_id = module.route53_acm.zone_id
  
  # 2. ArgoCD용 서브도메인
  name    = "argocd.soldesk-group4-pbs-project.click"
  type    = "A"

  # [중요] 기존에 팀원이 만든 게 있다면 덮어쓰기 위해 추가
  allow_overwrite = true

  alias {
    # 3. 방금 만든 ArgoCD용 Ingress의 ALB 주소를 가져옴
    # 주의: kubernetes_ingress_v1.argocd_ingress <-- 리소스 이름이 다릅니다!
    name                   = kubernetes_ingress_v1.argocd_ingress.status.0.load_balancer.0.ingress.0.hostname
    zone_id                = "ZWKZPGTI48KDX" # 서울 리전 ALB Zone ID (고정값)
    evaluate_target_health = true
  }
}



# =================================================================
# 9. AI Data Storage (S3 Buckets)
# =================================================================

# 1) AI 모델 및 학습 데이터 저장용
module "s3_ai_data" {
  source = "./modules/s3"

  # 버킷 이름은 전 세계 유일해야 하므로 환경변수 등을 섞습니다.
  bucket_name = "pbs-project-ai-data-${var.environment}-v1"
  
  tags = {
    Name        = "PBS-AI-Data"
    Environment = var.environment
    Role        = "Model-Training-Data"
  }
}

# 2) 시스템 로그 저장용
module "s3_logs" {
  source = "./modules/s3"

  bucket_name = "pbs-project-logs-${var.environment}-v1"
  
  tags = {
    Name        = "PBS Logs"
    Environment = var.environment
    Role        = "System Logs"
  }
}

# =================================================================
# 10. ArgoCD Repository & Applications (GitOps)
# =================================================================

# 1) GitHub 리포지토리 등록 (Secret)
# -----------------------------------------------------------------
resource "kubernetes_secret" "argocd_repo_secret" {
  metadata {
    name      = "pbs-repo-credential" # Secret 이름
    namespace = "argocd"              # ArgoCD가 설치된 네임스페이스
    labels = {
      "argocd.argoproj.io/secret-type" = "repository"
    }
  }

  data = {
    type      = "git"
    url       = "https://github.com/minnnnnuuuu/PBS_2.git" # 실제 리포지토리 주소
    # 제공된 토큰
    password = var.github_token
    username  = "minnnnnuuuu"                                # 깃허브 ID
  }

  type = "Opaque"

  # ArgoCD가 설치된 후에 생성되어야 함
  depends_on = [helm_release.argocd]
}
# [수정된 코드] ArgoCD 앱 등록을 위한 통합 리소스 (스크립트 방식)
resource "null_resource" "argocd_applications" {
  
  # [핵심] EKS와 ArgoCD 설치, 그리고 Secret 생성이 끝날 때까지 무조건 기다림
  depends_on = [
    module.eks,
    helm_release.argocd,
    kubernetes_secret.argocd_repo_secret
  ]

  provisioner "local-exec" {
    interpreter = ["PowerShell", "-Command"]
    
    command = <<-EOT
      # 1. EKS 접속 정보(kubeconfig) 가져오기
      aws eks update-kubeconfig --region ap-northeast-2 --name ${module.eks.cluster_name}
      
      # 2. ArgoCD Web Service 앱 등록
      $web_app_yaml = @"
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: pbs-web-service
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/minnnnnuuuu/PBS_2.git
    path: manifests/eks/apps
    targetRevision: HEAD
  destination:
    server: https://kubernetes.default.svc
    namespace: default
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
"@
      echo $web_app_yaml | kubectl apply -f -

      # 3. ArgoCD Infra(AX Platform) 앱 등록
      $infra_app_yaml = @"
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: pbs-ax-platform
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/minnnnnuuuu/PBS_2.git
    path: manifests/eks/infra
    targetRevision: HEAD
  destination:
    server: https://kubernetes.default.svc
    namespace: default
  syncPolicy:
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
      - PruneLast=true
"@
      echo $infra_app_yaml | kubectl apply -f -
    EOT
  }
}







# 잠시 유배
/*
# 2) Application 1: PBS Web Service (구 y-docs-web)
# -----------------------------------------------------------------
resource "kubernetes_manifest" "app_web_service" {
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "pbs-web-service" # [수정됨] y-docs-web -> pbs-web-service
      namespace = "argocd"
    }
    spec = {
      project = "default"
      source = {
        repoURL        = "https://github.com/minnnnnuuuu/PBS_2.git"
        path           = "manifests/eks/apps" # 웹 서비스 매니페스트 경로
        targetRevision = "HEAD"
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = "default"
      }
      syncPolicy = {
        automated = {
          prune    = true # 리포지토리에서 삭제되면 클러스터에서도 삭제
          selfHeal = true # 수동 변경 시 자동 복구
        }
      }
    }
  }

  depends_on = [helm_release.argocd]
}

# 3) Application 2: PBS AX Platform (AI & Infra)
# -----------------------------------------------------------------
resource "kubernetes_manifest" "app_ax_platform" {
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "pbs-ax-platform"
      namespace = "argocd"
    }
    spec = {
      project = "default"
      source = {
        repoURL        = "https://github.com/minnnnnuuuu/PBS_2.git"
        path           = "manifests/eks/infra" # 인프라(Milvus 등) 매니페스트 경로
        targetRevision = "HEAD"
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = "default"
      }
      syncPolicy = {
        # 인프라 앱은 수동 Sync 권장 (안정성 위함)
        # 필요 시 syncOptions로 대규모 리소스(ServerSideApply) 지원
        syncOptions = [
          "CreateNamespace=true",
          "ServerSideApply=true", # Milvus 등 큰 리소스 에러 방지 [중요]
          "PruneLast=true"
        ]
      }
    }
  }

  depends_on = [helm_release.argocd]
}
*/