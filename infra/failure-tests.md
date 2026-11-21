# Failure test scenarios

**Region:** ap-southeast-1 (Singapore), two AZs.
**Targets:** RPO 5 minutes, RTO 1 hour, survive the loss of one AZ, files kept for 5 years.

**How each test is measured.** Run `scripts/probe.ps1` during every test. Each second it calls `/api/health` and sends an autosave, and logs the result to `evidence/probe-<name>-*.csv`. When stopped, it prints:
- **DOWNTIME**: first failed request → first success (compare with RTO)
- **DATA LOSS**: last *acknowledged* autosave compared with what is in the database (compare with RPO)

```powershell
.\scripts\probe.ps1 -BaseUrl https://<cloudfront-domain> -Name <scenario>
# wait ~30 s, trigger the failure, wait for recovery, then Ctrl+C
```

📸 For **every** scenario, screenshot: (1) the probe summary, (2) the AWS console event that proves the failure happened, (3) any alarm email.

---

## F1: RDS primary fails (AZ failure of the database)

| | |
|---|---|
| **Trigger** | RDS → `exam-a3-db` → Actions → **Reboot** → tick **Reboot with failover** |
| **Expected impact** | The writer moves to the standby in the other AZ. The DNS endpoint is unchanged and points to the new primary. Autosaves fail for about 60–120 s, while the API's `pg` pool reconnects. **No committed data lost**, because replication is synchronous |
| **Expected vs targets** | RPO ≈ 0 (target 5 min). RTO ≈ 1–2 min (target 60 min) |
| **Evidence** | Probe summary; RDS → Logs & events: *"Multi-AZ instance failover started/completed"*; the Configuration tab's Primary AZ changes (screenshot before and after) |
| **Measured** | Downtime: `___ s` · Acknowledged saves lost: `___` · Primary AZ: `______` → `______` |
| **Verdict** | ☐ Meets RPO ☐ Meets RTO |
| **Likely fix / improvement** | Retry autosave in the browser (the frontend already retries every 30 s). Add **RDS Proxy** to keep client connections open during failover (cuts the error window to a few seconds). Lower the DNS-cache TTL in the API |

## F2: Loss of one AZ for compute (ECS tasks in AZ-a)

| | |
|---|---|
| **Trigger** | **Option A (simple):** ECS → `exam-a3-cluster` → `exam-a3-api` → Tasks → **stop the task(s) in AZ-a** (check the task's subnet/AZ). **Option B (closer to a real AZ outage):** VPC → Network ACLs → create a NACL that **denies all** inbound/outbound and associate it with the **AZ-a app subnet** (`exam-a3-app-1`). Remove it afterwards! |
| **Expected impact** | ALB health checks (15 s interval, 3 failures) mark AZ-a targets unhealthy within ~45 s; traffic continues on AZ-b. ECS starts replacement tasks (in AZ-b if AZ-a is blocked). Some requests may fail or slow while the remaining task carries all the load |
| **Expected vs targets** | Downtime ≈ 0–45 s of partial errors. RPO 0 (the database is untouched) |
| **Evidence** | Probe summary; EC2 → Target groups → Targets (one unhealthy/draining); ECS → service Events ("has started 1 tasks"); the CloudWatch `UnHealthyHostCount` alarm email |
| **Measured** | Downtime: `___ s` · Errors: `___` · Time to replacement task healthy: `___ s` |
| **Verdict** | ☐ Survives AZ loss ☐ Meets RTO |
| **Likely fix / improvement** | Keep **min tasks ≥ 2 per AZ** in exam windows, so one AZ alone can carry the peak. Shorter health-check interval. Add an AZ-aware alarm |

## F3: Bad deployment (broken API release)

| | |
|---|---|
| **Trigger** | Push a commit that breaks the health check, e.g. in `server.js` change `res.send("ok")` to `res.status(500).send("broken")`. The pipeline deploys it |
| **Expected impact** | New tasks fail ALB health checks. The **ECS deployment circuit breaker** stops the rollout and **rolls back** to the last working task definition. Old tasks keep serving, so users see no outage. Note: `terraform apply` does not wait for the ECS rollout, so the smoke test may still pass against the old tasks; the rollback shows up in the ECS service events |
| **Expected vs targets** | Downtime 0 s. RPO 0. Time to automatic rollback ≈ 5–10 min |
| **Evidence** | Probe summary (should stay green); ECS → service → Deployments/Events: *"deployment failed … rolling back"*; `HTTPCode_Target_5XX` / unhealthy-target alarm |
| **Measured** | Downtime: `___ s` · Rollback completed after: `___ min` |
| **Verdict** | ☐ No user impact |
| **Likely fix / improvement** | Add a staging environment or blue/green (CodeDeploy), and run the smoke test **before** shifting traffic. Revert the bad commit |

## F4: Marking pipeline failure (poison message / broken Lambda)

| | |
|---|---|
| **Trigger** | Lambda → `exam-a3-marker` → Configuration → Environment variables → change `PGHOST` to `wrong-host`. Then submit an exam on the site |
| **Expected impact** | The submit API still returns `{"queued":true}`, so **students are not affected**. The Lambda fails and SQS retries 5 times, then the message moves to the **marking DLQ**. The `exam-a3-marking-dlq-not-empty` alarm emails the ops team. No result is lost |
| **Expected vs targets** | Student-facing downtime 0. Marking delayed until fixed. RPO 0 (the message is kept in the DLQ for 14 days) |
| **Recovery** | Restore `PGHOST` (or re-run the pipeline), then SQS → `exam-a3-marking-dlq` → **Start DLQ redrive** back to the source queue. The result appears |
| **Evidence** | SQS DLQ "Messages available = 1"; alarm email; Lambda error logs; result shown after the redrive |
| **Measured** | Time to alarm: `___ min` · Time to recover after the fix: `___ min` · Results lost: `___` |
| **Verdict** | ☐ No data lost ☐ Alarm fired |
| **Likely fix / improvement** | Alarm on Lambda `Errors` (faster than waiting for the DLQ); a runbook for redrive; idempotent marking (already an upsert) |

## F5 (optional, strongest RTO evidence): accidental data loss → point-in-time restore

| | |
|---|---|
| **Trigger** | Note the time T. Delete a student's answers (e.g. a test row) to simulate a bad change. RDS → `exam-a3-db` → Actions → **Restore to point in time** → T − 1 min → new instance `exam-a3-db-restore` |
| **Expected impact** | Restore time ≈ 15–30 min for a small DB. Then point the app at the new endpoint (Terraform variable or rename). Data is recovered to within minutes of T |
| **Expected vs targets** | RPO ≤ 5 min (PITR granularity). RTO = restore time + switch-over, target ≤ 60 min |
| **Measured** | Restore started `__:__`, available `__:__` → `___ min`. Data recovered: ☐ |
| **Likely fix / improvement** | Script the switch-over; consider Aurora (faster clone/backtrack) if RTO becomes tight as the DB grows |

---

## Summary table (fill in after the tests)

| # | Scenario | Measured downtime | Data lost | RPO 5 min | RTO 1 h | Fix |
|---|---|---|---|---|---|---|
| F1 | RDS failover | | | | | RDS Proxy |
| F2 | AZ-a compute loss | | | | | ≥ 2 tasks per AZ in exams |
| F3 | Bad deployment | | | | | Blue/green + staging |
| F4 | Marking Lambda failure | | | | | Lambda error alarm + redrive runbook |
| F5 | PITR restore | | | | | Scripted switch-over |
