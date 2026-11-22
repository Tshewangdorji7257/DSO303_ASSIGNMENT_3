# Cost and service report: Exam platform in ap-southeast-1 (Singapore)

> **Prices:** AWS Pricing Calculator, USD, Region Asia Pacific (Singapore), **checked on 2026-11-21**.
> **Estimates:** Normal month `<calculator share link>` · Exam month `<calculator share link>`
> **Exports:** `evidence/calculator-normal.csv|pdf`, `evidence/calculator-exam.csv|pdf`
> **Inputs and assumptions:** [`calculator-inputs.md`](calculator-inputs.md)

---

## 1. Monthly cost per service

Every number below comes from the calculator exports (`evidence/calculator-normal.csv`, `evidence/calculator-exam.csv`). The calculator's **logs** figures **exclude** free-tier discounts; the **dashboard** figures include them. Free tiers (CloudFront 1 TB/10 M requests, Lambda, SQS 1 M, CloudWatch 5 GB, Cognito 10,000 MAU) would lower the real bill, so this is a **worst-case** estimate.

| # | Service | What is billed | Normal month (USD) | Exam month (USD) |
|---|---|---|---|---|
| 1 | **RDS PostgreSQL Multi-AZ** | db.t4g.medium primary + standby, 50 GB gp3, 10 GB extra backup | **207.47** | **207.47** |
| 2 | **NAT gateway** (2 AZs, billed per AZ-hour) | 1,460 NAT-hours + data processed | **86.73** | **87.91** |
| 3 | **ECS Fargate**: baseline | 2 tasks × 730 h, 0.5 vCPU / 1 GB, x86 | **44.98** | **44.98** |
| 3b | ECS Fargate: exam pre-scale | 160 tasks × 2.5 h (8 extra tasks × 20 sittings) | – | **12.32** |
| 4 | **CloudFront** *(includes data transfer out = hidden)* | 40 / 65 GB out, 52 / 85 GB to origin, 17.6 M / 28.8 M HTTPS requests | **33.80** | **55.25** |
| 5 | AWS WAF | 1 web ACL, 3 rules, 17.6 M / 28.8 M requests | 18.56 | 25.28 |
| 6 | Application Load Balancer | hours + LCU | 19.83 | 20.85 |
| 7 | **Public IPv4 addresses** *(hidden)* | 4 in-use addresses (2 NAT + 2 ALB) | 14.60 | 14.60 |
| 8 | S3 uploads: Standard | 165 GB, 16 k PUT, 30 k GET | 4.22 | 4.22 |
| 9 | S3 uploads: Standard-IA | 800 GB, 16 k lifecycle transitions, 10 GB retrieval | 11.30 | 11.30 |
| 10 | S3 uploads: Glacier Flexible Retrieval | 960 GB (end of year 1), 16 k transitions | 6.15 | 6.15 |
| 11 | **CloudWatch** *(Logs = hidden)* | 20 metrics, 3 / 6 GB logs, 6 alarms, 1 dashboard, GetMetricData | 8.81 | 11.28 |
| 12 | **AWS Backup (RDS)** *(hidden)* | daily 35 d + monthly 12 m, 20 GB | 3.56 | 3.56 |
| 13 | SES | 16,000 / 76,000 emails | 1.60 | 7.60 |
| 14 | **KMS** *(requests = hidden)* | 1 CMK, 60 k / 150 k requests | 1.18 | 1.45 |
| 15 | Route 53 | 1 zone + queries | 0.90 | 1.30 |
| 16 | SQS | 2 M / 2.2 M requests | 0.80 | 0.88 |
| 17 | Secrets Manager | 1 secret, 50 k / 100 k calls | 0.65 | 0.90 |
| 18 | **Data transfer between AZs** *(hidden)* | 25 / 40 GB | 0.50 | 0.80 |
| 19 | ECR | 1 GB | 0.10 | 0.10 |
| 20 | Lambda (notify, marker) | 16 k / 6 k requests | 0.00 | 0.00 |
| 21 | Cognito (Essentials) | 8,400 MAU (within 10,000 free MAU) | 0.00 | 0.00 |
| | **TOTAL** | | **465.74** | **518.20** |

