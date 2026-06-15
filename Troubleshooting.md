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


## 11. ServiceMonitor가 Service를 못 찾음 (Service 라벨 누락)

### 증상
ServiceMonitor를 배포했는데 Prometheus Targets에 stockops-api가 나타나지 않음.
ServiceMonitor 리소스 자체는 정상 등록(`kubectl get servicemonitor`)되어 있음.

### 원인
ServiceMonitor는 `selector.matchLabels`로 **대상 Service를 라벨로 찾는다.** 그런데 팀 인프라의
Service 정의에 라벨이 없어(`kubectl get svc --show-labels` → `<none>`) 매칭이 실패했다.
Deployment에는 `app` 라벨이 있었지만, ServiceMonitor가 보는 것은 **Service 메타데이터의 라벨**이다.

### 해결
Service 정의(`seoul/kubernetes.tf`)의 metadata에 라벨 추가 (팀 인프라 담당에게 요청):

```hcl
metadata {
  name   = "stockops-api-svc"
  labels = { app = "stockops-api" }   # ← ServiceMonitor 셀렉터가 찾는 라벨
}
```

### 교훈
ServiceMonitor의 매칭 기준은 Pod/Deployment 라벨이 아니라 **Service 자체의 라벨**이다.
앱 배포(Service)와 모니터링(ServiceMonitor)이 다른 레포로 분리된 경우, Service 라벨 규약을
사전에 합의해야 한다.

## 12. ServiceMonitor CRD 미존재로 apply 실패 (클린 배포)

### 증상
```
Error: API did not recognize GroupVersionKind from manifest (CRD may not be installed)
no matches for kind "ServiceMonitor" in group "monitoring.coreos.com"
```

### 원인
`kubernetes_manifest`는 **plan 시점에 해당 CRD가 클러스터에 이미 존재해야** 한다.
클러스터를 새로 만든 직후엔 kube-prometheus-stack(ServiceMonitor CRD 생성)이 아직 안 깔려서,
ServiceMonitor를 같은 apply에서 plan하려다 "kind를 모른다"고 실패한다. `depends_on`을 걸어도
plan 단계라 해결되지 않는다.

### 해결
CRD를 먼저 생성하는 2단계 apply:

```bash
# 1단계: Helm(=CRD)만 먼저
terraform apply -target=helm_release.kube_prometheus_stack

# 2단계: 전체 (CRD 생겼으니 ServiceMonitor 인식)
terraform apply
```

클러스터/CRD가 살아있는 상태에서 monitoring만 내렸다 올릴 때는 1단계가 필요 없다(딸깍 1번).
영구적으로 1단계로 만들려면 ServiceMonitor를 Helm values의 `additionalServiceMonitors`로
옮기면 되지만, 파일 분리를 포기하게 된다.

### 교훈
`kubernetes_manifest`로 CRD 기반 리소스(ServiceMonitor 등)를 만들 땐 CRD 선행 생성이 필수다.
클린 배포와 부분 재배포의 절차가 다르다는 점을 운영 문서에 명시해야 한다.

## 13. ServiceMonitor 포트 이름 매칭 실패

### 증상
Service 라벨을 붙였는데도 Prometheus가 스크랩하지 못함.

### 원인
ServiceMonitor의 endpoint에서 포트를 **이름(`port: http`)으로 지정**했는데, 대상 Service의
포트 정의에 `name`이 없어서 "http"라는 이름의 포트를 찾지 못했다.

### 해결
ServiceMonitor에서 포트를 숫자(`targetPort: 8080`)로 지정하거나, Service 포트에 `name = "http"`를
추가한다. 후자가 표준적이라 Service 포트에 이름을 부여하고 ServiceMonitor는 `port: http`를 쓰는
방식으로 통일했다.

### 교훈
ServiceMonitor의 `port`(이름 기반)와 `targetPort`(숫자 기반)는 다르다. 이름으로 매칭하려면
Service 포트에 반드시 `name`이 있어야 한다.


