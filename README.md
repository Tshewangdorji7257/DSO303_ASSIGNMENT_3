# DSO303 Assignment 3: Cost, Failure and Load Testing of the Online Exam Platform



## Summary, feasibility verdict and calculator links

**Summary.** The Assignment 2 exam platform was costed in **Singapore (ap-southeast-1)**: **USD 465.74** in a normal month and **USD 518.20** in an exam month. That is **USD 5,693.80 a year**, an average of **USD 474.48/month (47 % of the USD 1,000 budget)**, or **USD 0.71 per student per year**. It was deployed from Terraform via GitHub Actions, load-tested with 3,000 students in 5 minutes, and failure-tested in four scenarios. Testing found and fixed three defects:
- **mis-sized auto scaling:** 2 → 20 tasks at 17 % CPU → fixed to 4 tasks
- **a database-dependent health check** and **an async-error crash:** a DB failover caused an 89 s API outage → **16 s** after the fixes
- **a WAF per-IP limit** that would block students behind a campus NAT

**Feasibility verdict: FEASIBLE.**

| Target | Result | Met? |
|---|---|---|
| Budget USD 1,000/month (yearly average) | USD 474.48/month (≈ USD 391 with optimisations) | ✔ |
| Peak: 3,000 students in 5 min | 4 tasks, 0.005 % errors, server 17 ms, autosave p95 0.95 s | ✔ (after scaling fix) |
| RPO 5 min | **0** acknowledged autosaves lost in every test; 0 of 3 marking jobs lost | ✔ |
| RTO 1 h | Worst measured 89 s (16 s after fixes) | ✔ |
| Survive loss of one AZ | AZ-a isolated: 34 s intermittent errors, AZ-b carried all traffic | ✔ |
| Files kept 5 years | S3 lifecycle to 1,826 days + AWS Backup | ✔ |

**Conditions:** exempt campus IP ranges from the WAF per-IP limit (C11), request SES production access (C12), and keep the 4-task pre-scale during exam windows.

**AWS Pricing Calculator (Singapore, prices checked 21 Nov 2026)**

| Estimate | Monthly | Link |
|---|---|---|
| Normal month | USD 465.74 | `evidence/calculator-normal.csv` |
| Exam month | USD 518.20 | `evidence/calculator-exam.csv` |
| Exports | | `evidence/calculator-normal.csv/.pdf`, `evidence/calculator-exam.csv/.pdf` |

---

## 1. Aim / Objective

To find out whether the Assignment 2 exam platform can run in **Asia Pacific (Singapore)** within a budget of **USD 1,000 per month** (averaged over a year), and where it fails or slows down. Specifically:

1. **Cost** the platform for a **normal month** (300–500 concurrent users) and an **exam month** (3,000 students starting one exam within 5 minutes) in the AWS Pricing Calculator, including hidden costs, and apply at least three optimisations.
2. **Redesign** the architecture for cost, mark every single point of failure, and keep a change log against Assignment 2.
3. **Load-test** the deployed platform at the exam peak, prove the bottleneck with CloudWatch, fix it and re-test.
4. **Failure-test** at least four scenarios and measure them against the targets: **RPO 5 minutes, RTO 1 hour, survive the loss of one AZ, files kept 5 years**.

## 2. Introduction

This practical uses **cost and performance engineering on AWS**: measuring what a cloud system costs and how it behaves under load and failure. The main tools are:

- the **AWS Pricing Calculator**, which estimates monthly cost per service for a chosen Region
- **Amazon CloudWatch**, for metrics, logs and dashboards to measure behaviour
- **k6**, an open-source load-testing tool, to simulate thousands of students
- **AWS's own fault-injection levers**: RDS forced failover, network ACLs, Lambda configuration and ECS deployments

The platform itself is built from managed services:

- **CloudFront and WAF** at the edge
- an **Application Load Balancer** in front of **ECS Fargate** tasks in two Availability Zones
- **RDS PostgreSQL Multi-AZ**
- **S3** with a 5-year lifecycle
- **SQS, Lambda and SES** for marking and email

Everything is deployed by **Terraform** through **GitHub Actions** using OIDC, with no stored keys.

This matters in cloud computing because a design that *looks* highly available on a diagram can still fail in practice, and a design that *looks* expensive may actually be over-provisioned. Only cost estimates and real tests show this. Typical applications are capacity planning before a launch or an exam week, choosing a Region, proving SLA targets (RPO/RTO) to stakeholders, and finding configuration defects before users do.

## 3. Use Case

