# monitoring 네임스페이스 생성
resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = "monitoring"
  }
}

# kube-prometheus-stack (Prometheus + Grafana + AlertManager + Node Exporter)
resource "helm_release" "kube_prometheus_stack" {
  name       = "kube-prometheus-stack"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name
  version    = "58.0.0"

  timeout = 600

  values = [
    yamlencode({
      grafana = {
        enabled       = true
        adminPassword = var.grafana_admin_password

        service = {
          type = "LoadBalancer"
        }

        persistence = {
          enabled = false
        }

        datasources = {
          "datasources.yaml" = {
            apiVersion = 1
            datasources = [
              {
                name      = "Prometheus"
                type      = "prometheus"
                url       = "http://kube-prometheus-stack-prometheus:9090"
                isDefault = true
              },
              {
                name = "CloudWatch"
                type = "cloudwatch"
                jsonData = {
                  defaultRegion = "ap-northeast-2"
                  authType      = "default"
                }
              }
            ]
          }
        }
      }

      prometheus = {
        enabled = true
        prometheusSpec = {
          retention = "7d"
          resources = {
            requests = {
              memory = "256Mi"
              cpu    = "100m"
            }
            limits = {
              memory = "512Mi"
              cpu    = "500m"
            }
          }
        }
      }

      alertmanager = {
        enabled = false
      }

      nodeExporter = {
        enabled = true
      }

      kubeStateMetrics = {
        enabled = true
      }
    })
  ]

  depends_on = [kubernetes_namespace.monitoring]
}