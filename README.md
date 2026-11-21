# DSO303 Assignment 3: Cost, Failure and Load Testing of the Exam Platform (ap-southeast-1)

Follow-on to Assignment 2. The same online exam platform (8,000 students, 400 staff) is costed in **Asia Pacific (Singapore)**, optimised against a **USD 1,000/month** budget (averaged over a year), and tested for **peak load** and **failures** against **RPO 5 min**, **RTO 1 h**, **surviving the loss of one AZ** and **5-year file retention**.

## Summary

> *Fill in when the work is finished: 3–5 sentences on what was built, what it costs, what broke under load and how it was fixed.*

## Feasibility verdict

> **Feasible / Not feasible.** Average cost **$___/month** (___% of the $1,000 budget); annual **$___**; **$___ per student per year**.
> Peak of 3,000 students in 5 minutes handled at p95 **___ ms**, **___%** errors, after **<fix>**.
> RDS failover: **___ s** downtime, **0** acknowledged saves lost → RPO ✔ RTO ✔.
> Full reasoning: [`docs/cost-report.md` §5](docs/cost-report.md#5-feasibility-verdict)

## Links

| Item | Link |
|---|---|
| Pricing Calculator: **normal month** | `<paste share link>` |
| Pricing Calculator: **exam month** | `<paste share link>` |
| Optimised estimate(s) | `<paste share link(s)>` |
| Prices checked on | `____-__-__` |
| **Demo video** (≤ 5 min, own voice: one failure test + the load test) | `<YouTube/Drive link>` |

## Repository

| Path | Contents |
|---|---|
| [`architecture/`](architecture/) | Revised cost-optimised diagram with single points of failure marked, [`CHANGELOG.md`](architecture/CHANGELOG.md) against A2, the A2 baseline diagram |
| [`docs/cost-report.md`](docs/cost-report.md) | Cost per service (normal/exam), annual, per student, hidden costs, top 3, comparisons, Region comparison, verdict, optimisations |
| [`docs/calculator-inputs.md`](docs/calculator-inputs.md) | Every quantity entered in the calculator, with assumptions |
| [`docs/services.md`](docs/services.md) | A2 service documentation (role, alternative, configuration) |
| [`infra/`](infra/) | Terraform (Singapore) and [`failure-tests.md`](infra/failure-tests.md): scenarios, expected impact, measured result, fix |
| [`loadtest/`](loadtest/) | k6 peak test [`exam-peak.js`](loadtest/exam-peak.js) and the before/fix/after procedure |
| [`scripts/probe.ps1`](scripts/probe.ps1) | Failure-test probe: measures downtime (RTO) and lost writes (RPO) |
| [`evidence/`](evidence/) | Calculator exports, load-test and probe outputs, screenshots |

## Deploy (Singapore)

1. **Bootstrap** (once). Creates the state bucket and the GitHub OIDC role in ap-southeast-1:
   ```bash
   cd infra/bootstrap
   terraform init
   terraform apply -var="github_repo=<owner>/<repo>"
   ```
2. **GitHub → Settings → Secrets and variables → Actions:**
   - Secret `AWS_ROLE_ARN` = `github_role_arn` output
   - Variables: `TF_STATE_BUCKET` = `state_bucket` output, `ALERT_EMAIL`, `NOTIFY_EMAIL`
   - Optional tuning variables (defaults in brackets): `DB_INSTANCE_CLASS` (db.t4g.micro), `API_MIN_TASKS` (2), `API_MAX_TASKS` (20), `PG_POOL_MAX` (10), `WAF_RATE_LIMIT` (2000)
3. **Push to `main`**, or Actions → **deploy** → Run workflow. The first deploy takes about 25–40 min.
4. Confirm the **SNS** and **SES** emails.

## Tear down
Actions → **destroy** → Run workflow → type `DESTROY`. Delete the bootstrap last (empty the versioned state bucket first, then `terraform destroy` in `infra/bootstrap`).

## Constraints
Shared AWS account on the free plan: RDS backup retention is limited to 1 day in the deployed test stack. The production design and the cost estimate use 7 days. Sign-in uses an `x-user-id` stub (Cognito user pool deployed); the load test uses it to simulate 3,000 distinct students.
