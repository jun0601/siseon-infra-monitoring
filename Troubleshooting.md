# 🔧 트러블슈팅 기록

> siseon-infra-monitoring 구성 과정에서 발생한 문제와 해결 방법을 기록합니다.

---

## 1. Grafana CrashLoopBackOff

### 증상
```
kube-prometheus-stack-grafana   2/3   CrashLoopBackOff
```

### 원인
kube-prometheus-stack은 기본적으로 Prometheus 데이터소스를 자동 등록합니다.
커스텀 datasources.yaml에서도 Prometheus를 `isDefault: true`로 설정하면
**동일 조직에 default 데이터소스가 2개**가 되어 Grafana가 시작 시 오류로 종료됩니다.

```
Datasource provisioning error: datasource.yaml config is invalid.
Only one datasource per organization can be marked as default
```

### 해결
sidecar 설정으로 차트 기본 데이터소스 자동 등록을 비활성화합니다.

```hcl
sidecar = {
  datasources = {
    defaultDatasourceEnabled = false
  }
}
```

### 교훈
kube-prometheus-stack 사용 시 커스텀 데이터소스를 추가할 경우
반드시 `defaultDatasourceEnabled = false` 설정이 필요합니다.

---

## 2. LoadBalancer EXTERNAL-IP Pending

### 증상
```
NAME                            TYPE           CLUSTER-IP    EXTERNAL-IP   PORT(S)
kube-prometheus-stack-grafana   LoadBalancer   172.20.x.x    <pending>     80:xxxxx/TCP
```

### 원인
AWS Load Balancer Controller가 NLB를 생성하려면
VPC 서브넷에 특정 태그가 있어야 합니다.
팀 인프라의 VPC 모듈에 해당 태그가 누락되어 있었습니다.

### 해결
팀 인프라 `modules/vpc/main.tf` 서브넷 태그 추가:

```hcl
# 퍼블릭 서브넷
tags = {
  Name                                  = "${var.region_name}-pub-sub-2a"
  "kubernetes.io/role/elb"              = "1"
  "kubernetes.io/cluster/seoul-cluster" = "shared"
}

# 프라이빗 앱 서브넷
tags = {
  Name                                  = "${var.region_name}-priv-app-2a"
  "kubernetes.io/role/internal-elb"     = "1"
  "kubernetes.io/cluster/seoul-cluster" = "shared"
}
```

### 교훈
EKS + AWS Load Balancer Controller 환경에서는
VPC 구성 시 서브넷 태그를 반드시 사전에 설정해야 합니다.
이는 LBC가 퍼블릭/프라이빗 서브넷을 식별하는 유일한 방법입니다.

---

## 3. NLB internal로 생성됨 (외부 접속 불가)

### 증상
NLB가 생성됐지만 외부에서 접속이 되지 않습니다.
LBC 로그에서 `scheme: internal` 확인:

```json
{"scheme":"internal","subnetMapping":[{"subnetID":"subnet-04a71..."}]}
```

### 원인
서브넷 태그 추가 후 LBC가 퍼블릭/프라이빗 서브넷을 구분할 수 있게 되면서
명시적 scheme 지정이 없으면 **프라이빗 서브넷에 internal NLB**를 생성합니다.

### 해결
service annotation에 `internet-facing` 명시:

```hcl
service = {
  type = "LoadBalancer"
  annotations = {
    "service.beta.kubernetes.io/aws-load-balancer-scheme" = "internet-facing"
  }
}
```

### 교훈
AWS Load Balancer Controller 사용 시 외부 노출이 필요한 서비스는
반드시 `internet-facing` annotation을 명시해야 합니다.
서브넷 태그가 없을 때는 기본값으로 동작하지만,
태그 추가 후에는 LBC의 서브넷 선택 로직이 변경됩니다.

---

## 4. LBC IAM 권한 부족

### 증상
```json
{
  "level": "error",
  "error": "AccessDenied: User is not authorized to perform:
  elasticloadbalancing:DescribeListenerAttributes"
}
```

### 원인
팀 인프라의 LBC IAM 정책(`lbc-iam-policy.json`)에
`DescribeListenerAttributes` 권한이 누락되어 있었습니다.

### 해결
`modules/eks/lbc-iam-policy.json`에 권한 추가:

```json
{
  "Effect": "Allow",
  "Action": [
    "elasticloadbalancing:DescribeListenerAttributes",
    "elasticloadbalancing:ModifyListenerAttributes"
  ],
  "Resource": "*"
}
```

### 교훈
LBC 버전 업데이트에 따라 필요한 IAM 권한이 변경될 수 있습니다.
LBC 공식 문서의 IAM 정책을 주기적으로 확인하고 최신 버전을 유지해야 합니다.

---

## 5. Helm Release 실패 후 재배포 불가

### 증상
```
Error: failed to refresh resource information: services "kube-prometheus-stack-grafana" not found
```

### 원인
`terraform apply` timeout 또는 오류로 Helm release가 실패 상태로 남아있을 때,
Terraform state에는 release가 존재하는 것으로 기록되어
재배포 시 충돌이 발생합니다.

### 해결
```bash
# 1. Helm release 삭제
helm uninstall kube-prometheus-stack -n monitoring

# 2. Terraform state에서 제거
terraform state rm helm_release.kube_prometheus_stack

# 3. 재배포
terraform apply
```

### 교훈
Helm + Terraform 환경에서 배포 실패 시
반드시 Helm과 Terraform state를 모두 정리해야 합니다.
`terraform destroy`만으로는 Helm release가 완전히 제거되지 않을 수 있습니다.

---

## 6. context deadline exceeded (Timeout)