A university with **8,000 students and about 400 staff** runs all exams and assignment submissions online:

| User | Activity |
|---|---|
| Students | Sit timed MCQ exams; answers **autosave every 30 seconds**; upload assignments (PDF/ZIP, up to 50 MB) |
| Tutors | Create exams, mark, release results; get an email when an assignment arrives |
| Administrators | Manage users and exam timetables |

| Load profile | Months per year | Traffic |
|---|---|---|
| **Normal month** | 10 | 300–500 concurrent users |
| **Exam month** | 2 | Peak: **3,000 students start one exam within 5 minutes** (~10 starts/s, then ~100 autosaves/s) |

Where each service fits this use case:
- **CloudFront + S3** serve the web app close to students in Bhutan.
- **ECS Fargate + ALB** run the exam API across two AZs and scale for the peak.
- **RDS Multi-AZ** stores answers with no committed data lost if an AZ fails.
- **SQS + Lambda** mark exams in the background, so submissions never slow an exam.
- **S3 lifecycle** keeps assignment files for 5 years at the lowest storage cost.
- **CloudWatch + SNS** alert the operations team during exam week.

## 4. System Architecture / Design

**Revised, cost-optimised design (Singapore, 2 AZs)**, with single points of failure (SPOFs) tagged ✔ removed / ⚠ accepted, plus a cost and test-findings legend:

![alt text](architecture/architecture-v3.png)

*(Source: [`architecture/exam-a3-singapore-architecture.json`](architecture/exam-a3-singapore-architecture.json), imported into the Cloud Architecture Lab.)*

**Main data flows**

| Flow | Path |
|---|---|
| Open exam + autosave | Student → Route 53 → CloudFront (+ WAF) → ALB → ECS Fargate task (AZ a or b) → RDS PostgreSQL primary → synchronous standby in the other AZ |
| Submit exam | API → SQS `marking` → Lambda marker → RDS `results` (DLQ after 5 failures) |
| Upload assignment | API returns a presigned URL → browser uploads straight to S3 (SSE-KMS) → S3 event → SQS `notify` → Lambda → SES email to tutor |
| Monitoring | CloudWatch alarms → SNS email; dashboard `exam-a3` |
| Delivery | `git push` → GitHub Actions → OIDC role → Terraform → ECR → ECS / S3 / CloudFront |

**Single points of failure**

| # | Component | Decision |
|---|---|---|
| S1 | The Region itself | ⚠ **Accepted**: rebuild from Terraform + backups within the 1 h RTO |
| S2 | RDS writer | ✔ **Removed**: Multi-AZ standby, automatic failover (measured in F1) |
| S3 | NAT gateway | ✔ **Removed**: one per AZ |
| S4 | API tasks | ✔ **Removed**: tasks in both AZs (measured in F2) |
| S5–S6 | ALB, CloudFront, S3, SQS, Lambda | ✔ **Removed**: managed, multi-AZ |
| S7 | WAF per-IP limit behind a campus NAT | ✔ **Removed** by design: campus IP-set exception (proven in the load test) |
| S8 | SES sending quota | ⚠ **Accepted/mitigated**: production access, queued sending |
| S9 | Bad release | ✔ **Removed**: ECS circuit-breaker rollback (measured in F3) |
| S10 | Marking Lambda | ✔ **Removed**: retries + DLQ + redrive (measured in F4) |
| S11 | KMS key deletion | ⚠ **Accepted**: 7-day deletion window |

**Key changes from Assignment 2** (full list C1–C26 in [`architecture/CHANGELOG.md`](architecture/CHANGELOG.md)):

| Change | Reason |
|---|---|
| us-east-1 → **ap-southeast-1** | Brief; closer to Bhutan |
| Auto scaling target **300 → 3,000 requests/task**, pre-scale **4 tasks** in exams, max **20 → 8** | **Load test**: scaled 2 → 20 tasks at 17 % CPU |
| ALB health check `/api/health` (DB) → **`/api/live`** (no DB) | **Failure test F1**: a DB failover restarted every task |
| `require("express-async-errors")` + error handlers | **F1**: DB errors crashed Node |
| Interface VPC endpoints **rejected**, 2 NATs kept | **Cost**: endpoints cost more than the NAT data they save |
| CloudFront PriceClass_100 → **200** | PriceClass_100 has no Asian edges for Bhutan |
| Fargate **ARM64**, Savings Plan, RDS RI, logs 30 days, AWS Budgets | **Cost optimisations** |

## 5. Implementation Procedure

