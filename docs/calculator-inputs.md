# AWS Pricing Calculator inputs: Singapore (ap-southeast-1)

Use this sheet to fill in https://calculator.aws. Create **two estimates** with the Region set to **Asia Pacific (Singapore)**:

- `Exam platform - NORMAL month`
- `Exam platform - EXAM month`

Then save, **share** each one (copy the link into `README.md`) and **export** it (CSV and PDF) into `evidence/`.

> **Prices checked on:** `____-__-__` (write the date you built the estimates)

## Workload assumptions

| Assumption | Normal month | Exam month | Reasoning |
|---|---|---|---|
| Users | 8,000 students + 400 staff | same | Brief |
| Concurrent users | 400 average over 12 active hours/day | 400 background **plus** exam sessions | Brief: 300–500 normal |
| API requests from normal use | 400 × 2 req/min × 60 × 12 h × 30 d ≈ **17.3 M** | 17.3 M | Browsing, practice quizzes, results |
| Exam sessions | 0 | **20 sessions** × 3,000 students × 90 min | 10 exam days × 2 sittings |
| API requests per exam sitting | – | 1 load + 180 autosaves (every 30 s for 90 min) + submit + result ≈ 185 | Autosave is the main load |
| Exam API requests | 0 | 3,000 × 185 × 20 ≈ **11.1 M** | |
| **Total API requests** | **17.3 M** | **28.4 M** | |
| Peak request rate | ~15 req/s | ~**100 req/s** autosave + 10 exam starts/s | Brief: 3,000 starts in 5 min |
| Average API response | 2 KB | 2 KB | JSON |
| Frontend | 16 KB `index.html` (fonts come from Google) | same | Measured |
| Assignment uploads | 8,000 × 2/month × 10 MB avg = **160 GB/month** | 160 GB | PDFs/ZIPs up to 50 MB |
| Exam submissions (marking jobs) | 0 | 3,000 × 20 = **60,000** | |
| Emails | 16,000 upload notices | 16,000 + 60,000 result emails | |

---

## Service-by-service inputs

### 1. Amazon ECS on AWS Fargate (API)
| Field | Normal | Exam | Notes |
|---|---|---|---|
| OS / architecture | Linux / x86 | Linux / x86 | *Optimisation: ARM (Graviton)* |
| Tasks | 2 | 2 baseline + 8 extra during exams | 2 = one per AZ (survives the loss of an AZ) |
| Duration | 730 h each | 2 × 730 h **+** 8 × 20 sittings × 2.5 h (pre-scale 30 min + 90 min exam + buffer) | Enter as average tasks if needed: exam month ≈ 2 + 400/730 ≈ **2.55** tasks |
| vCPU / memory | 0.5 vCPU / 1 GB | same | From `compute.tf` |
| Ephemeral storage | 20 GB (free) | same | |

> The "8 extra tasks" figure comes from the load test. Update it after Phase 3.

### 2. Amazon RDS for PostgreSQL
| Field | Normal | Exam | Notes |
|---|---|---|---|
| Instance | **db.t4g.medium** (2 vCPU, 4 GB) | same (or a larger class if the load test shows it is needed) | Deployed demo used db.t4g.micro; the load test decides |
| Deployment | **Multi-AZ** (one standby) | Multi-AZ | Survives the loss of an AZ, RPO ≈ 0 |
| Pricing | On-Demand | On-Demand | *Optimisation: 1-year Reserved Instance* |
| Storage | gp3, 50 GB | gp3, 50 GB | |
| Backup storage beyond the free amount | 10 GB | 10 GB | 7-day PITR; free up to 100% of the DB size |

### 3. Elastic Load Balancing: Application Load Balancer
| Field | Normal | Exam |
|---|---|---|
| Number of ALBs | 1 | 1 |
| Processed bytes | 17.3 M × 3 KB ≈ 52 GB/month ≈ **0.07 GB/hour** | 28.4 M × 3 KB ≈ 85 GB ≈ **0.12 GB/hour** |
| New connections | 2 per second | 5 per second |
| Connection duration | 30 s | 30 s |
| Rule evaluations | 2 per request (header rule + default) | same |

### 4. Amazon VPC: NAT gateway  *(hidden cost)*
| Field | Normal | Exam | Notes |
|---|---|---|---|
| NAT gateways | **2** (one per AZ) | 2 | Removes the NAT single point of failure |
| Hours | 730 each | 730 each | |
| Data processed | **10 GB** | **30 GB** | ECR image pulls (~70 MB per task start), CloudWatch Logs, Secrets Manager/SQS/SES API calls. S3 traffic uses the free gateway endpoint |

### 5. Amazon VPC: public IPv4 addresses  *(hidden cost)*
| Field | Normal | Exam | Notes |
|---|---|---|---|
| In-use public IPv4 addresses | 4 | 4 | 2 NAT Elastic IPs + 2 ALB node IPs, charged per hour since 2024 |

### 6. Amazon CloudFront  *(data transfer out = hidden cost)*
| Field | Normal | Exam | Notes |
|---|---|---|---|
| Data transfer out to the internet | **40 GB** (Region: India / Asia Pacific) | **65 GB** | 17.3 M / 28.4 M × 2 KB + static |
| Data transfer out to origin | 52 GB | 85 GB | Requests forwarded to the ALB |
| HTTPS requests | **17.6 M** | **28.8 M** | API + static |

> The CloudFront always-free tier covers 1 TB out and 10 M requests per month. Show the estimate **without** it, then mention it as a saving.

