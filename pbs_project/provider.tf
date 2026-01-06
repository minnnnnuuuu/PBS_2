terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.9"
    }
    # [추가] 쿠버네티스 리소스(Gateway, HTTPRoute)를 만들기 위해 필요합니다.
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
  }

  backend "s3" {
    bucket         = "pbs-project-tfstate-soldesk-pbs" 
    key            = "terraform.tfstate"
    region         = "ap-northeast-2"
    dynamodb_table = "terraform-locks" 
    encrypt        = true
  }
}

provider "aws" {
  region = "ap-northeast-2"
}

# [추가] EKS 클러스터에 접속하기 위한 실시간 인증 토큰을 가져옵니다.
#data "aws_eks_cluster_auth" "this" {
#  name = module.eks.cluster_name # 가영님의 EKS 모듈 출력값에 맞춰야 합니다.
#}

# [추가] 쿠버네티스 프로바이더 설정
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  #token                  = data.aws_eks_cluster_auth.this.token
  exec {
  api_version = "client.authentication.k8s.io/v1beta1"
  command     = "aws"
  args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
}
}

# [기존 수정] Helm 프로바이더에 쿠버네티스 연결 정보를 주입합니다.
provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    #token                  = data.aws_eks_cluster_auth.this.token
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
    }
  }
}