1. **Prepared the repository:** copied the A2 code into a new repo, renamed the project to `exam-a3`, switched to `ap-southeast-1`, and added tuning variables (task counts, scaling target, DB class, pool size, WAF limit) controlled from GitHub Variables, plus a dashboard, a **destroy** workflow, a **k6 load test** and a **probe script**.
2. **Costed both load profiles** in the AWS Pricing Calculator (Singapore) from a documented quantities sheet ([`docs/calculator-inputs.md`](docs/calculator-inputs.md)), checking and correcting three input mistakes, then exported CSV/PDF.
3. **Measured latency** from Phuntsholing to Singapore and Mumbai (cloudping.info, 3 runs).
4. **Bootstrapped** the Terraform state bucket and GitHub OIDC role, **validated** Terraform, set the GitHub secret and variables, and **deployed** with GitHub Actions.
5. **Load test:** proved the WAF per-IP limit; raised it for testing; ran a smoke test, then the **BEFORE** test (3,000 students); pulled per-minute CloudWatch metrics; identified the bottleneck; changed the scaling settings; ran the **AFTER** test and compared.
6. **Failure tests:** ran `scripts/probe.ps1` (one health check + one autosave every second) during each test:
   - **F1** RDS forced failover (3 runs, 2 code fixes in between)
   - **F2** AZ-a app subnet isolated with a deny-all network ACL
   - **F3** deliberately broken release
   - **F4** broken marking Lambda (retries → DLQ → alarm → redrive)
7. **Wrote up** the cost report, load-test results, failure tests, change log and revised design, then **destroyed** the stack.

## 6. Results and Evidence

### 6.1 CLI / SDK Output

**Terraform validate and bootstrap.** Configuration valid; state bucket and OIDC role created (6 resources).

![alt text](evidence/image-25.png)
![alt text](evidence/image-26.png)

**k6 installed** (load-testing tool).

![alt text](evidence/image-30.png)

**Load test 0: WAF per-IP limit (500 students, one IP).** **3,021 of 5,624 requests (53.7 %) blocked with 403.** At the full 3,000-student peak, 95 % were blocked.

![alt text](evidence/image-31.png)

**Smoke test (200 students).** 0 % errors after raising the WAF limit; this also gives the **network baseline** from Bhutan (p95 ≈ 1.07 s at only 5 req/s).

![alt text](evidence/image-33.png)

**Load test BEFORE (3,000 students):** 0.02 % errors, but **autosave p95 2.00 s ✗** and p99 4.07 s.

![alt text](evidence/image-36.png)

**CloudWatch per-minute metrics, BEFORE.** The server responded in ~18 ms at 17 % CPU, but **ECS scaled 2 → 20 tasks** 4–8 min after the ramp, and **DB connections rose 8 → 61**.

![alt text](evidence/image-38.png)
![alt text](evidence/image-37.png)

**Fix applied in code.** The scaling target became a variable (`api_requests_per_target`).

![alt text](evidence/image-39.png)

**Load test AFTER (same 3,000 students):** **all thresholds pass**; autosave p95 **0.95 s**, errors 0.005 %.

![alt text](evidence/image-42.png)

**CloudWatch per-minute metrics, AFTER.** **4 tasks steady** (no scale-out), **max 28 DB connections**, server time 17 ms.

![alt text](evidence/image-43.png)

**Load test: before vs after**

| Metric | BEFORE | AFTER |
|---|---|---|
| Peak load (ALB) | ~5,800 req/min | ~5,900 req/min |
| ECS tasks at peak | 2 → **20** (late) | **4 steady** |
| Max DB connections | **61** | **28** |
| Server response (ALB avg) | 18 ms | 17 ms |
| k6 autosave p95 / p99 | 2.00 s / 4.07 s ✗ | **0.95 s / 1.34 s ✓** |
| Failed requests | 24 | 4 |

**F1: RDS failover.** Probe started, failover triggered from the CLI, RDS events show *failover started → completed*.

![alt text](evidence/image-44.png)
![alt text](evidence/image-45.png)
![alt text](evidence/image-46.png)
![alt text](evidence/image-47.png)
![alt text](evidence/image-48.png)

**F1: checks after the failover** (ECS events, API logs, primary AZ swapped):

![alt text](evidence/image-49.png)

**F1 results: three runs**

| | Run 1: as deployed | Run 2: + ALB liveness fix | **Run 3: + crash fix** |
|---|---|---|---|
| API outage (probe) | **89 s** | 76 s | **16 s** |
| Errors | 503, **502**, timeouts | 503, **502**, timeouts | 503/500 only |
| ECS tasks replaced | **all 4** (exit code 1) | **all 4** | **none** |
| Acknowledged autosaves lost | **0** | **0** | **0** |

