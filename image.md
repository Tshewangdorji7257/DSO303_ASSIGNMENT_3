Next: Phase 1, the Pricing Calculator (no AWS account needed)

1. Amazon RDS for PostgreSQL
![alt text](image.png)

aws fargate
![alt text](image-1.png)

3. Amazon Virtual Private Cloud (VPC)
![alt text](image-2.png)

4. Elastic Load Balancing
![alt text](image-3.png)

5. Amazon CloudFront
![alt text](image-4.png)

6. AWS WAF
![alt text](image-5.png)
![alt text](image-6.png)

7. Amazon S3
![alt text](image-7.png)

8. Amazon CloudWatch
![alt text](image-8.png)

1. AWS Key Management Service (KMS)
![alt text](image-9.png)

2. Amazon Simple Queue Service (SQS)
![alt text](image-10.png)

3. AWS Lambda
![alt text](image-11.png)

4. Amazon Simple Email Service (SES)
![alt text](image-12.png)

5. AWS Secrets Manager
![alt text](image-13.png)

6. Amazon Elastic Container Registry (ECR)
![alt text](image-14.png)

7. Amazon Route 53
![alt text](image-15.png)

8. Amazon Cognito
![alt text](image-16.png)

9. AWS Backup
![alt text](image-17.png)

10. AWS Data Transfer
![alt text](image-18.png)

Then finish the NORMAL month
Save and view summary. Check that every service has Region = Singapore.
📸 Screenshot the summary showing the monthly total, the 12-month total and the Region.
![alt text](image-20.png)


the Exam month
![alt text](image-21.png)

L1: latency from Bhutan

On your laptop in Phuntsholing, open https://www.cloudping.info → HTTP Ping. Note Singapore (ap-southeast-1) and Mumbai (ap-south-1) in ms. Run it 3 times and take the median.
📸 Screenshot it.
latency1
![alt text](image-22.png)

latency2
![alt text](image-23.png)

latency3
![alt text](image-24.png)


2. Validate and bootstrap (5 min)
![alt text](image-25.png)
![alt text](image-26.png)

Next: GitHub settings

In Tshewangdorji7257/DSO303_ASSIGNMENT_3 → Settings → Secrets and variables → Actions:

Secrets tab → New repository secret
![alt text](image-27.png)
![alt text](image-28.png)
![alt text](image-34.png)

Then deploy
Actions → deploy → Run workflow → main → Run workflow.
![alt text](image-29.png)

Now the load test: 2 marks, and the hardest criterion to get full marks on. Follow this order.

Step 1: Install k6 (2 min)
![alt text](image-30.png)


Step 2 (optional, worth doing): prove the WAF bottleneck first (5 min)

The WAF rate limit is still 2,000 requests per 5 min per IP. Run a small test from your one IP. It acts like a class sharing one campus IP, and WAF will block it, which turns this reasoned bottleneck into a proven one:
![alt text](image-31.png)

CloudWatch → Dashboards → exam-a3, time range last 30 minutes → screenshot the "WAF blocked requests (rate limit)" graph. It should show a spike starting a minute or two into the test. 
![alt text](image-32.png)

Next: step 3, raise the WAF limit
GitHub → Settings → Secrets and variables → Actions → Variables → New repository variable: WAF_RATE_LIMIT = 2000000
Actions → deploy → Run workflow (about 3–5 min).
When it's green, run the smoke test:
![alt text](image-33.png)


Next: the full BEFORE test (3,000 students, about 16 min)

Settings unchanged: 2 tasks, db.t4g.micro, pool 10.

Open the dashboard first: CloudWatch → Dashboards → exam-a3 → time range 1h, refresh 1 min.
![alt text](image-35.png)

k6 summary
![alt text](image-36.png)

Next: pull the CloudWatch numbers for the test window

The test ran from about 13:01 to 13:18 your time (07:01–07:18 UTC). If you took dashboard screenshots, send them. In any case, run this script. It saves the key metrics minute by minute to a CSV, which is hard evidence, and I can analyse it exactly:
![alt text](image-38.png)
![alt text](image-37.png)

The fix: right-size scaling from the measured capacity

2 tasks handled 2,900 req/min each at 17% CPU. So:

Target 3,000 requests per task per minute (about 50/s, still only ~20% CPU)
Pre-scale to 4 tasks (2 per AZ) during exams, so one AZ alone can carry the whole peak
Max 8 tasks, which keeps DB connections ≤ 80

The 300 target is currently hard-coded, so make it a GitHub variable. Three small edits:
![alt text](image-39.png)

Then:

Add GitHub Variables
![alt text](image-40.png)