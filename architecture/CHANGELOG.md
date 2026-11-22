# Architecture change log: Assignment 2 → Assignment 3

Baseline: Assignment 2 design ([`assignment2-diagram.png`](assignment2-diagram.png), [`assignment2-walkthroughs.md`](assignment2-walkthroughs.md)).
Revised design: [`exam-a3-singapore-architecture.json`](exam-a3-singapore-architecture.json) (import into the Cloud Architecture Lab, then export `architecture-v3.png`).

Status: **Done** = in Terraform now · **Planned** = recommended in the report, not deployed · **Rejected** = evaluated and not adopted.
Fill the "Driven by" column with the evidence (calculator line, load test, failure test).

| # | Change | Why | Driven by | Status |
|---|---|---|---|---|
| C1 | Region us-east-1 → **ap-southeast-1 (Singapore)** | Brief; closer to users in Bhutan than us-east-1 | Brief, Region comparison (§4) | Done |
| C2 | Project renamed `exam-tsd` → `exam-a3`, new state bucket and OIDC role | Separate A3 stack from A2 | – | Done |
| C3 | Tuning variables: `db_instance_class`, `api_min_tasks`, `api_max_tasks`, `pg_pool_max`, `waf_rate_limit` (set from GitHub Variables) | Fix and re-test the load-test bottleneck without code changes | Load test | Done |
| C4 | `pg` pool size configurable (`PG_POOL_MAX`) | DB connection limit found / avoided under peak | Load test | Done |
| C5 | Dashboard: p95 response time, running tasks, RDS credits and memory, WAF blocks | Prove the bottleneck in CloudWatch | Load test | Done |
| C6 | Manual **destroy** workflow | Only pay while testing | Cost | Done |
| C7 | RDS class: design db.t4g.medium; load test peaked at **19 % CPU on db.t4g.micro** with steady credits → candidate **db.t4g.small** (O8) | The database was not the bottleneck; connections were (C25) | Load test | Planned |
| C8 | Scheduled pre-scale to **4** tasks (2 per AZ) 30 min before each exam | Load test: target tracking added tasks 4–8 min after the 5-minute ramp | Load test | Done (min 4 set for tests); scheduled action planned |
| C9 | Fargate **ARM64 (Graviton)** | ~20% cheaper compute | Calculator O1 | |
| C10 | **Compute Savings Plan** (baseline) and **RDS RI** | Steady 24/7 baseline is commitment-friendly | Calculator O2/O3 | |
| C11 | WAF rate limit: IP set for campus NAT ranges / rate by user | 3,000 students behind one campus IP would be blocked | Reasoned bottleneck | Planned |
| C12 | SES production access + higher send rate | Result release for 3,000 students exceeds the sandbox | Reasoned bottleneck | Planned |
| C13 | RDS Proxy | Shorter failover error window; pools Lambda + API connections | Failure test F1 | In revised design |
| C14 | Interface VPC endpoints instead of NAT data | Cost more than the NAT GB they save at this traffic level | Calculator O5 | Rejected |
| C15 | Single NAT gateway | Cheaper, but a single point of failure for egress in one AZ | Calculator O6 | Rejected |
| C16 | Upload-handler Lambda + email queue (A2 lab design) merged into one notify queue + notify Lambda; the API records the submission at presign | Fewer moving parts and Lambdas; matches the deployed code | Simplification | Done |
| C17 | CloudFront PriceClass_100 → **PriceClass_200** | PriceClass_100 has no Asian edges, so Bhutan users were served from Europe/US; 200 adds India and Asia | Region/latency analysis (§4) | In revised design |
| C18 | CloudWatch log retention 400 d (A2 lab) → 30 d | Logs ingestion and storage are a hidden cost | Calculator | Done |
| C19 | AWS Budgets ($1,000 alerts at 80/100%) + Cost Anomaly Detection | Proves the platform stays within budget | Budget requirement | In revised design |
| C20 | Terraform lock: DynamoDB table → S3 native lock (`use_lockfile`) | One fewer resource | – | Done |
| C21 | Fargate 1 vCPU / 2 GB × min 4 (A2 lab) → 0.5 vCPU / 1 GB × min 2 + scheduled pre-scale | Normal months need ~2 tasks; peak capacity only during sittings | Calculator + load test | Done |
| C22 | RDS PITR 14 d / db.r6g.large (A2 lab) → 7 d / db.t4g.medium + 1-yr RI | Right-sized from the load test; 7 days still meets RPO 5 min | Calculator + load test | In revised design |
| C23 | ALB health check `/api/health` (DB query) → **`/api/live`** (no DB); `/api/health` kept as the deep check | A DB failover made every task fail its health check, so ECS replaced the whole service (F1: 89 s outage) | Failure test F1 | Done |
| C24 | `require("express-async-errors")`, `pool.on("error")`, `unhandledRejection` handler in the API | Async DB errors crashed Node (exit 1) during failover (F1 run 2: 76 s, all tasks restarted) → after fix 16 s, no restarts | Failure test F1 | Done |
| C25 | Auto scaling request target **300 → 3,000 req/task/min**, min 4 in exam windows, max **20 → 8** | Load test: 2 → 20 tasks at 17 % CPU, 4–8 min late, DB connections 8 → 61 → after fix 4 tasks, 28 connections | Load test | Done |
| C26 | Pipeline: wait for ECS steady state before the smoke test (planned) | F3: the smoke test can pass while ECS is rolling back a bad release | Failure test F3 | Planned |

## Single points of failure (mark these on the revised diagram)

| # | Component | Single point of failure? | Removed or accepted | How |
|---|---|---|---|---|
| S1 | Region (ap-southeast-1) | Yes | **Accepted** | Regional outage is rare. RTO 1 h is met by rebuilding from Terraform in another Region + restoring the latest snapshot copy (document as DR). Cross-region replication is not justified for the budget |
| S2 | RDS writer | Yes, during failover | **Removed (mostly)** | Multi-AZ standby, automatic failover 60–120 s, RPO ≈ 0 (F1). RDS Proxy shortens the gap |
| S3 | NAT gateway | Would be with one | **Removed** | One per AZ, per-AZ route tables |
| S4 | API tasks / AZ | Would be with one task | **Removed** | ≥ 1 task per AZ, ≥ 2 per AZ during exams (F2) |
| S5 | ALB | No | **Removed** | Managed, nodes in both AZs |
| S6 | CloudFront / WAF / S3 / SQS / Lambda | No | **Removed** | Managed, multi-AZ by design |
| S7 | WAF per-IP rate limit (campus NAT) | Yes, it blocks everyone at once | **Removed (planned)** | IP-set exception / per-user rate (C11) |
| S8 | SES sending quota | Yes, for result emails | **Accepted → mitigated** | Production access, queued sending (C12); results also visible in the app |
| S9 | Single deploy pipeline / bad release | Yes | **Removed** | ECS circuit breaker auto-rollback (F3) |
| S10 | Marking Lambda | No data loss | **Removed** | SQS retries + DLQ + alarm + redrive (F4) |
| S11 | Secrets / KMS key | Key deletion = data loss | **Accepted** | 7-day deletion window, key policy restricts deletion |