### Annual total and unit costs

| Metric | Formula | Value |
|---|---|---|
| Annual cost | 10 × 465.74 + 2 × 518.20 | **USD 5,693.80** |
| Average per month | 5,693.80 ÷ 12 | **USD 474.48** vs budget **USD 1,000** |
| Budget headroom | 1,000 − 474.48 | **USD 525.52 (52.6 %)** |
| Cost per student per year | 5,693.80 ÷ 8,000 | **USD 0.71** |
| Cost per user per year (students + staff) | 5,693.80 ÷ 8,400 | **USD 0.68** |
| Extra cost of an exam month | 518.20 − 465.74 | **USD 52.46** |
| Extra cost per exam sitting per student | 52.46 ÷ (20 × 3,000) | **USD 0.0009** |
| After optimisations (Section 6) | | **USD ____ / year** |

**Reading the numbers:** exam months cost only **11 % more** than normal months, because most of the bill is **fixed, always-on capacity** (RDS Multi-AZ, NAT, baseline tasks, IPv4, ALB), which is the price of availability. Traffic-driven items (CloudFront, WAF, logs, SES) and the extra Fargate pre-scale add the rest.

### Hidden costs: what they are and why they matter
| Hidden cost | Driver in this design | Normal / exam (USD) | How it is controlled |
|---|---|---|---|
| **Public IPv4 addresses** | 2 NAT EIPs + 2 ALB IPs, charged per hour | 14.60 / 14.60 | Unavoidable with NAT + a public ALB; IPv6 later. **3 % of the bill, more than the whole S3 Standard tier** |
| **Data transfer out** | Every API response to students goes out through CloudFront | part of 33.80 / 55.25 (CloudFront "Show calculations" splits GB vs requests) | Small JSON responses; CloudFront free tier (1 TB/month) would remove most of it |
| **NAT gateway processing** | ECR image pulls, CloudWatch Logs, SES/SQS/Secrets API calls | ~0.6 / ~1.2 | S3 gateway endpoint already keeps S3 traffic off NAT (free); NAT **hours** (86 USD) matter far more than NAT GB |
| **CloudWatch Logs** | Container Insights, API and Lambda logs | part of 8.81 / 11.28 | No per-request logging, 30-day retention (A2 lab: 400 days) |
| **KMS requests** | Secrets decrypts at task/Lambda start, S3 SSE-KMS | 1.18 / 1.45 | S3 Bucket Key (already on) |
| **Backups** | RDS backup storage beyond the free 100 %, AWS Backup daily/monthly copies | 3.56 + RDS extra backup / same | Free RDS backup storage up to the DB size; long-term copies grow until year 5 |
| **Inter-AZ data transfer** | API task in one AZ talking to the RDS primary in the other | 0.50 / 0.80 | The price of Multi-AZ; negligible at this volume |

### Calculator corrections (shows the estimate was checked)
The first draft totalled **USD 1,073.60/month** (`evidence/calculator-normal-v0-mistakes.csv`). Checking each line found three input errors:
1. **Cognito** had *advanced security* enabled (+USD 420), which the design does not use.
2. **NAT** was entered as both 2 zonal **and** 1 regional gateway across 2 AZs, i.e. 3× the NAT-hours (+USD 173).
3. **SES** had 160,000 instead of 16,000 emails (+USD 14.40).

After the fixes the estimate is **USD 465.74**, so checking the hidden-cost lines more than halved it.

## 2. The three most expensive components and why

Fill in from the totals. Expected order (confirm with your numbers):

