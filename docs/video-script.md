# Demo video script (≤ 5 minutes, own voice)

The brief asks for **one failure test + the load test**. The stack is destroyed, so build the video from your **screen recordings and screenshots** (CloudWatch dashboards, probe output, ECS events, k6 summaries). If you recorded the F1 run 3 live, use that clip.

Read it in your own words; the lines below are a guide, not a script to read word for word.

| Time | Show on screen | Say (in your own words) |
|---|---|---|
| **0:00–0:20** | README: title + verdict box | "This is my Assignment 3: the exam platform from Assignment 2, costed in Singapore, load-tested at the exam peak, and failure-tested against RPO 5 minutes and RTO 1 hour." |
| **0:20–0:50** | Revised architecture diagram (zoom on the SPOF tags and the legend cost line) | "Two AZs at every tier. Single points of failure are marked: removed, like the per-AZ NAT and Multi-AZ RDS, or accepted, like the single Region. The design costs USD 474 a month on average, 47 % of the budget." |
| **0:50–1:10** | Calculator summaries (normal $465.74, exam $518.20) | "Normal month 466, exam month 518, 5,694 a year, 71 cents per student. The top three costs are RDS Multi-AZ, NAT and Fargate: fixed availability capacity, which is why exam months only add 11 %." |
| **1:10–2:40** | **Load test**: (1) k6 BEFORE summary; (2) CloudWatch BEFORE graph: ECS tasks 2 → 20, DB connections; (3) the GitHub variables change; (4) k6 AFTER; (5) CloudWatch AFTER: tasks flat at 4 | "3,000 virtual students over 5 minutes, ~100 requests a second. The server stayed at 17 % CPU, but auto scaling jumped from 2 to 20 tasks, 4 to 8 minutes after the ramp, and DB connections rose from 8 to 61. The bottleneck was the scaling target: 300 requests per task. I measured 2,900 per task at 17 % CPU, set the target to 3,000 and pre-scaled to 4 tasks. Re-test: the same peak on 4 tasks, 28 connections, and all thresholds pass." |
| **2:40–2:55** | WAF k6 result (95 % blocked) | "Also proven: WAF's per-IP limit blocked 95 % of requests from one IP. A class behind the campus NAT would be blocked too, so the design exempts campus IP ranges." |
| **2:55–4:30** | **Failure test F1: RDS failover.** (1) probe running green; (2) `reboot-db-instance --force-failover`; (3) probe going red; (4) RDS events started/completed; (5) ECS events: run 1 all 4 tasks replaced, run 3 nothing; (6) the before/after table | "I forced a Multi-AZ failover while a probe autosaved every second. First run: the database switched in 49 seconds, but the API was down for 89, because the ALB health check queried the database and an unhandled async error crashed Node, so ECS replaced every task. I fixed both: a liveness endpoint without the database, and express-async-errors. Third run: 16 seconds, no restarts, and zero acknowledged answers lost. RPO 0, RTO 16 seconds." |
| **4:30–4:50** | Summary table in `infra/failure-tests.md` | "The other tests: losing an AZ gave 34 seconds of intermittent errors; a broken release rolled back automatically in 2 minutes; a broken marker lost nothing thanks to the dead-letter queue." |
| **4:50–5:00** | README verdict | "Verdict: feasible within budget, it meets RPO and RTO, on condition of the WAF and SES changes. Thank you." |

## Recording tips
- **Windows:** Win + Alt + R records the active window (Xbox Game Bar); or use OBS Studio (free) for screen + microphone.
- Put the screenshots in order in a folder and click through them full-screen while you talk.
- Upload to YouTube (Unlisted) or Google Drive (anyone with the link) and paste the link into the README.
- Check the length: **≤ 5:00**.
