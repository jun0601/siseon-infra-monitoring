# monitoring 네임스페이스 생성
resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = "monitoring"
  }
}

# kube-prometheus-stack
resource "helm_release" "kube_prometheus_stack" {
  name       = "kube-prometheus-stack"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name
  version    = "58.0.0"
  timeout    = 900

  values = [
    yamlencode({
      grafana = {
        enabled       = true
        adminPassword = var.grafana_admin_password

        service = {
          type = "LoadBalancer"
          annotations = {
            "service.beta.kubernetes.io/aws-load-balancer-scheme" = "internet-facing"
          }
        }

        persistence = {
          enabled = false
        }

        sidecar = {
          datasources = {
            defaultDatasourceEnabled = false
          }
        }

        datasources = {
          "datasources.yaml" = {
            apiVersion = 1
            datasources = [
              {
                name      = "Prometheus"
                type      = "prometheus"
                uid       = "prometheus"
                url       = "http://kube-prometheus-stack-prometheus:9090"
                isDefault = true
              },
              {
                name = "CloudWatch"
                type = "cloudwatch"
                uid  = "cloudwatch"
                jsonData = {
                  defaultRegion = "ap-northeast-2"
                  authType      = "default"
                }
              }
            ]
          }
        }

        dashboardProviders = {
          "dashboardproviders.yaml" = {
            apiVersion = 1
            providers = [
              {
                name            = "infra-templates"
                orgId           = 1
                folder          = "📊 인프라 모니터링"
                type            = "file"
                disableDeletion = true
                editable        = false
                options = {
                  path = "/var/lib/grafana/dashboards/infra-templates"
                }
              },
              {
                name            = "infra-custom"
                orgId           = 1
                folder          = "📊 인프라 모니터링"
                type            = "file"
                disableDeletion = true
                editable        = true
                options = {
                  path = "/var/lib/grafana/dashboards/infra-custom"
                }
              }
            ]
          }
        }

        dashboards = {
          infra-templates = {
            node-exporter-full = {
              gnetId     = 1860
              revision   = 37
              datasource = "Prometheus"
            }
            kubernetes-cluster = {
              gnetId     = 7249
              revision   = 1
              datasource = "Prometheus"
            }
            kubernetes-pods = {
              gnetId     = 6417
              revision   = 1
              datasource = "Prometheus"
            }
          }

          infra-custom = {
            stockops-infra = {
              json = jsonencode({
                title         = "🏭 StockOps 인프라 현황"
                uid           = "stockops-infra-custom"
                timezone      = "Asia/Seoul"
                refresh       = "30s"
                schemaVersion = 38
                tags          = ["stockops", "infra", "custom"]
                time = {
                  from = "now-1h"
                  to   = "now"
                }

                panels = [
                  # Row 1: 클러스터 요약
                  {
                    id      = 1
                    title   = "🖥️ 클러스터 CPU 사용률"
                    type    = "gauge"
                    gridPos = { x = 0, y = 0, w = 4, h = 5 }
                    datasource = { type = "prometheus", uid = "prometheus" }
                    fieldConfig = {
                      defaults = {
                        min  = 0
                        max  = 100
                        unit = "percent"
                        thresholds = {
                          mode = "absolute"
                          steps = [
                            { color = "green", value = null },
                            { color = "yellow", value = 60 },
                            { color = "red", value = 80 }
                          ]
                        }
                      }
                    }
                    targets = [{
                      expr         = "100 - (avg(irate(node_cpu_seconds_total{mode='idle'}[5m])) * 100)"
                      legendFormat = "CPU"
                    }]
                  },
                  {
                    id      = 2
                    title   = "💾 클러스터 메모리 사용률"
                    type    = "gauge"
                    gridPos = { x = 4, y = 0, w = 4, h = 5 }
                    datasource = { type = "prometheus", uid = "prometheus" }
                    fieldConfig = {
                      defaults = {
                        min  = 0
                        max  = 100
                        unit = "percent"
                        thresholds = {
                          mode = "absolute"
                          steps = [
                            { color = "green", value = null },
                            { color = "yellow", value = 60 },
                            { color = "red", value = 80 }
                          ]
                        }
                      }
                    }
                    targets = [{
                      expr         = "100 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes * 100)"
                      legendFormat = "Memory"
                    }]
                  },
                  {
                    id      = 3
                    title   = "✅ Running Pods"
                    type    = "stat"
                    gridPos = { x = 8, y = 0, w = 4, h = 5 }
                    datasource = { type = "prometheus", uid = "prometheus" }
                    fieldConfig = {
                      defaults = {
                        unit = "short"
                        thresholds = {
                          mode = "absolute"
                          steps = [{ color = "green", value = null }]
                        }
                      }
                    }
                    targets = [{
                      expr         = "count(kube_pod_status_phase{phase='Running'})"
                      legendFormat = "Running"
                    }]
                  },
                  {
                    id      = 4
                    title   = "🚨 Failed Pods"
                    type    = "stat"
                    gridPos = { x = 12, y = 0, w = 4, h = 5 }
                    datasource = { type = "prometheus", uid = "prometheus" }
                    fieldConfig = {
                      defaults = {
                        unit = "short"
                        thresholds = {
                          mode = "absolute"
                          steps = [
                            { color = "green", value = null },
                            { color = "red", value = 1 }
                          ]
                        }
                      }
                    }
                    targets = [{
                      expr         = "count(kube_pod_status_phase{phase='Failed', namespace='stockops'}) or vector(0)"
                      legendFormat = "Failed"
                    }]
                  },
                  {
                    id      = 5
                    title   = "🖧 Node 수"
                    type    = "stat"
                    gridPos = { x = 16, y = 0, w = 4, h = 5 }
                    datasource = { type = "prometheus", uid = "prometheus" }
                    fieldConfig = {
                      defaults = {
                        unit = "short"
                        thresholds = {
                          mode = "absolute"
                          steps = [{ color = "blue", value = null }]
                        }
                      }
                    }
                    targets = [{
                      expr         = "count(kube_node_info)"
                      legendFormat = "Nodes"
                    }]
                  },
                  {
                    id      = 6
                    title   = "⏳ Pending Pods"
                    type    = "stat"
                    gridPos = { x = 20, y = 0, w = 4, h = 5 }
                    datasource = { type = "prometheus", uid = "prometheus" }
                    fieldConfig = {
                      defaults = {
                        unit = "short"
                        thresholds = {
                          mode = "absolute"
                          steps = [
                            { color = "green", value = null },
                            { color = "yellow", value = 1 }
                          ]
                        }
                      }
                    }
                    targets = [{
                      expr         = "count(kube_pod_status_phase{phase='Pending'}) or vector(0)"
                      legendFormat = "Pending"
                    }]
                  },

                  # Row 2: StockOps 서비스별 Pod 상태
                  {
                    id      = 7
                    title   = "📋 StockOps 서비스별 Pod 상태"
                    type    = "table"
                    gridPos = { x = 0, y = 5, w = 24, h = 5 }
                    datasource = { type = "prometheus", uid = "prometheus" }
                    targets = [
                      {
                        expr         = "kube_pod_status_phase{namespace='stockops'}"
                        legendFormat = "{{pod}} - {{phase}}"
                        instant      = true
                      }
                    ]
                  },

                  # Row 3: CPU/메모리 시계열
                  {
                    id      = 8
                    title   = "⚡ StockOps Pod CPU 사용률"
                    type    = "timeseries"
                    gridPos = { x = 0, y = 8, w = 12, h = 6 }
                    datasource = { type = "prometheus", uid = "prometheus" }
                    fieldConfig = {
                      defaults = {
                        unit = "percent"
                        custom = {
                          lineWidth   = 2
                          fillOpacity = 15
                        }
                      }
                    }
                    targets = [{
                      expr         = "sum(rate(container_cpu_usage_seconds_total{namespace='stockops',container!=''}[5m])) by (pod) * 100"
                      legendFormat = "{{pod}}"
                    }]
                  },
                  {
                    id      = 9
                    title   = "💡 StockOps Pod 메모리 사용량"
                    type    = "timeseries"
                    gridPos = { x = 12, y = 8, w = 12, h = 6 }
                    datasource = { type = "prometheus", uid = "prometheus" }
                    fieldConfig = {
                      defaults = {
                        unit = "bytes"
                        custom = {
                          lineWidth   = 2
                          fillOpacity = 15
                        }
                      }
                    }
                    targets = [{
                      expr         = "sum(container_memory_working_set_bytes{namespace='stockops',container!=''}) by (pod)"
                      legendFormat = "{{pod}}"
                    }]
                  },

                  # Row 4: 네트워크
                  {
                    id      = 10
                    title   = "📥 네트워크 수신 트래픽"
                    type    = "timeseries"
                    gridPos = { x = 0, y = 14, w = 12, h = 6 }
                    datasource = { type = "prometheus", uid = "prometheus" }
                    fieldConfig = {
                      defaults = {
                        unit = "binBps"
                        custom = {
                          lineWidth   = 2
                          fillOpacity = 15
                        }
                      }
                    }
                    targets = [{
                      expr         = "sum(rate(container_network_receive_bytes_total{namespace='stockops'}[5m])) by (pod)"
                      legendFormat = "{{pod}} RX"
                    }]
                  },
                  {
                    id      = 11
                    title   = "📤 네트워크 송신 트래픽"
                    type    = "timeseries"
                    gridPos = { x = 12, y = 14, w = 12, h = 6 }
                    datasource = { type = "prometheus", uid = "prometheus" }
                    fieldConfig = {
                      defaults = {
                        unit = "binBps"
                        custom = {
                          lineWidth   = 2
                          fillOpacity = 15
                        }
                      }
                    }
                    targets = [{
                      expr         = "sum(rate(container_network_transmit_bytes_total{namespace='stockops'}[5m])) by (pod)"
                      legendFormat = "{{pod}} TX"
                    }]
                  },

                  # Row 5: Pod 재시작 & Node 상태
                  {
                    id      = 12
                    title   = "🔄 Pod 재시작 횟수"
                    type    = "table"
                    gridPos = { x = 0, y = 20, w = 12, h = 6 }
                    datasource = { type = "prometheus", uid = "prometheus" }
                    targets = [{
                      expr         = "sum(kube_pod_container_status_restarts_total{namespace='stockops'}) by (pod)"
                      legendFormat = "{{pod}}"
                      instant      = true
                    }]
                  },
                  {
                    id      = 13
                    title   = "🟢 Node 상태"
                    type    = "table"
                    gridPos = { x = 12, y = 20, w = 12, h = 6 }
                    datasource = { type = "prometheus", uid = "prometheus" }
                    fieldConfig = {
                      defaults = {
                        thresholds = {
                          mode = "absolute"
                          steps = [
                            { color = "green", value = null },
                            { color = "red", value = 0 }
                          ]
                        }
                      }
                    }
                    targets = [{
                      expr         = "kube_node_status_condition{condition='Ready',status='true'}"
                      legendFormat = "{{node}}"
                      instant      = true
                    }]
                  }
                ]
              })
            }
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
        enabled = true
        config = {
          global = {
            smtp_smarthost    = "smtp.gmail.com:587"
            smtp_from         = "bljh5220@gmail.com"
            smtp_auth_username = "bljh5220@gmail.com"
            smtp_auth_password = var.gmail_app_password
            smtp_require_tls  = true
          }
          route = {
            group_by        = ["alertname", "namespace"]
            group_wait      = "30s"
            group_interval  = "5m"
            repeat_interval = "12h"
            receiver        = "gmail"
            routes = [
              {
                match    = { severity = "critical" }
                receiver = "gmail"
              },
              {
                match    = { severity = "warning" }
                receiver = "gmail"
              }
            ]
          }
          receivers = [
            {
              name = "gmail"
              email_configs = [
                {
                  to            = "bljh5220@gmail.com"
                  send_resolved = true
                  subject       = "[StockOps] {{ .GroupLabels.alertname }} - {{ .Status | toUpper }}"
                  body          = "{{ range .Alerts }}알람: {{ .Annotations.summary }}\n상세: {{ .Annotations.description }}\n심각도: {{ .Labels.severity }}\n시간: {{ .StartsAt }}\n{{ end }}"
                }
              ]
            }
          ]
        }
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