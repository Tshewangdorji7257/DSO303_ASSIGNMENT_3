# Load test results: exam peak (3,000 students in 5 minutes)

**Tool:** k6 v2.4.0, [`exam-peak.js`](exam-peak.js): 3,000 virtual students ramp up over 5 min, open exam 1, then autosave every 20–40 s for 10 min (~100 req/s).
**Client:** one laptop in Phuntsholing, Bhutan (one public IP). **Target:** `https://dt60dgqnqv83d.cloudfront.net` (ap-southeast-1).
**Server-side evidence:** CloudWatch per-minute metrics in [`evidence/cloudwatch-before.csv`](../evidence/cloudwatch-before.csv) and [`evidence/cloudwatch-after.csv`](../evidence/cloudwatch-after.csv), plus dashboard screenshots `evidence/load-02-cw-before.png` and `evidence/load-05-cw-after.png`.

## Test sequence

| # | Test | Time (BTT) | Settings | Purpose |
|---|---|---|---|---|
| T0 | WAF, 500 students | 22 Nov ~12:20 | WAF 2,000 req/5 min/IP | Prove the per-IP rate limit bottleneck |
| T0b | WAF, 3,000 students | 22 Nov ~12:35 | WAF 2,000 (variable not yet set) | Same at full peak |
| T1 | Smoke, 200 students | 22 Nov ~12:33 | WAF 2,000 (below limit) | Network baseline at 5 req/s |
| **T2** | **BEFORE**, 3,000 students | 22 Nov 13:01–13:17 | WAF 2,000,000 · min 2 / max 20 tasks · **300 req/task/min** · db.t4g.micro · pool 10 | Find the capacity bottleneck |
| **T3** | **AFTER**, 3,000 students | 22 Nov 17:35–17:51 | min **4** / max **8** tasks · **3,000 req/task/min** · db.t4g.micro · pool 10 | Re-test after the fix |

## Bottleneck 1 (proven): WAF per-IP rate limit behind a shared IP
| | T0: 500 students | T0b: 3,000 students |
|---|---|---|
| Requests blocked with 403 | **3,021 / 5,624 (53.7 %)** | **73,613 / 77,371 (95.1 %)** |
| Autosave success | 41 % | **2.6 %** |

3,000 students behind a campus NAT send ~30,000 requests / 5 min from one IP, 15× the 2,000 limit. **Fix (C11):** IP-set exception for campus egress ranges, or rate-limit per user rather than per source IP. For T2/T3 the limit was raised to 2,000,000 (GitHub variable `WAF_RATE_LIMIT`).

## Bottleneck 2 (proven, fixed, re-tested): mis-sized auto scaling

### BEFORE (T2): CloudWatch, minute by minute (excerpt)
| Time | ALB req/min | Server avg / max (s) | ECS tasks | ECS CPU max % | RDS CPU % | DB connections |
|---|---|---|---|---|---|---|
| 13:01 | 672 | 0.007 / 0.043 | 4→2 | 5.8 | 5.4 | 7 |
| 13:05 | 5,366 | 0.015 / 0.064 | **2** | 14.1 | 14.3 | 20 |
| 13:07 | 5,838 | 0.019 / 0.170 | **2** | **17.4** | 16.7 | 20 |
| 13:09 | 5,797 | 0.018 / 0.081 | **11** | 7.2 | 15.1 | 45 |
| 13:12 | 5,809 | 0.018 / 0.169 | **20** | 7.1 | 17.6 | 52 |
| 13:14 | 5,789 | 0.018 / 0.129 | **20** | 3.4 | 15.8 | **61** |
| 13:20 | 0 | – | **20** (still) | 0.8 | 5.7 | 24 |

**Diagnosis:** the request-count target tracking policy was set to **300 requests per task per minute**. At peak each of the 2 tasks served ~2,900 req/min (≈10× the target) at only **17 % CPU**, so auto scaling added tasks up to the **cap of 20**:
- **Late:** new tasks arrived at 13:09–13:12, **4–8 minutes after the ramp** (13:01–13:05), so they did not help the 5-minute burst.
- **Wasteful:** 20 tasks at 3–8 % CPU, still running after the test (scale-in cooldown).
- **Risky:** DB connections rose **8 → 61** (20 tasks × pool 10 = up to 200), towards the ~80-connection limit of db.t4g.micro. Scaling out the API was what threatened the database.
- **Not** the bottleneck: RDS CPU ≤ 19 % with CPU credits steady (77 → 76); server response ≤ 23 ms average; 0 ALB 5xx.

