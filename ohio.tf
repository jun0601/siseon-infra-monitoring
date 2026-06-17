# ============================================
# 오하이오(us-east-2) 멀티리전 메트릭
# kube-prometheus-stack에서 Prometheus만 (grafana/alertmanager 제외)
# Prometheus를 internal NLB로 노출 → 서울 Grafana가 VPC 피어링으로 직접 조회
# ============================================

resource "kubernetes_namespace" "monitoring_ohio" {
  provider = kubernetes.ohio
  metadata {
    name = "monitoring"
  }
}

resource "helm_release" "kps_ohio" {
  provider   = helm.ohio
  name       = "kube-prometheus-stack"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  namespace  = kubernetes_namespace.monitoring_ohio.metadata[0].name
  version    = "58.0.0"
  timeout    = 900

  values = [
    yamlencode({
      # 서울에만 Grafana/Alertmanager 두고 오하이오는 메트릭 수집기만
      grafana      = { enabled = false }
      alertmanager = { enabled = false }

      # EKS 관리형 컨트롤플레인은 스크랩 불가 → 비활성(다운 타겟 노이즈 제거)
      kubeControllerManager = { enabled = false }
      kubeScheduler         = { enabled = false }
      kubeEtcd              = { enabled = false }
      kubeProxy             = { enabled = false }

      nodeExporter     = { enabled = true }
      kubeStateMetrics = { enabled = true }

      prometheus = {
        service = {
          type = "LoadBalancer"
          annotations = {
            "service.beta.kubernetes.io/aws-load-balancer-type"            = "external"
            "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type" = "ip"
            "service.beta.kubernetes.io/aws-load-balancer-scheme"          = "internal"
          }
        }
        prometheusSpec = {
          retention = "3d"
          # 모든 ServiceMonitor 선택 (release 라벨 무관)
          serviceMonitorSelectorNilUsesHelmValues = false
          podMonitorSelectorNilUsesHelmValues     = false
          ruleSelectorNilUsesHelmValues           = false
          resources = {
            requests = { memory = "512Mi", cpu = "100m" }
            limits   = { memory = "1Gi", cpu = "500m" }
          }
        }
      }
    })
  ]

  depends_on = [kubernetes_namespace.monitoring_ohio]
}

# 오하이오 stockops 앱 ServiceMonitor (api/ai) — 오하이오 Prometheus가 스크랩
resource "kubernetes_manifest" "stockops_api_servicemonitor_ohio" {
  provider = kubernetes.ohio
  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "PodMonitor"
    metadata = {
      name      = "stockops-api"
      namespace = "monitoring"
      labels    = { release = "kube-prometheus-stack" }
    }
    spec = {
      selector          = { matchLabels = { app = "stockops-api" } }
      namespaceSelector = { matchNames = ["stockops"] }
      # 오하이오 stockops 서비스는 라벨/포트명이 없어 PodMonitor로 파드 직접 스크랩
      podMetricsEndpoints = [
        { targetPort = 8080, path = "/actuator/prometheus", interval = "30s" }
      ]
    }
  }
  depends_on = [helm_release.kps_ohio]
}

resource "kubernetes_manifest" "stockops_ai_servicemonitor_ohio" {
  provider = kubernetes.ohio
  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "PodMonitor"
    metadata = {
      name      = "stockops-ai"
      namespace = "monitoring"
      labels    = { release = "kube-prometheus-stack" }
    }
    spec = {
      selector          = { matchLabels = { app = "stockops-ai" } }
      namespaceSelector = { matchNames = ["stockops"] }
      # 오하이오 stockops 서비스는 라벨/포트명이 없어 PodMonitor로 파드 직접 스크랩
      podMetricsEndpoints = [
        { targetPort = 8000, path = "/metrics", interval = "30s" }
      ]
    }
  }
  depends_on = [helm_release.kps_ohio]
}

# 오하이오 Prometheus internal NLB 프로비저닝 대기
resource "time_sleep" "wait_for_ohio_prometheus_nlb" {
  depends_on      = [helm_release.kps_ohio]
  create_duration = "240s"
}

# NLB DNS 조회 → 서울 Grafana 데이터소스 URL로 사용
data "kubernetes_service" "ohio_prometheus" {
  provider   = kubernetes.ohio
  depends_on = [time_sleep.wait_for_ohio_prometheus_nlb]
  metadata {
    name      = "kube-prometheus-stack-prometheus"
    namespace = "monitoring"
  }
}

locals {
  ohio_prometheus_url = "http://${data.kubernetes_service.ohio_prometheus.status[0].load_balancer[0].ingress[0].hostname}:9090"
}