## 14. Prometheus OOMKilled 크래시 루프 (전 패널 No data / connection refused)

### 증상
Grafana 전 패널 No data. 패널 edit 시 `Post "http://kube-prometheus-stack-prometheus:9090/...": connect: connection refused`.

### 원인
데이터소스 URL·설정은 정상. Prometheus 컨테이너가 메모리 limit(512Mi)을 초과해 반복 `OOMKilled`(exitCode 137) → 크래시 루프. 죽었다 뜨는 BackOff 구간에 9090 포트가 connection refused라, 그 순간 Grafana 쿼리가 실패한 것. WAF 대시보드·멀티리전 로그/추적 누적 + api 부하 트래픽으로 시계열 카디널리티(uri `/**`, status별)가 늘며 512Mi를 넘김.

### 해결
`prometheus.prometheusSpec.resources` 메모리 상향 (노드 t3.medium 4Gi라 수용 가능):
```hcl
limits   = { memory = "1.5Gi", cpu = "500m" }   # 512Mi → 1.5Gi
requests = { memory = "768Mi", cpu = "100m" }   # 256Mi → 768Mi
```
적용 후 RESTARTS 0 유지, 9090 Ready, 타겟 up 확인 → Grafana 데이터소스 자동 복구.

### 교훈
전 패널 No data + connection refused면 데이터소스 설정보다 **Prometheus 파드 안정성(RESTARTS/OOMKilled)**을 먼저 의심해야 한다. request는 limit의 절반쯤으로 함께 올려 스케줄러가 빠듯한 노드에 배치해 또 OOM 나는 것을 막는다.

---

## 15. api 메트릭 패널 전체 No data (`/actuator/prometheus` 401)

### 증상
앱 재배포 후 앱 메트릭 대시보드 api 6패널 전부 No data. ai 패널은 정상.

### 원인
Prometheus 타겟 `serviceMonitor/monitoring/stockops-api/0`가 `health=down`, `lastError = server returned HTTP status 401`. api(Spring) `/actuator/prometheus`가 인증에 막혀 스크랩 거부. ai 타겟은 up이라 대시보드/ServiceMonitor 문제가 아닌 수집 경로 차단(회귀). api `SecurityConfig`는 `stockops.actuator.prometheus-public=true`일 때만 이 경로를 permitAll 하는데, 재배포 파드에 이 값이 없어 기본값 false → 401.

### 해결
인프라 레포(`seoul/kubernetes.tf`) api 컨테이너 env에 한 줄 추가(진우 영역):
```hcl
env {
  name  = "STOCKOPS_ACTUATOR_PROMETHEUS_PUBLIC"
  value = "true"
}
```
> Spring Boot relaxed binding으로 `stockops.actuator.prometheus-public` 프로퍼티가 env `STOCKOPS_ACTUATOR_PROMETHEUS_PUBLIC`에 매핑된다. 적용 후 타겟 up → 부하 주면 api 6패널 채워짐.

### 교훈
대시보드가 비었을 때 "트래픽 없음"으로 단정하지 말 것. Prometheus 타겟 `health`/`lastError`를 먼저 봐야 한다 — 수집이 끊긴(401/down) 상태면 부하를 줘도 메모리에만 쌓이고 대시보드엔 안 뜬다.

---

## 16. ai 캐시 적중률 패널 0%/NaN (increase 윈도우 문제)

### 증상
모델 캐시 적중률 패널이 0%로 깔림 (그런데 예측 지연은 500→200ms로 떨어져 캐시가 실제 동작 중).

### 원인
메트릭(`ai_model_cache_events_total{result="hit"}=40, miss=1`, 실적중률 97.56%)은 정상. 패널 PromQL이 `increase([10m])`를 써서, 부하가 최근 10분보다 전에 끝나면 분자·분모 둘 다 0 → `0/0 = NaN`. `or vector(0)`는 빈 벡터만 0으로 치환하고 NaN은 그대로 둬서 No data/0% 표시.