### FIX
Capacity measured in T2: **2 tasks × ~2,900 req/min at 17 % CPU.**
- Scaling target **300 → 3,000 req/task/min** (`API_REQ_PER_TARGET`, new Terraform variable `api_requests_per_target`)
- **Pre-scale to 4 tasks** (2 per AZ) for exam windows (`API_MIN_TASKS=4`), so **one AZ alone can carry the full peak**
- **Max 8 tasks** (`API_MAX_TASKS=8`), keeping DB connections ≤ 80

### AFTER (T3): CloudWatch, minute by minute (excerpt)
| Time | ALB req/min | Server avg / max (s) | ECS tasks | ECS CPU max % | RDS CPU % | DB connections |
|---|---|---|---|---|---|---|
| 17:35 | 965 | 0.008 / 0.042 | 5 (rollout finishing) | 7.9 | 4.8 | 10 |
| 17:37 | 3,358 | 0.014 / 0.131 | **4** | 8.7 | 10.8 | 11 |
| 17:40 | 5,908 | 0.017 / 0.154 | **4** | **16.7** | 17.9 | 14 |
| 17:45 | 5,917 | 0.018 / 0.223 | **4** | 12.9 | 18.6 | **28** |
| 17:49 | 5,890 | 0.017 / 0.087 | **4** | 10.9 | 16.7 | 13 |
| 17:52 | 0 | – | **4** | 0.4 | 5.3 | 2 |

### Before vs after

| Metric | BEFORE | AFTER | Result |
|---|---|---|---|
| Peak load (ALB) | ~5,800 req/min | ~5,900 req/min | same load |
| **ECS tasks at peak** | 2 → **20** (late scale-out) | **4 steady** | **5× fewer tasks**, no scale-out lag |
| **Max DB connections** | **61** | **28** | **−54 %**, well below the micro limit |
| Server response avg (ALB) | 18 ms | 17 ms | unchanged (server was never the limit) |
| ALB 5xx | 0 | 0 | – |
| k6 failed requests | 24 (0.02 %) | 4 (0.005 %) | −83 % (all client/network timeouts; none reached the ALB) |
| k6 autosave p95 / p99 (from Bhutan) | 2.00 s / 4.07 s ✗ | **0.95 s / 1.34 s ✓** | thresholds pass |
| k6 exam load p95 | 1.34 s | 1.13 s ✓ | |

**Honest reading:** server-side latency was ~17 ms in both runs, so most of the client-side p95 improvement comes from the **network path Bhutan → Singapore** (midday vs evening), not the server. The fix's measured effect is **capacity and stability**: the same peak on 4 tasks instead of 20, no late scale-out, and half the DB connections. That also supports the Region/latency analysis in the cost report (`docs/cost-report.md` §4).

**Note:** T3 began while the deploy was finishing (5 tasks at 17:35–17:36 during the rolling update); from 17:37 it ran on the fixed configuration (4 tasks).

## Bottleneck 3 (reasoned): SES sending quota
Result release emails one message per student (3,000 per sitting, up to 60,000 per exam month). The SES sandbox allows ~200 emails/day at 1/s, so result emails would take days or fail. **Fix (C12):** request SES production access with a send rate ≥ 14/s; send through the SQS notify queue so bursts are smoothed; results are also visible in the app.

## Bottleneck 4 (reasoned): marking Lambda concurrency against DB connections
60,000 submissions arriving in bursts could scale the marker Lambda to hundreds of concurrent executions, each opening a DB connection, which would exhaust connections exactly as the API scale-out began to in T2. **Fix:** reserved concurrency (e.g. 20) on the marker and/or RDS Proxy (C13).

## Effect on cost (feeds `docs/cost-report.md`)
- Exam pre-scale needs **2 extra tasks per sitting** (4 total), not 8: pre-scale Fargate falls from 160 to **40 task-runs × 2.5 h** (≈ USD 12.32 → ≈ USD 3.08 per exam month).
- RDS CPU peaked at **19 % on db.t4g.micro**: the design's db.t4g.medium has large headroom. **db.t4g.small** (more memory and connections than micro) is a candidate for a further saving; confirm with a calculator clone and a re-test.