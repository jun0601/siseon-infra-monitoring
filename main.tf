data "aws_eks_cluster" "seoul" {
  name = var.cluster_name
}

locals {
  eks_oidc_issuer = replace(data.aws_eks_cluster.seoul.identity[0].oidc[0].issuer, "https://", "")
}

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
        plugins = [
          "grafana-athena-datasource"
        ]
        serviceAccount = {
          create = true
          name   = "grafana-athena-sa"
          annotations = {
            "eks.amazonaws.com/role-arn" = aws_iam_role.grafana_athena_role.arn
          }
        }

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
          dashboards = {
            enabled = false
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
              },
              {
                name = "CloudWatch-Ohio"
                type = "cloudwatch"
                uid  = "cloudwatch-ohio"
                jsonData = {
                  defaultRegion = "us-east-2"
                  authType      = "default"
                }
              },
              {
                name = "Athena"
                type = "grafana-athena-datasource"
                uid  = "athena"
                jsonData = {
                  defaultRegion = "ap-northeast-2"
                  catalog       = "AwsDataCatalog"
                  database      = "stockops_sensor"
                  workgroup     = "siseon-sensor-workgroup"
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
              },
              {
                name            = "iot-custom"
                orgId           = 1
                folder          = "🚀 애플리케이션 모니터링"
                type            = "file"
                disableDeletion = true
                editable        = true
                options = {
                  path = "/var/lib/grafana/dashboards/iot-custom"
                }
              },
              {
                name            = "applog-custom"
                orgId           = 1
                folder          = "🚀 애플리케이션 모니터링"
                type            = "file"
                disableDeletion = true
                editable        = true
                options = {
                  path = "/var/lib/grafana/dashboards/applog-custom"
                }
              },
              {
                name            = "appmetric-custom"
                orgId           = 1
                folder          = "🚀 애플리케이션 모니터링"
                type            = "file"
                disableDeletion = true
                editable        = true
                options = {
                  path = "/var/lib/grafana/dashboards/appmetric-custom"
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

                templating = {
                  list = [
                    {
                      name       = "region"
                      type       = "custom"
                      label      = "🌐 리전"
                      query      = "서울 : seoul,미국(오하이오) : ohio"
                      includeAll = false
                      multi      = false
                      current    = { text = "서울", value = "seoul" }
                    }
                  ]
                }

                panels = [
                  {
                    id         = 1
                    title      = "🖥️ 노드별 CPU 사용률"
                    type       = "gauge"
                    gridPos    = { x = 0, y = 0, w = 12, h = 6 }
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
                      expr         = "label_replace(100 - (avg by(instance) (irate(node_cpu_seconds_total{mode='idle'}[5m])) * 100), \"node\", \"$1\", \"instance\", \"([^:]+):.*\")"
                      legendFormat = "{{node}}"
                    }]
                  },
                  {
                    id         = 2
                    title      = "💾 노드별 메모리 사용률"
                    type       = "gauge"
                    gridPos    = { x = 12, y = 0, w = 12, h = 6 }
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
                      expr         = "label_replace(100 - (avg by(instance) (node_memory_MemAvailable_bytes) / avg by(instance) (node_memory_MemTotal_bytes) * 100), \"node\", \"$1\", \"instance\", \"([^:]+):.*\")"
                      legendFormat = "{{node}}"
                    }]
                  },
                  {
                    id         = 3
                    title      = "✅ Running Pods"
                    type       = "stat"
                    gridPos    = { x = 0, y = 6, w = 6, h = 5 }
                    datasource = { type = "prometheus", uid = "prometheus" }
                    fieldConfig = {
                      defaults = {
                        unit = "short"
                        thresholds = {
                          mode  = "absolute"
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
                    id         = 4
                    title      = "🚨 Failed Pods"
                    type       = "stat"
                    gridPos    = { x = 6, y = 6, w = 6, h = 5 }
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
                      expr         = "count(kube_pod_status_phase{phase='Failed', namespace='stockops'} == 1) or vector(0)"
                      legendFormat = "Failed"
                    }]
                  },
                  {
                    id         = 5
                    title      = "🖧 Node 수"
                    type       = "stat"
                    gridPos    = { x = 12, y = 6, w = 6, h = 5 }
                    datasource = { type = "prometheus", uid = "prometheus" }
                    fieldConfig = {
                      defaults = {
                        unit = "short"
                        thresholds = {
                          mode  = "absolute"
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
                    id         = 6
                    title      = "⏳ Pending Pods"
                    type       = "stat"
                    gridPos    = { x = 18, y = 6, w = 6, h = 5 }
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
                      expr         = "count(kube_pod_status_phase{phase='Pending', namespace='stockops'} == 1) or vector(0)"
                      legendFormat = "Pending"
                    }]
                  },
                  {
                    id         = 7
                    title      = "⚡ StockOps Pod CPU 사용률"
                    type       = "timeseries"
                    gridPos    = { x = 0, y = 11, w = 12, h = 6 }
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
                    options = {
                      legend = {
                        displayMode = "table"
                        placement   = "right"
                        calcs       = ["lastNotNull", "max"]
                      }
                    }
                    targets = [{
                      expr         = "sum(rate(container_cpu_usage_seconds_total{namespace='stockops',container!=''}[5m])) by (pod) * 100"
                      legendFormat = "{{pod}}"
                    }]
                  },
                  {
                    id         = 8
                    title      = "💡 StockOps Pod 메모리 사용량"
                    type       = "timeseries"
                    gridPos    = { x = 12, y = 11, w = 12, h = 6 }
                    datasource = { type = "prometheus", uid = "prometheus" }
                    fieldConfig = {
                      defaults = {
                        unit = "bytes"
                        custom = {
                          lineWidth   = 2
                          fillOpacity = 15
                          scaleDistribution = {
                            type = "log"
                            log  = 2
                          }
                        }
                      }
                    }
                    options = {
                      legend = {
                        displayMode = "table"
                        placement   = "right"
                        calcs       = ["lastNotNull", "max"]
                      }
                    }
                    targets = [{
                      expr         = "sum(container_memory_working_set_bytes{namespace='stockops',container!=''}) by (pod)"
                      legendFormat = "{{pod}}"
                    }]
                  },
                  {
                    id         = 9
                    title      = "📥 네트워크 수신 트래픽"
                    type       = "timeseries"
                    gridPos    = { x = 0, y = 17, w = 12, h = 6 }
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
                    options = {
                      legend = {
                        displayMode = "table"
                        placement   = "right"
                        calcs       = ["lastNotNull", "max"]
                      }
                    }
                    targets = [{
                      expr         = "sum(rate(container_network_receive_bytes_total{namespace='stockops'}[5m])) by (pod)"
                      legendFormat = "{{pod}} RX"
                    }]
                  },
                  {
                    id         = 10
                    title      = "📤 네트워크 송신 트래픽"
                    type       = "timeseries"
                    gridPos    = { x = 12, y = 17, w = 12, h = 6 }
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
                    options = {
                      legend = {
                        displayMode = "table"
                        placement   = "right"
                        calcs       = ["lastNotNull", "max"]
                      }
                    }
                    targets = [{
                      expr         = "sum(rate(container_network_transmit_bytes_total{namespace='stockops'}[5m])) by (pod)"
                      legendFormat = "{{pod}} TX"
                    }]
                  },
                  {
                    id         = 11
                    title      = "🔄 Pod 재시작 횟수"
                    type       = "table"
                    gridPos    = { x = 0, y = 23, w = 12, h = 6 }
                    datasource = { type = "prometheus", uid = "prometheus" }
                    targets = [{
                      expr         = "sum(kube_pod_container_status_restarts_total{namespace='stockops'}) by (pod)"
                      legendFormat = "{{pod}}"
                      instant      = true
                    }]
                  },
                  {
                    id         = 12
                    title      = "🟢 Node 상태"
                    type       = "table"
                    gridPos    = { x = 12, y = 23, w = 12, h = 6 }
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
                  },
                  {
                    id         = 13
                    title      = "📋 StockOps 서비스별 Pod 상태"
                    type       = "table"
                    gridPos    = { x = 0, y = 29, w = 24, h = 5 }
                    datasource = { type = "prometheus", uid = "prometheus" }
                    targets = [
                      {
                        expr         = "kube_pod_status_phase{namespace='stockops', phase='Running'} == 1"
                        legendFormat = "{{pod}}"
                        instant      = true
                      }
                    ]
                  }
                ]
              })
            }
          },
          iot-custom = {
            stockops-iot = {
              json = jsonencode({
                title         = "🌡️ StockOps IoT 센서 현황"
                uid           = "stockops-iot-custom"
                timezone      = "Asia/Seoul"
                refresh       = "1m"
                schemaVersion = 38
                tags          = ["stockops", "iot", "sensor"]
                time = {
                  from = "now-6h"
                  to   = "now"
                }

                templating = {
                  list = [
                    {
                      name       = "site_id"
                      type       = "query"
                      label      = "창고"
                      refresh    = 2
                      datasource = { type = "grafana-athena-datasource", uid = "athena" }
                      query = {
                        rawSQL = "SELECT DISTINCT site_id FROM stockops_sensor.sensor_data WHERE year='2026' AND month='06'"
                        format = 0
                        connectionArgs = {
                          catalog  = "AwsDataCatalog"
                          database = "stockops_sensor"
                        }
                      }
                      includeAll = false
                      multi      = false
                    }
                  ]
                }

                panels = [
                  {
                    id         = 1
                    title      = "🌡️ 온도 (°C)"
                    type       = "timeseries"
                    gridPos    = { x = 0, y = 0, w = 8, h = 8 }
                    datasource = { type = "grafana-athena-datasource", uid = "athena" }
                    fieldConfig = {
                      defaults = {
                        unit = "celsius"
                        custom = {
                          lineWidth   = 2
                          fillOpacity = 15
                        }
                        color = {
                          mode       = "fixed"
                          fixedColor = "red"
                        }
                        thresholds = {
                          mode = "absolute"
                          steps = [
                            { color = "green", value = null },
                            { color = "yellow", value = 25 },
                            { color = "red", value = 35 }
                          ]
                        }
                      }
                    }
                    targets = [{
                      rawSQL = "SELECT timestamp AS time, value, sensor_id FROM stockops_sensor.sensor_data WHERE sensor_type='temperature' AND site_id LIKE '%$site_id%' AND year='2026' AND month='06' AND $__timeFilter(timestamp) ORDER BY time"
                      format = 1
                      refId  = "A"
                      connectionArgs = {
                        catalog  = "AwsDataCatalog"
                        database = "stockops_sensor"
                      }
                    }]
                  },
                  {
                    id         = 2
                    title      = "💧 습도 (%)"
                    type       = "timeseries"
                    gridPos    = { x = 8, y = 0, w = 8, h = 8 }
                    datasource = { type = "grafana-athena-datasource", uid = "athena" }
                    fieldConfig = {
                      defaults = {
                        unit = "percent"
                        custom = {
                          lineWidth   = 2
                          fillOpacity = 15
                        }
                        color = {
                          mode       = "fixed"
                          fixedColor = "blue"
                        }
                        thresholds = {
                          mode = "absolute"
                          steps = [
                            { color = "green", value = null },
                            { color = "yellow", value = 70 },
                            { color = "red", value = 85 }
                          ]
                        }
                      }
                    }
                    targets = [{
                      rawSQL = "SELECT timestamp AS time, value, sensor_id FROM stockops_sensor.sensor_data WHERE sensor_type='humidity' AND site_id LIKE '%$site_id%' AND year='2026' AND month='06' AND $__timeFilter(timestamp) ORDER BY time"
                      format = 1
                      refId  = "A"
                      connectionArgs = {
                        catalog  = "AwsDataCatalog"
                        database = "stockops_sensor"
                      }
                    }]
                  },
                  {
                    id         = 3
                    title      = "🔵 기압 (hPa)"
                    type       = "timeseries"
                    gridPos    = { x = 16, y = 0, w = 8, h = 8 }
                    datasource = { type = "grafana-athena-datasource", uid = "athena" }
                    fieldConfig = {
                      defaults = {
                        unit = "pressurehpa"
                        custom = {
                          lineWidth   = 2
                          fillOpacity = 15
                        }
                        color = {
                          mode       = "fixed"
                          fixedColor = "purple"
                        }
                      }
                    }
                    targets = [{
                      rawSQL = "SELECT timestamp AS time, value, sensor_id FROM stockops_sensor.sensor_data WHERE sensor_type='pressure' AND site_id LIKE '%$site_id%' AND year='2026' AND month='06' AND $__timeFilter(timestamp) ORDER BY time"
                      format = 1
                      refId  = "A"
                      connectionArgs = {
                        catalog  = "AwsDataCatalog"
                        database = "stockops_sensor"
                      }
                    }]
                  },
                  {
                    id         = 4
                    title      = "😷 PM2.5 (μg/m³)"
                    type       = "timeseries"
                    gridPos    = { x = 0, y = 8, w = 12, h = 8 }
                    datasource = { type = "grafana-athena-datasource", uid = "athena" }
                    fieldConfig = {
                      defaults = {
                        unit = "µg/m³"
                        custom = {
                          lineWidth   = 2
                          fillOpacity = 15
                        }
                        color = {
                          mode       = "fixed"
                          fixedColor = "orange"
                        }
                        thresholds = {
                          mode = "absolute"
                          steps = [
                            { color = "green", value = null },
                            { color = "yellow", value = 15 },
                            { color = "orange", value = 35 },
                            { color = "red", value = 75 }
                          ]
                        }
                      }
                    }
                    targets = [{
                      rawSQL = "SELECT timestamp AS time, value, sensor_id FROM stockops_sensor.sensor_data WHERE sensor_type='pm25' AND site_id LIKE '%$site_id%' AND year='2026' AND month='06' AND $__timeFilter(timestamp) ORDER BY time"
                      format = 1
                      refId  = "A"
                      connectionArgs = {
                        catalog  = "AwsDataCatalog"
                        database = "stockops_sensor"
                      }
                    }]
                  },
                  {
                    id         = 5
                    title      = "🌫️ PM10 (μg/m³)"
                    type       = "timeseries"
                    gridPos    = { x = 12, y = 8, w = 12, h = 8 }
                    datasource = { type = "grafana-athena-datasource", uid = "athena" }
                    fieldConfig = {
                      defaults = {
                        unit = "µg/m³"
                        custom = {
                          lineWidth   = 2
                          fillOpacity = 15
                        }
                        color = {
                          mode       = "fixed"
                          fixedColor = "yellow"
                        }
                        thresholds = {
                          mode = "absolute"
                          steps = [
                            { color = "green", value = null },
                            { color = "yellow", value = 30 },
                            { color = "orange", value = 80 },
                            { color = "red", value = 150 }
                          ]
                        }
                      }
                    }
                    targets = [{
                      rawSQL = "SELECT timestamp AS time, value, sensor_id FROM stockops_sensor.sensor_data WHERE sensor_type='pm10' AND site_id LIKE '%$site_id%' AND year='2026' AND month='06' AND $__timeFilter(timestamp) ORDER BY time"
                      format = 1
                      refId  = "A"
                      connectionArgs = {
                        catalog  = "AwsDataCatalog"
                        database = "stockops_sensor"
                      }
                    }]
                  },
                  {
                    id         = 6
                    title      = "🚪 도어 상태"
                    type       = "stat"
                    gridPos    = { x = 0, y = 16, w = 6, h = 4 }
                    datasource = { type = "grafana-athena-datasource", uid = "athena" }
                    fieldConfig = {
                      defaults = {
                        unit = "short"
                        mappings = [
                          { type = "value", options = { "0" = { text = "닫힘 🔒", color = "green" }, "1" = { text = "열림 🔓", color = "red" } } }
                        ]
                        thresholds = {
                          mode = "absolute"
                          steps = [
                            { color = "green", value = null },
                            { color = "red", value = 1 }
                          ]
                        }
                      }
                    }
                    options = {
                      textMode  = "value"
                      colorMode = "value"
                      text = {
                        valueSize = 36
                      }
                    }
                    targets = [{
                      rawSQL = "SELECT timestamp AS time, value, sensor_id FROM stockops_sensor.sensor_data WHERE sensor_type='door_open' AND site_id LIKE '%$site_id%' AND year='2026' AND month='06' ORDER BY time DESC LIMIT 1"
                      format = 0
                      refId  = "A"
                      connectionArgs = {
                        catalog  = "AwsDataCatalog"
                        database = "stockops_sensor"
                      }
                    }]
                  },
                  {
                    id         = 7
                    title      = "👤 재실 감지"
                    type       = "stat"
                    gridPos    = { x = 6, y = 16, w = 6, h = 4 }
                    datasource = { type = "grafana-athena-datasource", uid = "athena" }
                    fieldConfig = {
                      defaults = {
                        unit = "short"
                        mappings = [
                          { type = "value", options = { "0" = { text = "없음 ⬜", color = "blue" }, "1" = { text = "감지 🟢", color = "green" } } }
                        ]
                        thresholds = {
                          mode = "absolute"
                          steps = [
                            { color = "blue", value = null },
                            { color = "green", value = 1 }
                          ]
                        }
                      }
                    }
                    options = {
                      textMode  = "value"
                      colorMode = "value"
                      text = {
                        valueSize = 36
                      }
                    }
                    targets = [{
                      rawSQL = "SELECT timestamp AS time, value, sensor_id FROM stockops_sensor.sensor_data WHERE sensor_type='presence_detected' AND site_id LIKE '%$site_id%' AND year='2026' AND month='06' ORDER BY time DESC LIMIT 1"
                      format = 0
                      refId  = "A"
                      connectionArgs = {
                        catalog  = "AwsDataCatalog"
                        database = "stockops_sensor"
                      }
                    }]
                  }
                ]
              })
            }
          },
          applog-custom = {
            stockops-applog = {
              json = jsonencode({
                title         = "📜 StockOps 애플리케이션 로그"
                uid           = "stockops-applog-custom"
                timezone      = "Asia/Seoul"
                refresh       = "30s"
                schemaVersion = 38
                tags          = ["stockops", "logs", "application"]
                time = {
                  from = "now-1h"
                  to   = "now"
                }

                templating = {
                  list = [
                    {
                      name    = "search"
                      type    = "textbox"
                      label   = "🔍 검색어"
                      query   = ""
                      current = { text = "", value = "" }
                    },
                    {
                      name       = "level"
                      type       = "custom"
                      label      = "로그 레벨"
                      query      = "전체 : .*,INFO : INFO,WARN : WARN,ERROR : ERROR"
                      includeAll = false
                      multi      = false
                      current    = { text = "전체", value = ".*" }
                    },
                    {
                      name       = "region_target"
                      type       = "custom"
                      label      = "🌐 리전"
                      query      = "seoul-cluster : ap-northeast-2,ohio-cluster : us-east-2"
                      includeAll = false
                      multi      = false
                      current    = { text = "seoul-cluster", value = "ap-northeast-2" }
                    }
                  ]
                }

                panels = [
                  {
                    id         = 1
                    title      = "📋 API 로그 (stockops-api)"
                    type       = "logs"
                    gridPos    = { x = 0, y = 0, w = 24, h = 11 }
                    datasource = { type = "cloudwatch", uid = "cloudwatch" }
                    options = {
                      showTime       = true
                      wrapLogMessage = true
                      sortOrder      = "Descending"
                    }
                    targets = [
                      {
                        refId         = "A"
                        region        = "$region_target"
                        logGroupNames = ["/aws/eks/$${region_target:text}/stockops/api"]
                        queryMode     = "Logs"
                        expression    = "fields @timestamp, @message | filter @message like /$level/ and @message like /$search/ | sort @timestamp desc | limit 100"
                      }
                    ]
                  },
                  {
                    id         = 2
                    title      = "🤖 AI 로그 (stockops-ai)"
                    type       = "logs"
                    gridPos    = { x = 0, y = 11, w = 24, h = 11 }
                    datasource = { type = "cloudwatch", uid = "cloudwatch" }
                    options = {
                      showTime       = true
                      wrapLogMessage = true
                      sortOrder      = "Descending"
                    }
                    targets = [
                      {
                        refId         = "A"
                        region        = "$region_target"
                        logGroupNames = ["/aws/eks/$${region_target:text}/stockops/ai"]
                        queryMode     = "Logs"
                        expression    = "fields @timestamp, @message | filter @message like /$level/ and @message like /$search/ | sort @timestamp desc | limit 100"
                      }
                    ]
                  },
                  {
                    id         = 3
                    title      = "⚠️ API 경고/에러 (WARN / ERROR)"
                    type       = "logs"
                    gridPos    = { x = 0, y = 22, w = 24, h = 10 }
                    datasource = { type = "cloudwatch", uid = "cloudwatch" }
                    options = {
                      showTime       = true
                      wrapLogMessage = true
                      sortOrder      = "Descending"
                    }
                    targets = [
                      {
                        refId         = "A"
                        region        = "$region_target"
                        logGroupNames = ["/aws/eks/$${region_target:text}/stockops/api"]
                        queryMode     = "Logs"
                        expression    = "fields @timestamp, @message | filter @message like /WARN|ERROR/ and @message like /$search/ | sort @timestamp desc | limit 100"
                      }
                    ]
                  }
                ]
              })
            }
          },
          appmetric-custom = {
            stockops-appmetric = {
              json = jsonencode({
                title         = "📈 StockOps 애플리케이션 메트릭"
                uid           = "stockops-appmetric-custom"
                timezone      = "Asia/Seoul"
                refresh       = "30s"
                schemaVersion = 38
                tags          = ["stockops", "metrics", "application"]
                time = {
                  from = "now-30m"
                  to   = "now"
                }

                templating = {
                  list = [
                    {
                      name       = "region"
                      type       = "custom"
                      label      = "🌐 리전"
                      query      = "서울 : seoul,미국(오하이오) : ohio"
                      includeAll = false
                      multi      = false
                      current    = { text = "서울", value = "seoul" }
                    }
                  ]
                }

                panels = [
                  {
                    id         = 1
                    title      = "🚀 API 처리량 (req/s)"
                    type       = "timeseries"
                    gridPos    = { x = 0, y = 0, w = 12, h = 7 }
                    datasource = { type = "prometheus", uid = "prometheus" }
                    fieldConfig = {
                      defaults = {
                        unit = "reqps"
                        custom = {
                          lineWidth   = 2
                          fillOpacity = 15
                        }
                      }
                    }
                    options = {
                      legend = {
                        displayMode = "table"
                        placement   = "right"
                        calcs       = ["lastNotNull", "max"]
                      }
                    }
                    targets = [{
                      expr         = "sum(rate(http_server_requests_seconds_count{application=\"stockops\"}[1m])) by (method)"
                      legendFormat = "{{method}}"
                    }]
                  },
                  {
                    id         = 2
                    title      = "❌ 에러율 (%)"
                    type       = "timeseries"
                    gridPos    = { x = 12, y = 0, w = 12, h = 7 }
                    datasource = { type = "prometheus", uid = "prometheus" }
                    fieldConfig = {
                      defaults = {
                        unit = "percent"
                        min  = 0
                        custom = {
                          lineWidth   = 2
                          fillOpacity = 15
                        }
                        thresholds = {
                          mode = "absolute"
                          steps = [
                            { color = "green", value = null },
                            { color = "yellow", value = 1 },
                            { color = "red", value = 5 }
                          ]
                        }
                      }
                    }
                    targets = [{
                      expr         = "sum(rate(http_server_requests_seconds_count{application=\"stockops\",status=~\"5..\"}[1m])) / sum(rate(http_server_requests_seconds_count{application=\"stockops\"}[1m])) * 100 or vector(0)"
                      legendFormat = "5xx 에러율"
                    }]
                  },
                  {
                    id         = 3
                    title      = "⏱️ 평균 응답시간"
                    type       = "timeseries"
                    gridPos    = { x = 0, y = 7, w = 12, h = 7 }
                    datasource = { type = "prometheus", uid = "prometheus" }
                    fieldConfig = {
                      defaults = {
                        unit = "s"
                        custom = {
                          lineWidth   = 2
                          fillOpacity = 15
                        }
                        thresholds = {
                          mode = "absolute"
                          steps = [
                            { color = "green", value = null },
                            { color = "yellow", value = 0.5 },
                            { color = "red", value = 1 }
                          ]
                        }
                      }
                    }
                    options = {
                      legend = {
                        displayMode = "table"
                        placement   = "right"
                        calcs       = ["lastNotNull", "max"]
                      }
                    }
                    targets = [{
                      expr         = "sum(rate(http_server_requests_seconds_sum{application=\"stockops\"}[1m])) by (uri) / sum(rate(http_server_requests_seconds_count{application=\"stockops\"}[1m])) by (uri)"
                      legendFormat = "{{uri}}"
                    }]
                  },
                  {
                    id         = 4
                    title      = "🧠 JVM 힙 메모리"
                    type       = "timeseries"
                    gridPos    = { x = 12, y = 7, w = 12, h = 7 }
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
                    options = {
                      legend = {
                        displayMode = "table"
                        placement   = "right"
                        calcs       = ["lastNotNull", "max"]
                      }
                    }
                    targets = [
                      {
                        expr         = "sum(jvm_memory_used_bytes{application=\"stockops\",area=\"heap\"})"
                        legendFormat = "사용 중"
                      },
                      {
                        expr         = "sum(jvm_memory_committed_bytes{application=\"stockops\",area=\"heap\"})"
                        legendFormat = "할당됨"
                      }
                    ]
                  },
                  {
                    id         = 5
                    title      = "🗄️ DB 커넥션 풀 (HikariCP)"
                    type       = "timeseries"
                    gridPos    = { x = 0, y = 14, w = 12, h = 7 }
                    datasource = { type = "prometheus", uid = "prometheus" }
                    fieldConfig = {
                      defaults = {
                        unit = "short"
                        custom = {
                          lineWidth   = 2
                          fillOpacity = 15
                        }
                      }
                    }
                    options = {
                      legend = {
                        displayMode = "table"
                        placement   = "right"
                        calcs       = ["lastNotNull", "max"]
                      }
                    }
                    targets = [
                      {
                        expr         = "sum(hikaricp_connections_active{application=\"stockops\"})"
                        legendFormat = "활성"
                      },
                      {
                        expr         = "sum(hikaricp_connections_idle{application=\"stockops\"})"
                        legendFormat = "유휴"
                      },
                      {
                        expr         = "sum(hikaricp_connections_pending{application=\"stockops\"})"
                        legendFormat = "대기"
                      }
                    ]
                  },
                  {
                    id         = 6
                    title      = "🔌 Bedrock 회로차단기 상태"
                    type       = "stat"
                    gridPos    = { x = 12, y = 14, w = 12, h = 7 }
                    datasource = { type = "prometheus", uid = "prometheus" }
                    fieldConfig = {
                      defaults = {
                        unit = "short"
                        mappings = [
                          { type = "value", options = {
                            "0" = { text = "정상 (닫힘)", color = "green" },
                            "1" = { text = "차단 (열림)", color = "red" }
                          } }
                        ]
                        thresholds = {
                          mode = "absolute"
                          steps = [
                            { color = "green", value = null }
                          ]
                        }
                      }
                    }
                    options = {
                      textMode  = "value"
                      colorMode = "value"
                      graphMode = "none"
                      text = {
                        valueSize = 28
                      }
                    }
                    targets = [
                      {
                        expr         = "resilience4j_circuitbreaker_state{application=\"stockops\",name=\"bedrock\",state=\"open\"}"
                        legendFormat = "상태"
                        instant      = true
                      }
                    ]
                  },
                  {
                    id         = 7
                    title      = "🤖 AI 예측 처리량 (req/s)"
                    type       = "timeseries"
                    gridPos    = { x = 0, y = 21, w = 12, h = 7 }
                    datasource = { type = "prometheus", uid = "prometheus" }
                    fieldConfig = {
                      defaults = {
                        unit = "reqps"
                        custom = {
                          lineWidth   = 2
                          fillOpacity = 15
                        }
                      }
                    }
                    options = {
                      legend = {
                        displayMode = "table"
                        placement   = "right"
                        calcs       = ["lastNotNull", "max"]
                      }
                    }
                    targets = [{
                      expr         = "sum(rate(ai_forecast_requests_total[5m])) by (outcome) or vector(0)"
                      legendFormat = "{{outcome}}"
                    }]
                  },
                  {
                    id         = 8
                    title      = "🤖 AI 예측 지연 p95"
                    type       = "timeseries"
                    gridPos    = { x = 12, y = 21, w = 12, h = 7 }
                    datasource = { type = "prometheus", uid = "prometheus" }
                    fieldConfig = {
                      defaults = {
                        unit = "s"
                        custom = {
                          lineWidth   = 2
                          fillOpacity = 15
                        }
                        thresholds = {
                          mode = "absolute"
                          steps = [
                            { color = "green", value = null },
                            { color = "yellow", value = 2 },
                            { color = "red", value = 5 }
                          ]
                        }
                      }
                    }
                    targets = [{
                      expr         = "histogram_quantile(0.95, sum(rate(ai_forecast_duration_seconds_bucket[5m])) by (le))"
                      legendFormat = "p95"
                    }]
                  },
                  {
                    id         = 9
                    title      = "🤖 모델 캐시 적중률 (%)"
                    type       = "timeseries"
                    gridPos    = { x = 0, y = 28, w = 12, h = 7 }
                    datasource = { type = "prometheus", uid = "prometheus" }
                    fieldConfig = {
                      defaults = {
                        unit = "percent"
                        min  = 0
                        max  = 100
                        custom = {
                          lineWidth   = 2
                          fillOpacity = 15
                        }
                      }
                    }
                    targets = [{
                      expr         = "sum(increase(ai_model_cache_events_total{result=\"hit\"}[10m])) / sum(increase(ai_model_cache_events_total[10m])) * 100 or vector(0)"
                      legendFormat = "캐시 적중률"
                    }]
                  },
                  {
                    id         = 10
                    title      = "🤖 예측 정확도 MAPE (%)"
                    type       = "stat"
                    gridPos    = { x = 12, y = 28, w = 12, h = 7 }
                    datasource = { type = "prometheus", uid = "prometheus" }
                    fieldConfig = {
                      defaults = {
                        unit     = "percent"
                        decimals = 1
                        thresholds = {
                          mode = "absolute"
                          steps = [
                            { color = "green", value = null },
                            { color = "yellow", value = 20 },
                            { color = "red", value = 50 }
                          ]
                        }
                      }
                    }
                    options = {
                      colorMode = "value"
                      text      = { valueSize = 28 }
                    }
                    targets = [{
                      expr    = "sum(ai_evaluation_mape_percent_sum) / sum(ai_evaluation_mape_percent_count)"
                      instant = true
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
            smtp_smarthost     = "smtp.gmail.com:587"
            smtp_from          = "bljh5220@gmail.com"
            smtp_auth_username = "bljh5220@gmail.com"
            smtp_auth_password = var.gmail_app_password
            smtp_require_tls   = true
          }
          route = {
            group_by        = ["alertname", "instance"]
            group_wait      = "30s"
            group_interval  = "5m"
            repeat_interval = "12h"
            receiver        = "blackhole"
            routes = [
              {
                match_re = { alertname = "PodFailed|PodRestartHigh|NodeCPUHigh|NodeMemoryHigh" }
                receiver = "gmail"
              }
            ]
          }
          receivers = [
            {
              name = "blackhole"
            },
            {
              name = "gmail"
              email_configs = [
                {
                  to            = "bljh5220@gmail.com"
                  send_resolved = true
                }
              ]
            }
          ]
        }
      }

      additionalPrometheusRulesMap = {
        stockops-alerts = {
          groups = [
            {
              name = "stockops.pod"
              rules = [
                {
                  alert  = "PodFailed"
                  expr   = "count(kube_pod_status_phase{phase='Failed', namespace='stockops'} == 1) > 0 or count(kube_pod_container_status_waiting_reason{reason='ImagePullBackOff', namespace='stockops'} == 1) > 0"
                  for    = "1m"
                  labels = { severity = "critical" }
                  annotations = {
                    summary     = "StockOps Pod 장애 발생"
                    description = "stockops 네임스페이스에 Failed Pod가 있습니다."
                  }
                },
                {
                  alert  = "PodRestartHigh"
                  expr   = "sum(kube_pod_container_status_restarts_total{namespace='stockops'}) by (pod) > 3"
                  for    = "1m"
                  labels = { severity = "warning" }
                  annotations = {
                    summary     = "Pod 재시작 횟수 초과"
                    description = "{{ $labels.pod }} Pod가 3회 이상 재시작했습니다."
                  }
                }
              ]
            },
            {
              name = "stockops.node"
              rules = [
                {
                  alert  = "NodeCPUHigh"
                  expr   = "100 - (avg by(instance) (irate(node_cpu_seconds_total{mode='idle'}[5m])) * 100) > 80"
                  for    = "3m"
                  labels = { severity = "critical" }
                  annotations = {
                    summary     = "노드 CPU 과부하"
                    description = "{{ $labels.instance }} 노드 CPU가 80%를 초과했습니다."
                  }
                },
                {
                  alert  = "NodeMemoryHigh"
                  expr   = "100 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes * 100) > 85"
                  for    = "3m"
                  labels = { severity = "critical" }
                  annotations = {
                    summary     = "노드 메모리 과부하"
                    description = "{{ $labels.instance }} 노드 메모리가 85%를 초과했습니다."
                  }
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

# 그라파나 전용 IAM Role (IRSA)
resource "aws_iam_role" "grafana_athena_role" {
  name = "seoul-grafana-athena-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = "arn:aws:iam::448768137813:oidc-provider/${local.eks_oidc_issuer}"
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.eks_oidc_issuer}:sub" = "system:serviceaccount:monitoring:grafana-athena-sa"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "grafana_athena" {
  role       = aws_iam_role.grafana_athena_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonAthenaFullAccess"
}

resource "aws_iam_role_policy_attachment" "grafana_glue" {
  role       = aws_iam_role.grafana_athena_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSGlueConsoleFullAccess"
}

resource "aws_iam_role_policy_attachment" "grafana_s3" {
  role       = aws_iam_role.grafana_athena_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

resource "aws_iam_role_policy_attachment" "grafana_cloudwatch_logs" {
  role       = aws_iam_role.grafana_athena_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsReadOnlyAccess"
}