### 7. AWS WAF
| Field | Normal | Exam |
|---|---|---|
| Web ACLs | 1 | 1 |
| Rules | 3 (rate limit + 2 AWS managed rule groups) | 3 |
| Requests | 17.6 M | 28.8 M |

### 8. Amazon S3
**Frontend bucket:** S3 Standard 0.001 GB, 10,000 GET requests (CloudFront cache misses).

**Uploads bucket.** Lifecycle: Standard → Standard-IA at 30 days → Glacier Flexible Retrieval at 180 days → expire at 5 years. Enter the **end of year 1** for the annual cost, and say in the report what happens at year 5:

| Storage class | Year 1 (month 12) | Year 5 steady state |
|---|---|---|
| S3 Standard | 160 GB | 160 GB |
| S3 Standard-IA | 800 GB | 800 GB |
| S3 Glacier Flexible Retrieval | 960 GB | ~8,640 GB |
| PUT requests | 16,000/month | 16,000/month |
| Lifecycle transitions | 16,000 to IA + 16,000 to Glacier per month | same |
| GET requests | 20,000/month (tutors downloading) | same |

*Comparison for the report: the same data entirely in S3 Standard, and entirely in Intelligent-Tiering.*

### 9. Amazon CloudWatch  *(Logs = hidden cost)*
| Field | Normal | Exam | Notes |
|---|---|---|---|
| Logs ingested | **3 GB** | **6 GB** | API + Lambda logs + Container Insights performance events |
| Logs stored | 3 GB (30-day retention) | 6 GB | |
| Standard metric alarms | 6 | 6 | `monitoring.tf` |
| Dashboards | 1 | 1 | |
| Custom metrics | 0 | 0 | Container Insights is billed as logs |

### 10. AWS KMS  *(requests = hidden cost)*
| Field | Normal | Exam | Notes |
|---|---|---|---|
| Customer-managed keys | 1 | 1 | RDS + uploads bucket |
| Symmetric requests | **60,000** | **150,000** | S3 Bucket Key keeps upload requests low; Secrets Manager decrypts at each task/Lambda start; first 20,000 free |

### 11. Backups  *(hidden cost)*
| Item | Normal | Exam | Notes |
|---|---|---|---|
| RDS backup storage (beyond free) | 10 GB | 10 GB | Entered in RDS above |
| AWS Backup: RDS snapshot, cold storage | 20 GB × yearly copies (year 1 = 20 GB) | same | 5-year record retention |
| S3 versioning (non-current versions) | 5 GB Standard | 5 GB | Overwritten uploads, 365-day expiry |

### 12. Asynchronous and other services
| Service | Normal | Exam | Notes |
|---|---|---|---|
| **SQS** standard requests | 2 M | 2.2 M | Lambda long-polling (~1.3 M empty receives/month) + messages; 1 M free |
| **Lambda** marker | 0 | 6,000 invocations × 2 s × 256 MB | Batch size 10 |
| **Lambda** notify | 16,000 × 0.5 s × 128 MB | same | |
| **SES** outbound emails | 16,000 | 76,000 | |
| **Secrets Manager** | 1 secret, 50,000 API calls | 1 secret, 100,000 calls | |
| **ECR** storage | 1 GB | 1 GB | Last 10 images |
| **Route 53** | 1 hosted zone, 1 M queries | same | Alias queries to CloudFront are free |
| **Cognito** | 8,400 MAU (Essentials/Lite) | same | Check the free tier |
| **CloudTrail** | 1 management trail (free) + S3 storage 1 GB | same | |
| **ACM** | public certificates | free | |
| **Data transfer between AZs** | 25 GB | 40 GB | API task in AZ-b → RDS primary in AZ-a |

---

## Optimisation estimates (clone the estimate, change ONE thing, record the new total)

| # | Change | Where in the calculator | Expected effect |
|---|---|---|---|
| O1 | Fargate **ARM (Graviton)** | ECS Fargate → architecture ARM | About 20% off compute |
| O2 | **Compute Savings Plan** (1 yr, no upfront) on the 2 baseline tasks | Fargate → Savings Plans | Roughly 15–20% off the baseline |
| O3 | **RDS Reserved Instance** (1 yr, no upfront), Multi-AZ | RDS → pricing model | Roughly 30% off the instance |
| O4 | **Scheduled scaling**: extra tasks only during the 2.5 h exam windows (already assumed), compared with a fixed 10 tasks all month | Fargate task count | Shows why scheduled pre-scale beats over-provisioning |
| O5 | **VPC interface endpoints** (ECR api/dkr, Logs, Secrets Manager, SQS) instead of NAT data | VPC → endpoints: 5 × 2 AZs × 730 h | Usually **more** expensive at this traffic level, which supports keeping NAT |
| O6 | **Single NAT** | NAT gateways = 1 | Saves money but reintroduces a single point of failure (record as *rejected*) |
| O7 | Uploads in **Intelligent-Tiering** vs **Standard only** vs the lifecycle above | S3 | Shows the lifecycle is cheapest for predictable ageing |

## Annual and per-student formulas

- **Annual** = 10 × NORMAL + 2 × EXAM
- **Average per month** = Annual ÷ 12 (compare with **USD 1,000**)
- **Cost per student per year** = Annual ÷ 8,000
- **Cost per exam sitting** = (EXAM − NORMAL) ÷ (20 sittings × 3,000 students)