1. **RDS PostgreSQL Multi-AZ: USD 207.47/month (44.5 % of a normal month).** Multi-AZ **doubles** the instance cost: you pay for a standby in the second AZ that serves no traffic. That standby is what gives **RPO ≈ 0** (synchronous replication) and lets the platform **survive the loss of an AZ**, so it is the cost of the availability targets, not waste. Levers: Reserved Instance (O3), right-sizing from the load test.
2. **NAT gateways (2 AZs): USD 86.73/month (18.6 %).** Billed **per AZ-hour, around the clock**, even in quiet months when almost no traffic leaves the private subnets (data processed is only ~10 GB, i.e. < USD 1). One NAT per AZ removes the NAT single point of failure. A single NAT would save ~USD 43 but break AZ independence (O6, rejected). Interface endpoints would cost more (O5).
3. **ECS Fargate: USD 44.98/month normal, USD 57.30 in exam months (9.7–11 %).** Two tasks run 24/7 (one per AZ) for availability; exam months add 400 task-hours of pre-scale. Levers: Graviton/ARM64 (O1), Compute Savings Plan on the baseline (O2), scheduled scaling instead of fixed peak capacity (O4).

*Next: CloudFront (USD 33.80–55.25) is the biggest traffic-driven cost, and it grows with exam requests.*

## 3. Service choices compared with an alternative

Legend: ✔ better · ≈ similar · ✘ worse. **Exact** = derived from the calculator's own per-hour rates in `evidence/calculator-*.csv`. **≈** = estimate from AWS list prices for Singapore; confirm it in the calculator (Section 6 lists the clone estimates).

### 3.1 Backend compute: ECS Fargate (chosen) vs EC2 Auto Scaling vs Lambda
| | **ECS Fargate (chosen)** | EC2 Auto Scaling (2 × t4g.small) | Lambda + API Gateway (HTTP API) |
|---|---|---|---|
| **Cost / normal month** | **USD 44.98** (exact) | ≈ USD 35–40 (instances + EBS + more NAT for OS patches) | ≈ USD 40–45 (17.3 M requests × ~100 ms × 512 MB + HTTP API requests) **+ RDS Proxy needed** |
| **Performance** | ✔ Steady latency; a new task is ready in ~60–90 s | ≈ Same latency; scale-out 3–5 min (instance boot + ECS/agent) | ✔ Instant scale-out; ✘ cold starts; ✘ connection storms on RDS at 100 req/s |
| **Resilience** | ✔ Tasks in 2 AZs, auto-replaced, circuit-breaker rollback | ≈ Same if the ASG spans 2 AZs, but hosts are a failure unit | ✔ Multi-AZ by default |
| **Effort** | ✔ Low: no servers; the current Docker image runs unchanged | ✘ High: AMIs, OS patching, capacity, agents | ✘ Medium–high: rewrite Express into handlers, add RDS Proxy, API Gateway config |
| **Verdict** | **Chosen.** EC2 saves ≈ USD 5–10/month but adds patching work and slower scaling at the exam ramp; Lambda costs about the same and needs a rewrite plus RDS Proxy to protect the database. For one small always-on API, Fargate is the best balance. |||

### 3.2 Answers database: RDS PostgreSQL Multi-AZ (chosen) vs Aurora Serverless v2 vs DynamoDB
| | **RDS PostgreSQL Multi-AZ (chosen)** | Aurora PostgreSQL Serverless v2 | DynamoDB on-demand |
|---|---|---|---|
| **Cost / month** | **USD 207.47** (exact; ≈ USD 140 with a 1-yr RI) | ≈ USD 100–120 at the 0.5 ACU minimum × writer + reader for Multi-AZ, rising during exams (10–20 ACU-hours per sitting) + I/O | ≈ USD 15–30 (≈ 20–30 M writes + reads per month) |
| **Performance** | ≈ Fixed size; burstable credits are a risk at peak (load test) | ✔ Scales ACUs in seconds during the 5-minute ramp | ✔ Single-digit ms at any scale |
| **Resilience / RPO / RTO** | ✔ Synchronous standby, failover 60–120 s, RPO ≈ 0 | ✔ Storage in 3 AZs, failover usually < 30 s | ✔ Multi-AZ built in, PITR |
| **Effort** | ✔ None: current SQL, upserts and joins | ✔ Low: PostgreSQL-compatible | ✘ High: redesign marking queries (joins), new access patterns, rewrite API and marker |
| **Verdict** | **Chosen for now.** It is the biggest cost, but it needs no rework and meets RPO/RTO. **Aurora Serverless v2 is the best upgrade path** if the load test shows CPU-credit or connection limits: similar cost, better scaling at the ramp, faster failover. DynamoDB is cheapest but needs a rewrite of the data model. |||