**F2: AZ-a loss.** Tasks spread 2 + 2 across AZs, and the deny-all network ACL prepared and applied (isolated 20:47:08 → restored 20:49:05).

![alt text](evidence/image-50.png)
![alt text](evidence/image-51.png)

**F4: marking Lambda broken.** `PGHOST` changed, 3 exams submitted (students unaffected: `queued: True`), the queue watched until the **DLQ held 3**, then fixed + redrive. **All 3 scores recovered.**

![alt text](evidence/image-52.png)
![alt text](evidence/image-53.png)
![alt text](evidence/image-54.png)
![alt text](evidence/image-55.png)
![alt text](evidence/image-56.png)
![alt text](evidence/image-57.png)

**Failure tests: summary**

| Test | User impact (measured) | Data lost | RPO 5 min | RTO 1 h |
|---|---|---|---|---|
| **F1** RDS failover | 89 s → **16 s** after 2 fixes | 0 | ✔ | ✔ |
| **F2** AZ-a lost | 34 s intermittent (5 timeouts), no outage | 0 | ✔ | ✔ |
| **F3** Bad release | **0 s** (344/344 autosaves OK); auto-rollback in **2 min 02 s** | 0 | ✔ | ✔ |
| **F4** Marker broken | 0 s for students; marking delayed ~9 min | **0 of 3 jobs** | ✔ | ✔ |

### 6.2 AWS Management Console Verification

**Pricing Calculator: normal month (Singapore).** Each service configured with the quantities in `docs/calculator-inputs.md`.

| Service | Screenshot | What was configured |
|---|---|---|
| RDS PostgreSQL | ![alt text](evidence/image.png) | db.t4g.medium, **Multi-AZ**, 50 GB gp3, 10 GB backup |
| AWS Fargate | ![alt text](evidence/image-1.png) | 2 tasks × 730 h, 0.5 vCPU / 1 GB |
| Amazon VPC | ![alt text](evidence/image-2.png) | NAT across 2 AZs + 4 public IPv4 addresses |
| Elastic Load Balancing | ![alt text](evidence/image-3.png) | 1 Application Load Balancer |
| Amazon CloudFront | ![alt text](evidence/image-4.png) | 40 GB out, 17.6 M HTTPS requests (India edge) |
| AWS WAF | ![alt text](evidence/image-5.png) ![alt text](evidence/image-6.png) | 1 web ACL, 3 rules, 17.6 M requests |
| Amazon S3 | ![alt text](evidence/image-7.png) | Standard 165 GB, Standard-IA 800 GB, Glacier 960 GB, lifecycle transitions |
| Amazon CloudWatch | ![alt text](evidence/image-8.png) | 20 metrics, 3 GB logs, 6 alarms, 1 dashboard |
| AWS KMS | ![alt text](evidence/image-9.png) | 1 key, 60,000 requests |
| Amazon SQS | ![alt text](evidence/image-10.png) | 2 M requests |
| AWS Lambda | ![alt text](evidence/image-11.png) | notify: 16,000 requests |
| Amazon SES | ![alt text](evidence/image-12.png) | 16,000 emails |
| AWS Secrets Manager | ![alt text](evidence/image-13.png) | 1 secret, 50,000 calls |
| Amazon ECR | ![alt text](evidence/image-14.png) | 1 GB |
| Amazon Route 53 | ![alt text](evidence/image-15.png) | 1 hosted zone |
| Amazon Cognito | ![alt text](evidence/image-16.png) | 8,400 MAU (within free tier) |
| AWS Backup | ![alt text](evidence/image-17.png) | RDS daily 35 d + monthly 12 m |
| AWS Data Transfer | ![alt text](evidence/image-18.png) | 25 GB between AZs |

**Normal month estimate: USD 465.74/month.**

![alt text](evidence/image-20.png)

**Exam month estimate: USD 518.20/month** (adds an exam pre-scale Fargate row, marker Lambda, and more traffic, logs and email).

![alt text](evidence/image-21.png)

**Latency from Phuntsholing, Bhutan** (cloudping.info, 3 runs):

![alt text](evidence/image-22.png)
![alt text](evidence/image-23.png)
![alt text](evidence/image-24.png)

| | Singapore (ap-southeast-1) | Mumbai (ap-south-1) |
|---|---|---|
| Median of 3 runs | ___ ms | ___ ms |

