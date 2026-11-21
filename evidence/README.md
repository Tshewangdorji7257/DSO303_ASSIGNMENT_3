# Evidence: Assignment 3

Name files with the prefix shown, so they sort in report order. Tick each one when it's added.

## Calculator (costed estimate)
- [ ] `calc-01-normal-summary.png`: normal month estimate summary (total, Region = Singapore, date)
- [ ] `calc-02-exam-summary.png`: exam month estimate summary
- [ ] `calculator-normal.csv` / `.pdf`: export of the normal month
- [ ] `calculator-exam.csv` / `.pdf`: export of the exam month
- [ ] `calc-03-opt-<name>.png`: one per optimisation (new total visible)
- [ ] `calc-04-mumbai.png`: same estimate with the Region switched to Mumbai
- [ ] `latency-cloudping.png`: cloudping.info from Bhutan (Singapore vs Mumbai)

## Deployment (Singapore)
- [ ] `deploy-01-actions-green.png`: green deploy run
- [ ] `deploy-02-site.png`: site on CloudFront, Region ap-southeast-1 in the console

## Load test
- [ ] `loadtest-before.json` + `load-01-k6-before.png`: k6 summary before the fix
- [ ] `load-02-cw-before.png`: CloudWatch dashboard during the before-test (the bottleneck)
- [ ] `load-03-fix.png`: the change made (GitHub variables / ECS tasks / RDS class)
- [ ] `loadtest-after.json` + `load-04-k6-after.png`: k6 summary after the fix
- [ ] `load-05-cw-after.png`: CloudWatch dashboard during the after-test

## Failure tests (one set per scenario)
- [ ] `fail-F1-probe.png` + `probe-rds-failover-*.csv` + `fail-F1-rds-events.png` (+ primary AZ before/after)
- [ ] `fail-F2-probe.png` + `fail-F2-targets.png` + `fail-F2-ecs-events.png` + alarm email
- [ ] `fail-F3-probe.png` + `fail-F3-rollback.png`
- [ ] `fail-F4-dlq.png` + `fail-F4-alarm.png` + `fail-F4-redrive.png`
- [ ] *(optional)* `fail-F5-pitr.png`

## Cost tracking (optional, strong evidence)
- [ ] `billing-cost-explorer.png`: actual spend during testing vs the estimate
- [ ] `budget-alert.png`: the AWS Budget you set