### 3.3 Private traffic: 2 zonal NAT gateways (chosen) vs 1 regional NAT vs interface VPC endpoints
| | **2 zonal NAT (chosen, in Terraform)** | 1 regional NAT (2 AZs) | Interface endpoints (ECR api, ECR dkr, Logs, Secrets Manager, SQS) |
|---|---|---|---|
| **Cost / month** | **USD 86.73** + USD 0.059/GB (exact) | **USD 86.73** (exact: billed per AZ-hour, the same) | ≈ **+USD 95** (5 endpoints × 2 AZs × 730 h ≈ USD 0.013/h) **on top of** NAT, which is still needed for SES/internet |
| **Performance** | ≈ | ≈ | ✔ No NAT hop for AWS APIs |
| **Resilience** | ✔ One per AZ, per-AZ route tables | ✔ AWS spreads it across AZs; ✘ up to 60 min to expand to a new AZ | ✔ ENIs per AZ |
| **Effort** | ≈ 2 gateways, 2 EIPs, 2 route tables | ✔ One NAT ID, one route | ✘ 5 resources × 2 AZs, endpoint policies, private DNS |
| **Verdict** | **Chosen.** NAT data is only 10–30 GB/month (< USD 2), so endpoints would cost ~50× more than the NAT data they save. The regional NAT is the same price and simpler: a future change (not a saving). |||

### 3.4 Pricing model: On-Demand vs Compute Savings Plan vs RDS Reserved Instance
| | **On-Demand** | Compute Savings Plan (1 yr, no upfront) on Fargate | RDS Reserved Instance (1 yr, no upfront, Multi-AZ) |
|---|---|---|---|
| **Cost / year** | **USD 5,693.80** (exact) | Fargate baseline ≈ −20 % → saves ≈ **USD 108/yr** (≈ USD 9/month) | RDS instance ≈ −33 % → saves ≈ **USD 800/yr** (≈ USD 67/month) |
| **Flexibility** | ✔ Full | ✔ Applies to any Fargate/Lambda/EC2 usage, any Region, any size | ✘ Locked to instance family, Region and Multi-AZ setting |
| **Risk** | None | ≈ Low: commits only the always-on baseline (2 tasks), which runs 24/7 anyway | ✘ If the load test forces a bigger class, an RI on db.t4g.medium is wasted. Buy it **after** the load test; size-flexibility within the family softens this |
| **Verdict** | **Adopt both commitments on the steady 24/7 baseline only** (2 tasks + the RDS instance). Exam pre-scale stays On-Demand. Together they cut ≈ 16 % of the annual bill. |||

### 3.5 5-year file retention: S3 lifecycle (chosen) vs Intelligent-Tiering vs Standard only
Same data at the end of year 1: **1,925 GB** (165 Standard + 800 IA + 960 Glacier).
| | **Lifecycle Standard → IA (30 d) → Glacier Flexible (180 d) → expire (5 y)** | S3 Intelligent-Tiering (all tiers + Archive Instant) | S3 Standard only |
|---|---|---|---|
| **Cost / month (year 1)** | **USD 21.67** (exact) | ≈ USD 20–25 (+ monitoring fee ≈ USD 0.0025 per 1,000 objects × 192,500 objects) | ≈ **USD 48** (1,925 GB × ≈ USD 0.025) |
| **Cost / month (year 5, ≈ 9.6 TB)** | ≈ **USD 55–60** (Glacier ≈ 8.6 TB) | ≈ USD 60–70 | ≈ **USD 240** |
| **Retrieval** | ✘ Glacier: minutes–hours, per-GB fee (fine for appeals/audits) | ✔ Instant for frequent/infrequent/archive-instant tiers | ✔ Instant |
| **Fit** | ✔ Files age predictably; rarely opened after marking | ≈ Best when access is unpredictable | ✘ Pays hot-storage prices for cold records |
| **Verdict** | **Chosen.** Access follows a known calendar (marking, then archive), so a fixed lifecycle is about as cheap as Intelligent-Tiering, with no monitoring fee, and **≈ 4× cheaper than Standard-only** by year 5. |||

