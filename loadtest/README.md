# Load test: prove the bottleneck, fix it, re-test

Rubric: *"Bottleneck proven with CloudWatch, fixed and re-tested; two more reasoned."*

## 0. Prepare (once)
1. Install k6: `winget install k6 --source winget` (or download it from https://k6.io).
2. **Allow your one IP through WAF.** In GitHub → Settings → Variables, set `WAF_RATE_LIMIT` = `2000000`, then re-run the **deploy** workflow. Without this, WAF blocks the test after 2,000 requests per 5 minutes, because all 3,000 virtual students come from your laptop's single IP.
3. Open CloudWatch → Dashboards → **`exam-a3`**. The added widgets are p95 response time, running tasks, RDS credits and memory, and WAF blocks.

## 1. Smoke run (2 min, cheap)
```powershell
k6 run -e BASE_URL=https://<cloudfront-domain> -e STUDENTS=200 -e RAMP=1m -e HOLD=1m loadtest\exam-peak.js
```
Check that the error rate is 0% before running the full test.

## 2. BEFORE: full peak with the as-deployed settings
Settings: `API_MIN_TASKS=2`, `DB_INSTANCE_CLASS=db.t4g.micro`, `PG_POOL_MAX=10`.
```powershell
k6 run -e BASE_URL=https://<cloudfront-domain> loadtest\exam-peak.js --summary-export evidence\loadtest-before.json
```
📸 Screenshot:
- the k6 end-of-test summary (`http_req_failed`, `exam_load_ms` p95, `autosave_ms` p95, thresholds ✓/✗)
- the dashboard **during** the ramp, set to the last 30 min at 1-minute period. These are the graphs that prove the bottleneck:
  - **p95 TargetResponseTime** rises
  - **5XX count** appears
  - **ECS CPU** pinned above 80% while **running tasks** climb only slowly (scale-out lag)
  - **RDS CPU** / **DatabaseConnections** near the limit, **CPUCreditBalance** falling (burstable instance)

**Name the bottleneck from the graphs.** For example: *"ECS CPU hit 95% at minute 2, but the second task only became healthy at minute 6; p95 rose from 120 ms to 4 s and 3% of requests returned 503."* Or: *"RDS CPU at 100% and credit balance falling; DB connections plateaued at 20 (2 tasks × pool 10)."*

## 3. FIX (change one or two knobs, re-run the deploy workflow)
| Bottleneck found | Fix | GitHub variable |
|---|---|---|
| ECS scale-out too slow / CPU pinned | Pre-scale before the exam (scheduled scaling) | `API_MIN_TASKS` = 8 (one-off for the test; production = scheduled action) |
| RDS CPU / credits | Larger, non-throttled class | `DB_INSTANCE_CLASS` = `db.t4g.medium` (or `db.m7g.large`) |
| DB connections capped | Larger pool (stay below the RDS `max_connections`) | `PG_POOL_MAX` = 20 |

Wait until ECS shows the new number of running tasks before re-testing.

## 4. AFTER: re-test with exactly the same command
```powershell
k6 run -e BASE_URL=https://<cloudfront-domain> loadtest\exam-peak.js --summary-export evidence\loadtest-after.json
```
📸 The same k6 summary and the same dashboard graphs. Put **before | after** side by side in the report (p95, error %, CPU, connections).

## 5. Two more bottlenecks: reasoned, not tested
1. **WAF rate limit behind the campus NAT.** 3,000 students on college Wi-Fi share one or a few public IPs. At 100 autosaves/s that is about 30,000 requests per 5 min, far above 2,000, so WAF would block the exam. *Fix:* a higher limit for known campus IP ranges (IP set + scope-down), or rate-limit by forwarded IP or Cognito user rather than source IP.
2. **SES sandbox / sending quota.** Sandbox allows ~200 emails/day at 1/s, but releasing results for 3,000 students needs 3,000 emails. *Fix:* request production access and a higher send rate; send through the SQS notify queue so bursts are smoothed.
3. *(alternative)* **Lambda marker concurrency against DB connections.** 60,000 submissions with unlimited concurrency could open hundreds of connections. *Fix:* reserved concurrency (e.g. 20) and/or RDS Proxy.

## 6. Clean up
Set `WAF_RATE_LIMIT` back to `2000` and the other variables back to the production values. Re-deploy, or run the **destroy** workflow if you're finished.