### 해결
누적 비율 쿼리로 변경:
```promql
sum(ai_model_cache_events_total{result="hit"}) / sum(ai_model_cache_events_total) * 100 or vector(0)
```
idle 구간에도 누적 적중률(~97%)이 유지됨.

### 교훈
적중률·비율 패널에 `increase([window])`를 쓰면 트래픽 없는 구간에 0/0=NaN이 된다. 데모/저빈도 환경에선 누적 합(`sum`) 비율이 안정적이다. (단 카운터라 파드 재시작 시 리셋됨)

> **참고 — MAPE 패널 No data**: `ai_evaluation_mape_percent_count=0`. 평가 이벤트(실측 vs 예측 비교) 자체가 발생 안 함 → 데이터 문제(쿼리 무관). generate(미래 예측)로는 안 채워지며, 별도 모델 평가/백테스트 경로가 호출돼야 한다(앱 영역). 측정 메트릭·패널은 구축돼 있어 평가 데이터 축적 시 자동 표시된다.

---

## 17. WAF 보안 대시보드 — count vs block 분리

### 증상
WAF 로그를 단순히 `action=BLOCK`만 집계하니 SQLi/XSS 공격 시도가 대시보드에서 안 잡힘.

### 원인
진우 인프라의 WAF는 운영 안전을 위해 대부분 룰이 관찰(count) 모드. SQLi/CommonRuleSet(XSS)은 count라 로그에 `action=ALLOW`로 찍힘 → BLOCK만 세면 공격이 안 보임. 실제 BLOCK은 KnownBadInputs 정도.

### 해결
패널을 두 축으로 분리:
- **차단(BLOCK)** — `filter action="BLOCK"` 룰별 집계 (실제 막은 것)
- **탐지(count)** — `awswaf:managed` 라벨 파싱으로 ALLOW로 통과된 공격 시도까지 집계

상단에 총 차단/총 탐지/공격 소스 IP 수 stat 3종, 하단에 각각의 룰별·IP별 상세 테이블 3종을 stat↔테이블 1:1 대응으로 배치. 리전 드롭다운(서울 ALB/오하이오 ALB/CloudFront)은 로그그룹 패턴이 제각각이라 풀네임을 직접 나열. 새 폴더 `🛡️ 보안 모니터링`에 위치(주제는 보안이나 Grafana 대시보드라 monitoring 레포 관리).

### 교훈
WAF 대시보드는 룰이 차단 모드인지 관찰 모드인지를 먼저 이해하고, '막은 것(block)'과 '들어온 것(count)'을 분리해야 한다. count 모드 공격은 ALLOW로 찍히므로 라벨(`awswaf:managed`) 기반으로 탐지해야 누락되지 않는다.

---

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
| 11 | ServiceMonitor가 Service 못 찾음 | Service 메타데이터에 라벨 누락 | Service metadata에 app 라벨 추가 |
| 12 | ServiceMonitor CRD 미존재 apply 실패 | kubernetes_manifest는 plan 시 CRD 필요 | Helm(CRD) 먼저 -target apply 후 전체 apply |
| 13 | ServiceMonitor 포트 매칭 실패 | port 이름(http)에 대응하는 Service 포트 name 없음 | targetPort 숫자 지정 또는 Service 포트에 name 부여 |
| 14 | 전 패널 No data (connection refused) | Prometheus OOMKilled 크래시 루프 | 메모리 limit 512Mi→1.5Gi 상향 |
| 15 | api 메트릭 패널 전체 No data | `/actuator/prometheus` 401 (수집 차단) | api env `STOCKOPS_ACTUATOR_PROMETHEUS_PUBLIC=true` 추가 |
| 16 | ai 캐시 적중률 0%/NaN | increase([10m]) idle 구간 0/0=NaN | 누적 비율 `sum(hit)/sum(total)` 쿼리로 변경 |
| 17 | WAF 공격이 대시보드에 안 잡힘 | count 모드 룰은 ALLOW로 찍힘 | 차단(BLOCK)/탐지(managed 라벨) 패널 분리 |