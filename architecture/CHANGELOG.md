# Architecture change log: Assignment 2 → Assignment 3

Baseline: Assignment 2 design ([`assignment2-diagram.png`](assignment2-diagram.png), [`assignment2-walkthroughs.md`](assignment2-walkthroughs.md)).
Revised design: `architecture-v3.png` (draw it after the cost and test results).

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
| C7 | RDS class `db.t4g.micro` → `________` | Burstable CPU credits / connections exhausted at peak | Load test before/after | |
| C8 | Scheduled pre-scale to `__` tasks 30 min before each exam | Target tracking reacts too slowly to a 5-minute ramp | Load test | Planned |
| C9 | Fargate **ARM64 (Graviton)** | ~20% cheaper compute | Calculator O1 | |
| C10 | **Compute Savings Plan** (baseline) and **RDS RI** | Steady 24/7 baseline is commitment-friendly | Calculator O2/O3 | |
| C11 | WAF rate limit: IP set for campus NAT ranges / rate by user | 3,000 students behind one campus IP would be blocked | Reasoned bottleneck | Planned |
| C12 | SES production access + higher send rate | Result release for 3,000 students exceeds the sandbox | Reasoned bottleneck | Planned |
| C13 | RDS Proxy | Shorter failover error window; pools Lambda + API connections | Failure test F1 | Planned |
| C14 | Interface VPC endpoints instead of NAT data | Cost more than the NAT GB they save at this traffic level | Calculator O5 | Rejected |
| C15 | Single NAT gateway | Cheaper, but a single point of failure for egress in one AZ | Calculator O6 | Rejected |

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