**GitHub Actions secret and variables.** Role ARN as a secret (no AWS keys stored); state bucket and emails as variables.

![alt text](evidence/image-27.png)
![alt text](evidence/image-28.png)
![alt text](evidence/image-34.png)

**Deploy pipeline green.** OIDC → Terraform → ECR → ECS → S3/CloudFront → smoke test.

![alt text](evidence/image-29.png)

**CloudWatch: WAF blocked requests** during load test 0 (the per-IP rate limit).

![alt text](evidence/image-32.png)

**CloudWatch dashboard `exam-a3`** during the BEFORE load test.

![alt text](evidence/image-35.png)

**Fix: GitHub Variables** `API_REQ_PER_TARGET=3000`, `API_MIN_TASKS=4`, `API_MAX_TASKS=8`.

![alt text](evidence/image-40.png)

**ECS service running 4 tasks** after the fix.

![alt text](evidence/image-41.png)

### 6.3 Cost summary

| Item | USD |
|---|---|
| Normal month | **465.74** |
| Exam month | **518.20** |
| **Annual** (10 × normal + 2 × exam) | **5,693.80** |
| **Average per month** | **474.48** = **47 %** of the USD 1,000 budget |
| Cost per student per year | **0.71** |
| After adopted optimisations | ≈ 391/month (≈ 4,690/year) |

**Top 3 costs:** RDS Multi-AZ **207.47** (44.5 %), NAT gateways **86.73** (18.6 %), Fargate **44.98** (9.7 %). All three are **fixed availability capacity** that runs 24/7, which is why an exam month costs only 11 % more.

**Hidden costs included:** public IPv4 (14.60), CloudFront data transfer out, NAT data processing, CloudWatch Logs, KMS requests, backups and inter-AZ data transfer (details in `docs/cost-report.md` §1).

**Optimisations** (savings per year; ≈ = estimate to confirm in the calculator):

| # | Optimisation | Saving / year | Adopted |
|---|---|---|---|
| O1 | Fargate ARM64 (Graviton) | ≈ 113 | ✔ |
| O2 | Compute Savings Plan (1 yr) | ≈ 86 | ✔ |
| O3 | RDS Reserved Instance (1 yr) | ≈ 800 | ✔ (after load test) |
| O4 | Scheduled pre-scale vs fixed peak capacity | **335** (exact) | ✔ |
| O5 | Interface endpoints instead of NAT data | −1,140 (costs more) | ✘ |
| O6 | Single NAT | 520 (exact) | ✘ (SPOF) |

## 7. Analysis and Discussion

**What was achieved.** Both load profiles were costed in the calculator, the platform was deployed to Singapore from code, and it was load-tested at the full exam peak and failure-tested in four scenarios. **Three real defects** were found and fixed with before/after measurements:

| Defect found | Evidence | Fix | Result |
|---|---|---|---|
| **Auto scaling mis-sized** (300 req/task target) | CloudWatch: 2 → 20 tasks at 17 % CPU, 4–8 min late; DB connections 8 → 61 | Target 3,000 req/task, pre-scale 4, max 8 | Same peak on **4 tasks**, 28 connections, thresholds pass |
| **Health check depended on the database** | F1 run 1: all 4 tasks deregistered and replaced during a 49 s DB failover → 89 s outage | `/api/live` (no DB) for the ALB | Run 2: tasks no longer failed the ALB check… |
| **Unhandled async errors crashed Node** | F1 run 2: exit code 1, all tasks restarted, 76 s outage; `express-async-errors` was in `package.json` but never `require`d | `require("express-async-errors")`, pool and rejection handlers | Run 3: **16 s**, no restarts |
| **WAF per-IP limit** blocks a shared campus IP | 95 % of requests blocked from one IP at the peak | Campus IP-set exception / per-user rate limit (design C11) | Designed, not deployed |

**Did the results match the expected outcome?**
- **Cost: better than expected.** USD 474/month on average is under half the budget.
- **Peak: not at first.** The platform *survived* the peak before the fix (0.02 % errors), but scaling was wasteful and late, and the database's connection limit was the real risk.
- **Failover: no.** I expected ~60 s of database errors with the API staying up. Instead the API restarted completely, which showed that **"Multi-AZ" on a diagram does not guarantee resilience if the application reacts badly to a failover.**
- **AZ loss, bad release and DLQ: yes,** close to the expected behaviour.

**Errors encountered and how they were resolved**

