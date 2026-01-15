# -----------------------------------------------------------
# [최종 수정] EKS 하이브리드 관제 및 오토스케일링 설정
# -----------------------------------------------------------

# 1. 지표 배달부 (Prometheus Agent)
resource "helm_release" "prometheus_agent" {
  name             = "prometheus-agent-v3"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "prometheus"
  namespace        = "monitoring"
  create_namespace = true
  wait             = false

  values = [<<EOF
server:
  persistentVolume:
    enabled: false
  remoteWrite:
    - url: "https://prometheus.cloudreaminu.cloud/api/v1/write"
  global:
    external_labels:
      cluster: "pbs-eks-dev"
alertmanager:
  enabled: false
pushgateway:
  enabled: false
nodeExporter:
  enabled: true
kubeStateMetrics:
  enabled: true
EOF
  ]
  depends_on = [module.eks]
}

# 2. 로그 배달부 (Promtail)
resource "helm_release" "promtail" {
  name             = "promtail"
  repository       = "https://grafana.github.io/helm-charts"
  chart            = "promtail"
  namespace        = "monitoring"
  create_namespace = true
  wait             = false

  values = [<<EOF
config:
  clients:
    - url: "https://loki.cloudreaminu.cloud/loki/api/v1/push"
      external_labels:
        cluster: "pbs-eks-dev"
EOF
  ]
  depends_on = [module.eks]
}

# -----------------------------------------------------------
# [신규 추가] 3. 지표 측정기 (Metrics Server) - HPA 작동 필수
# -----------------------------------------------------------
resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  namespace  = "kube-system" # 시스템 네임스페이스에 설치
  version    = "3.11.0"
  wait       = false

  # EKS에서 노드 지표를 안전하게 읽어오기 위한 필수 설정
  set {
    name  = "args"
    value = "{--kubelet-insecure-tls,--kubelet-preferred-address-types=InternalIP}"
  }

  depends_on = [module.eks]
}