### 증상
```
Error: context deadline exceeded
with helm_release.kube_prometheus_stack
```

### 원인
kube-prometheus-stack은 Prometheus CRD, 각종 RBAC, 여러 Pod를 한 번에 설치합니다.
t3.medium(2vCPU, 4GB) 노드 2개 환경에서 기본 timeout(300초)이 부족했습니다.

### 해결
```hcl
resource "helm_release" "kube_prometheus_stack" {
  timeout = 900  # 기본 300 → 900으로 증가
}
```

### 교훈
kube-prometheus-stack은 설치할 컴포넌트가 많아 시간이 오래 걸립니다.
노드 스펙이 낮을수록 timeout을 넉넉히 설정해야 합니다.
실제 배포 환경(운영)에서는 노드 스펙 업그레이드를 권장합니다.

---

## 7. SSO 토큰 만료

### 증상
```
Error: No valid credential sources found
failed to refresh cached credentials, unable to refresh SSO token
```

### 원인
AWS SSO 임시 토큰의 유효 기간이 만료됩니다. (기본 8시간)

### 해결
```bash
aws sso login --profile siseon
```

### 교훈
장시간 작업 시 SSO 토큰 만료에 주의해야 합니다.
`terraform apply` 전 항상 토큰 유효성을 확인하는 습관이 필요합니다.

---

## 8. Failed/Pending Pods 대시보드 오류 집계

### 증상
kubectl get pods 에서 모두 Running인데 대시보드에 Failed 5, Pending 29 표시

### 원인
PromQL이 현재 상태가 아닌 과거 이벤트까지 집계
- Pending: 네임스페이스 필터 없어서 전체 클러스터 집계
- Failed: 배포 시 순간적으로 Failed 거치는 Pod까지 집계

### 해결
```promql
# Pending - stockops 네임스페이스 + 현재 상태만
count(kube_pod_status_phase{phase='Pending', namespace='stockops'} == 1) or vector(0)

# Failed - stockops 네임스페이스 + 현재 상태만
count(kube_pod_status_phase{phase='Failed', namespace='stockops'} == 1) or vector(0)
```

### 교훈
kube_pod_status_phase는 모든 phase 상태를 동시에 가지고 있어 `== 1` 조건으로 현재 상태만 필터링해야 합니다.

---

## 9. Alertmanager 미생성 (enabled = true인데 Pod 없음)

### 증상

kubectl get pods -n monitoring
→ alertmanager Pod 없음

### 원인
`additionalPrometheusRulesMap`이 `alertmanagerSpec` 안에 잘못 배치되어 Helm이 인식 못함
`email_configs`의 `subject`, `body` 필드가 yamlencode 변환 시 Alertmanager YAML 형식과 불일치

### 해결
1. `additionalPrometheusRulesMap`을 `alertmanager` 블록과 같은 레벨로 분리
2. `email_configs`에서 `subject`, `body` 제거 후 기본 포맷 사용

### 교훈
kube-prometheus-stack Helm values에서 `additionalPrometheusRulesMap`은 최상위 레벨에 위치해야 합니다.
Terraform `yamlencode` 사용 시 Alertmanager YAML 스펙과 필드명이 정확히 일치해야 합니다.

---

## 10. EKS 노이즈 알람 (KubeSchedulerDown 등)

### 증상
[FIRING] KubeSchedulerDown
[FIRING] KubeControllerManagerDown

### 원인
EKS는 컨트롤 플레인(스케줄러, 컨트롤러 매니저)이 AWS 관리라 Prometheus가 메트릭을 수집할 수 없음
kube-prometheus-stack 기본 알람 룰이 이를 장애로 판단하여 알람 발송

### 해결
기본 receiver를 `blackhole`로 설정하고 필요한 알람만 gmail로 라우팅:
```hcl
route = {
  receiver = "blackhole"
  routes = [
    {
      match_re = { alertname = "PodFailed|PodRestartHigh|NodeCPUHigh|NodeMemoryHigh" }
      receiver = "gmail"
    }
  ]
}
receivers = [
  { name = "blackhole" },
  { name = "gmail", email_configs = [...] }
]
```

### 교훈
EKS 환경에서 kube-prometheus-stack 사용 시 컨트롤 플레인 관련 기본 알람은 반드시 억제해야 합니다.


## 📋 트러블슈팅 요약

| # | 문제 | 원인 | 해결 |
|---|------|------|------|
| 1 | Grafana CrashLoopBackOff | 데이터소스 default 중복 | sidecar defaultDatasourceEnabled = false |
| 2 | LoadBalancer pending | 서브넷 태그 누락 | VPC 서브넷에 K8s 태그 추가 |
| 3 | NLB internal 생성 | scheme 미지정 | internet-facing annotation 추가 |
| 4 | LBC IAM 권한 부족 | DescribeListenerAttributes 누락 | lbc-iam-policy.json 권한 추가 |
| 5 | Helm 재배포 불가 | state 충돌 | helm uninstall + terraform state rm |
| 6 | context deadline exceeded | timeout 부족 | timeout = 900 설정 |
| 7 | SSO 토큰 만료 | 토큰 유효기간 초과 | aws sso login 재실행 |
| 8 | Failed/Pending 오류 집계 | 네임스페이스 필터 + 현재 상태 필터 누락 | == 1 조건 + namespace 필터 추가 |
| 9 | Alertmanager Pod 미생성 | additionalPrometheusRulesMap 위치 오류 + email 필드 불일치 | 레벨 분리 + subject/body 제거 |
| 10 | EKS 노이즈 알람 | 컨트롤 플레인 메트릭 수집 불가 | blackhole receiver + 필요 알람만 라우팅 |