| Problem | Resolution |
|---|---|
| Calculator first draft **USD 1,073**: Cognito advanced security on, NAT counted 3×, SES 160,000 emails | Checked each line → **USD 465.74** |
| Regional NAT fields would not accept 0 | Priced as one regional NAT across 2 AZs (same cost as 2 zonal) |
| Exam estimate overwrote the baseline Fargate row; "per day" unit | Separate rows via Add service; unit set to per month |
| `-var` syntax error in bootstrap | `-var="github_repo=owner/repo"` |
| k6 "not recognized" after install | Refreshed PATH |
| 3,000-user test still 95 % blocked | `WAF_RATE_LIMIT` variable was missing in GitHub; added it, redeployed, verified the limit with the CLI |
| CloudWatch script failed for two-dimension metrics | Passed dimensions as separate arguments |
| First failover "had no effect" | The reboot was never triggered; used the CLI `--force-failover` and checked RDS events |
| F4 first run fixed before the DLQ | Repeated, waiting for the DLQ, alarm and redrive |

**Observations**
- **The bottleneck was configuration, not capacity.** 2 tasks and a micro database handled the full peak below 20 % CPU.
- **Client latency from Bhutan is mostly network.** Server time was ~17 ms in both runs, while k6 p95 was 1–2 s. That makes the **Region choice** matter for the exam-start experience.
- **Liveness checks must not depend on the database:** a "deep" health check turned a database event into a full service restart.
- **The pipeline's smoke test can pass while ECS is rolling back a bad release,** so the pipeline should wait for a stable deployment.
- **Measured RPO was 0** in every test: no acknowledged autosave was lost.

## 8. Reflection

1. **What did I learn about these AWS services?** I learned how much an architecture costs and *why*: most of the bill is the price of availability (the Multi-AZ standby, a NAT per AZ, tasks in both AZs), not traffic. I learned to read CloudWatch per minute to tell a real capacity limit from a configuration problem, and how ECS health checks, deployment circuit breakers, SQS dead-letter queues and RDS Multi-AZ failover actually behave when something breaks.

2. **What challenges did I encounter?** The calculator was easy to get wrong (an extra zero, a unit of "per day", a feature left enabled), so every line had to be checked. Running a fair load test from one laptop in Bhutan meant accounting for the WAF limit and for network latency. The hardest part was the failover result: the database recovered, but the API didn't, and finding the reason took the ECS events, the stopped-task exit codes and the application logs together.

3. **How would I apply this in a real cloud environment?** Before an exam season I would run the same three steps: a calculator estimate with a budget alert, a load test at the expected peak, and a failure test of the database and an AZ, with a probe that measures downtime and lost writes. I would also keep liveness and readiness checks separate, require async error handling in code review, and make the pipeline wait for a stable deployment.

4. **What would I like to explore next?**
   - **AWS Fault Injection Service** to automate these tests
   - **RDS Proxy** to shorten the failover window further
   - **Aurora Serverless v2** for automatic database scaling
   - **blue/green deployments** with CodeDeploy
   - running the load test from several IPs or from inside AWS, to separate network from server latency

## 9. Conclusion

The objectives were achieved. The exam platform was costed for both load profiles in Singapore: **USD 465.74 in a normal month and USD 518.20 in an exam month, an average of USD 474.48/month, which is 47 % of the USD 1,000 budget, or USD 0.71 per student per year.** Adopting Graviton, a Savings Plan, an RDS Reserved Instance and scheduled scaling would bring it to about USD 391/month. The design was revised for cost, its single points of failure were marked, and every change was logged against Assignment 2.

Deploying and testing the real system showed that **cost was not the problem; configuration was.** The load test proved, through CloudWatch, that auto scaling was mis-sized (2 → 20 tasks at 17 % CPU), and after the fix the same peak ran on 4 tasks. The failure tests found that a database failover restarted the whole API. After two fixes the outage fell from **89 s to 16 s**, with **no acknowledged answer lost in any test** (RPO 0) and a worst-case recovery far inside the 1-hour RTO. The platform also survived the loss of an AZ, rolled back a broken release automatically, and kept every marking job through a Lambda failure.

The key concepts were cost modelling with hidden costs, Multi-AZ resilience, load testing, failure testing with measured RPO and RTO, and Infrastructure as Code. The skills I developed were the Pricing Calculator, Terraform with GitHub Actions and OIDC, k6, CloudWatch analysis, and debugging with ECS events and logs. The verdict is that the platform is **feasible**, on condition that the WAF campus exception and SES production access are in place before the first exam week.