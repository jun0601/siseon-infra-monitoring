# 📊 Siseon Infra Monitoring

> **StockOps ERP** 하이브리드 멀티클라우드 프로젝트의 인프라 모니터링 구성  
> Amazon EKS 클러스터의 Pod/Node 메트릭을 Prometheus로 수집하고 Grafana로 시각화하는 모니터링 스택을 Terraform + Helm으로 구현

---

## 📌 프로젝트 개요

| 항목 | 내용 |
|------|------|
| 프로젝트명 | StockOps ERP - 인프라 모니터링 파트 |
| 팀명 | 시선 (SISEON) |
| 담당 | 팀원C - 로그/모니터링 |
| 클라우드 | AWS (ap-northeast-2) |
| 대상 클러스터 | `seoul-cluster` (Amazon EKS) |
| IaC | Terraform + Helm |

---

## 🏗️ 아키텍처

```
Amazon EKS (seoul-cluster)
        ↓
kube-prometheus-stack (Helm)
├── Prometheus        → Pod/Node 메트릭 수집
├── Node Exporter     → 노드 시스템 메트릭
├── kube-state-metrics → 클러스터 이벤트/상태
└── Grafana           → 통합 대시보드
        ↓
Grafana 데이터소스
├── Prometheus   → 인프라 메트릭 (공식 템플릿 + 커스텀)
└── CloudWatch   → 애플리케이션 로그 (추후 연동)
```

---

## 📡 수집 메트릭

| 수집 대상 | 수집 도구 | 설명 |
|----------|----------|------|
| Pod CPU/메모리 사용률 | Prometheus | 컨테이너 리소스 현황 |
| Pod 재시작 횟수 | kube-state-metrics | CrashLoopBackOff 감지 |
| Node 상태 | Node Exporter | 워커 노드 헬스 체크 |
| 클러스터 이벤트 | kube-state-metrics | Deployment/Service 상태 |
| 네트워크 트래픽 | Prometheus | In/Out 바이트 |

---

## 📊 Grafana 대시보드 구성

| 구분 | 방식 | 대시보드 |
|------|------|---------|
| 공식 템플릿 | Grafana Community | Node Exporter Full (ID: 1860) |
| 공식 템플릿 | Grafana Community | Kubernetes Cluster (ID: 7249) |
| 공식 템플릿 | Grafana Community | Kubernetes Pod (ID: 6417) |
| 커스텀 | 직접 제작 | StockOps 인프라 현황 (서비스별 Pod 상태, CPU/메모리, 네트워크) |

---

## 📁 디렉토리 구조

```
siseon-infra-monitoring/
├── main.tf          # kube-prometheus-stack Helm 배포 + 대시보드 provisioning
├── providers.tf     # AWS / Kubernetes / Helm Provider 설정
├── variables.tf     # 변수 정의
├── outputs.tf       # 출력값
├── terraform.tfvars # 민감 변수 (git 제외)
└── .gitignore
```

---

## 🛠️ 기술 스택

| 분류 | 기술 |
|------|------|
| IaC | Terraform >= 1.0 |
| 클러스터 | Amazon EKS (t3.medium x 2) |
| 모니터링 스택 | kube-prometheus-stack v58.0.0 |
| 메트릭 수집 | Prometheus + Node Exporter + kube-state-metrics |
| 시각화 | Grafana v10.4.0 |
| 배포 방식 | Helm (Terraform Helm Provider) |

---

## 🚀 배포 방법

### 사전 요구사항
- Terraform >= 1.0
- AWS CLI + SSO 설정 (`aws configure sso --profile siseon`)
- EKS 클러스터 구성 완료 (`seoul-cluster`)
- kubectl 설치
- helm 설치

### kubeconfig 설정

```bash
aws eks update-kubeconfig --region ap-northeast-2 --name seoul-cluster --profile siseon
```

### 배포

```bash
# 1. 초기화
terraform init

# 2. 플랜 확인
terraform plan

# 3. 배포 (약 5~10분 소요)
terraform apply
```

### 배포 확인

```bash
# Pod 상태 확인
kubectl get pods -n monitoring -w

# Grafana LoadBalancer IP 확인
kubectl get svc -n monitoring kube-prometheus-stack-grafana
```

### Grafana 접속

```
URL: http://<EXTERNAL-IP>
ID : admin
PW : Siseon2026!
```

### 삭제

```bash
# Helm release 먼저 삭제
helm uninstall kube-prometheus-stack -n monitoring

# Terraform 리소스 삭제
terraform destroy
```

---

## 🔗 연관 레포지토리

| 레포 | 설명 |
|------|------|
| [siseon-security](https://github.com/jun0601/siseon-security) | CloudTrail 보안/감사 모니터링 |
| [siseon-infra-monitoring](https://github.com/jun0601/siseon-infra-monitoring) | EKS 인프라 모니터링 (현재) |
| Stockops-Infra | 팀 메인 인프라 (VPC, EKS, ALB, RDS) |

---

## ⚠️ 주의사항

- `terraform.tfvars` 는 Grafana 비밀번호 포함으로 **절대 커밋 금지** (`.gitignore` 처리됨)
- EKS 클러스터(`seoul-cluster`)가 먼저 배포되어 있어야 함
- AWS CLI SSO 토큰 만료 시 `aws sso login --profile siseon` 으로 재로그인 필요
- kube-prometheus-stack 배포에 약 **5~10분** 소요
- 재배포 시 `helm uninstall` 먼저 실행 후 `terraform apply`