## 4. Region comparison: Singapore (ap-southeast-1) vs Mumbai (ap-south-1)

| | **Singapore** | **Mumbai** |
|---|---|---|
| Normal month (same estimate, Region switched) | **USD 465.74** | USD ____ *(calculator R1)* |
| Exam month | **USD 518.20** | USD ____ |
| Annual | **USD 5,693.80** | USD ____ |
| **Latency from Bhutan** (median of 3, cloudping.info, Phuntsholing, 2026-11-__) | ____ ms | ____ ms |
| Distance / network path | Further (via India or Bangladesh → Southeast Asia) | Closer; Bhutan's international links run through India |
| Services in this design available? | All | All used here (Fargate incl. Graviton, RDS Multi-AZ, SES, WAF, CloudFront) |
| CloudFront | Same global edges either way; **PriceClass_200** serves Bhutan from Indian edges | Same |
| **Verdict** | *Fill after R1 and L1, e.g.: "Mumbai is ___ % cheaper and ___ ms faster from Bhutan; Singapore was set by the brief and is still within budget. Recommend Mumbai if the university can choose."* | |

> Latency mainly affects **API** calls (exam load, autosave, submit). Static files come from a nearby CloudFront edge in both cases, and autosave every 30 s is not latency-sensitive. The difference matters most for exam start at the 5-minute ramp.

## 5. Feasibility verdict

| Question | Evidence | Answer |
|---|---|---|
| **Within USD 1,000/month averaged over a year?** | Annual USD 5,693.80 → **USD 474.48/month** (47 % of budget, On-Demand); ≈ USD 391/month with adopted optimisations | **✔ Yes, with ~50 % headroom** |
| **Handles the peak (3,000 starts in 5 min)?** | Load test T3 (`loadtest/RESULTS.md`): 3,000 virtual students, ~5,900 req/min, **4 tasks**, **0.005 % errors**, server response **17 ms avg**, autosave p95 **0.95 s** from Bhutan, ECS CPU ≤ 17 %, RDS CPU ≤ 19 % on db.t4g.micro | **✔ Yes**, after right-sizing auto scaling (300 → 3,000 req/task, pre-scale to 4) |
| **Peak blocked by anything?** | WAF per-IP limit blocked **95 %** of requests from one IP at the peak (T0b) | **✘ until fixed**: campus IP-set exception / per-user rate limit required (C11) |
| **RPO ≤ 5 min?** | 5 probe runs across F1–F3: **0 acknowledged autosaves lost**; F4: **0 of 3** marking jobs lost (DLQ + redrive); synchronous Multi-AZ | **✔ Yes (measured RPO = 0)** |
| **RTO ≤ 1 h?** | F1 DB failover **16 s** API outage (after fixes; 89 s before); F2 AZ loss 34 s intermittent; F3 bad release 0 s with auto-rollback in 2 min; F4 recovery ~1 min after fix | **✔ Yes (worst measured: 89 s)** |
| **Survives the loss of one AZ?** | F2: AZ-a app subnet isolated → AZ-b tasks carried all traffic, replacement started in AZ-b within ~70 s; F1: DB failed over between AZs | **✔ Yes** |
| **Files kept 5 years?** | S3 lifecycle expire at 1,826 days; versioning; AWS Backup monthly copies | ✔ Yes (by configuration) |

**Verdict: feasible.** The platform costs **USD 474/month on average (USD 0.71 per student per year)**, under half the USD 1,000 budget, and about **USD 391/month** after the adopted optimisations. Load and failure testing showed that **money is not the constraint; configuration is.** Three real defects were found and fixed with measurements:

1. **Auto scaling mis-sized:** 2 → 20 tasks at 17 % CPU, 4–8 min late, DB connections 8 → 61. Fixed (4 tasks, 28 connections).
2. **Deep health check plus unhandled async errors:** a 49 s DB failover caused an 89 s API outage and restarted every task. Fixed (16 s, no restarts).
3. **WAF per-IP limit:** would block a whole class behind one campus IP. Fix designed (C11).

The measured capacity (2 tasks, a micro database at < 20 % CPU) leaves room to **downsize** the database class in the design (O8) rather than grow it.
**Conditions:** apply C11 (WAF) and C12 (SES production access) before the first exam week, and keep the scheduled pre-scale of 4 tasks (2 per AZ) during exam windows.

## 6. Optimisations (Task 3)

Baseline: normal **USD 465.74**, exam **USD 518.20**, annual **USD 5,693.80**.
**Exact** = derived from the calculator's own per-hour rates (the change is linear). **≈** = list-price estimate; confirm with a calculator clone and replace the figure.

| # | Optimisation | Monthly before → after | **Saving / year** | Trade-off | Adopted? |
|---|---|---|---|---|---|
| **O1** | Fargate **ARM64 (Graviton)** (≈ 20 % lower vCPU/GB rate) | Fargate 44.98 → ≈ 35.98 (normal); pre-scale 12.32 → ≈ 9.86 | ≈ **USD 113** | Build an arm64 image (one `docker buildx` flag); test dependencies | ✔ |
| **O2** | **Compute Savings Plan**, 1 yr, no upfront, on the 2-task baseline | baseline ≈ 35.98 → ≈ 28.8 (after O1) | ≈ **USD 86** | 1-year commitment on usage that runs 24/7 anyway | ✔ |
| **O3** | **RDS Reserved Instance**, 1 yr, no upfront, Multi-AZ | RDS 207.47 → ≈ 140 | ≈ **USD 800** | Locked to the class; **buy after the load test confirms the size** | ✔ (after load test) |
| **O4** | **Scheduled pre-scale** vs fixed peak capacity (10 tasks all month in exam months) | exam Fargate 224.90 → 57.30 (**exact**) | **USD 335** (2 exam months × 167.60) | Needs the exam timetable fed into the scaling schedule | ✔ (already in design) |
| O5 | Interface endpoints instead of NAT data | VPC +≈ 95/month | **−USD 1,140** (cost increase) | NAT still needed for SES/internet | ✘ rejected |
| O6 | Single NAT (1 AZ) | NAT 86.73 → 43.37 (**exact**) | USD 520 | Reintroduces a single point of failure: losing that AZ cuts outbound access (SES, image pulls) for the survivor | ✘ rejected |
| O7 | CloudWatch log retention 400 d → 30 d (vs A2 lab design) | avoids ~ 12× log storage growth | small now, grows yearly | Less history; export to S3 if needed | ✔ |
| | **Adopted O1–O4 combined** | normal ≈ **382**, exam ≈ **432** | **≈ USD 1,000/yr (≈ 18 %)** → annual ≈ **USD 4,690**, ≈ **USD 391/month**, ≈ **USD 0.59/student** | | |

**Free-tier note.** The estimate excludes most free tiers. CloudFront's always-free 1 TB and 10 M requests alone would remove most of the USD 34–55 CloudFront line; Lambda, SQS (1 M), CloudWatch (5 GB logs, 10 metrics, 10 alarms) and Cognito (10,000 MAU) add small further savings.

### To confirm in the calculator (clone the normal or exam estimate; change one thing; record the total)
- [ ] O1: Fargate → ARM → total ____
- [ ] O2: Fargate → Compute Savings Plan 1 yr no upfront → total ____
- [ ] O3: RDS → Reserved 1 yr no upfront, Multi-AZ → total ____
- [ ] O4: exam estimate, delete the pre-scale row, baseline 10 tasks × 730 h → total ____ (expect 685.80)
- [ ] O5: VPC → 5 interface endpoints × 2 AZs → total ____
- [ ] O6: Regional NAT active in 1 AZ → total ____ (expect ≈ 422.37)
- [ ] R1: Mumbai → total ____ · L1: cloudping Singapore ____ ms / Mumbai ____ ms