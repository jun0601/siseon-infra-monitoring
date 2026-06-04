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
Grafana 데이터소스 3개
├── Prometheus   → 인프라 메트릭 탭
├── CloudWatch   → 애플리케이션 로그 탭
└── Azure Monitor → 백업 로그 탭 (AWS 장애 시나리오)
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

## 📁 디렉토리 구조

```
siseon-infra-monitoring/
├── main.tf          # kube-prometheus-stack Helm 배포
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
| 시각화 | Grafana |
| 배포 방식 | Helm (Terraform Helm Provider) |

---

## 🚀 배포 방법

### 사전 요구사항
- Terraform >= 1.0
- AWS CLI + SSO 설정 (`aws configure sso --profile siseon`)
- EKS 클러스터 구성 완료 (`seoul-cluster`)
- kubectl 설치

### 배포

```bash
# 1. 초기화
terraform init

# 2. 변수 파일 생성
cp terraform.tfvars.example terraform.tfvars
# terraform.tfvars 에 Grafana 비밀번호 입력

# 3. 플랜 확인
terraform plan

# 4. 배포
terraform apply
```

### Grafana 접속

```bash
# LoadBalancer 외부 IP 확인
kubectl get svc -n monitoring kube-prometheus-stack-grafana

# 접속 정보
# ID: admin
# PW: terraform.tfvars 에 설정한 값
```

### 삭제

```bash
terraform destroy
```

---

## 📊 Grafana 대시보드 구성

| 탭 | 데이터소스 | 주요 패널 |
|----|----------|----------|
| 인프라 | Prometheus | Pod CPU/메모리, Node 상태, 클러스터 이벤트 |
| 애플리케이션 | CloudWatch | API 로그, 재고 로그, AI 예측 로그 |
| Azure 백업 | Azure Monitor | AWS 장애 시 백업 로그 전환 시나리오 |

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
- kube-prometheus-stack은 배포에 약 **5~10분** 소요