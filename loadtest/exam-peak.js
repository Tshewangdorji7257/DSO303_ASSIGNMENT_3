// k6 load test: exam-week peak for the exam platform (Assignment 3)
//
// Scenario from the brief: 3,000 students start ONE exam within 5 minutes,
// then each autosaves every 30 seconds.
//   - starts:    3,000 / 300 s  ~ 10 exam loads per second during the ramp
//   - autosaves: 3,000 / 30 s   ~ 100 PUTs per second once everyone is in
//
// Run (Windows PowerShell):
//   winget install k6 --source winget
//   k6 run -e BASE_URL=https://<your-cloudfront-domain> loadtest\exam-peak.js
// Smaller dry run first:
//   k6 run -e BASE_URL=https://<domain> -e STUDENTS=200 -e RAMP=1m -e HOLD=2m loadtest\exam-peak.js
//
// IMPORTANT: all virtual students come from YOUR one IP address. Raise the WAF
// rate limit first (GitHub variable WAF_RATE_LIMIT, e.g. 2000000, then re-run deploy),
// or WAF will block the test after 2,000 requests per 5 minutes. Put it back afterwards.
//
// Save the summary for evidence:
//   k6 run ... --summary-export evidence\loadtest-before.json

import http from "k6/http";
import { check, sleep } from "k6";
import { Trend, Rate, Counter } from "k6/metrics";

const BASE = __ENV.BASE_URL;
const STUDENTS = Number(__ENV.STUDENTS || 3000);
const RAMP = __ENV.RAMP || "5m";   // all students start within 5 minutes
const HOLD = __ENV.HOLD || "10m";  // keep autosaving
const EXAM_ID = __ENV.EXAM_ID || "1";

const loadTime = new Trend("exam_load_ms", true);
const saveTime = new Trend("autosave_ms", true);
const saveFailed = new Rate("autosave_failed");
const blocked = new Counter("waf_blocked_403");

export const options = {
  scenarios: {
    exam_peak: {
      executor: "ramping-vus",
      startVUs: 0,
      stages: [
        { duration: RAMP, target: STUDENTS },
        { duration: HOLD, target: STUDENTS },
        { duration: "1m", target: 0 },
      ],
      gracefulRampDown: "30s",
    },
  },
  thresholds: {
    // Targets you can defend in the report: tune if you choose different ones
    http_req_failed: ["rate<0.01"],          // < 1% errors
    exam_load_ms: ["p(95)<2000"],            // exam opens in < 2 s for 95% of students
    autosave_ms: ["p(95)<1000"],             // autosave < 1 s for 95%
  },
  summaryTrendStats: ["avg", "med", "p(90)", "p(95)", "p(99)", "max"],
};

export default function () {
  // Each VU is one student with a stable id, so autosave upserts the same rows
  const student = `load-${__VU}`;
  const headers = { "Content-Type": "application/json", "x-user-id": student };

  // 1) Open the exam (only once per student)
  if (__ITER === 0) {
    const r = http.get(`${BASE}/api/exams/${EXAM_ID}`, { headers, tags: { name: "GET exam" } });
    loadTime.add(r.timings.duration);
    if (r.status === 403) blocked.add(1);
    check(r, { "exam loaded 200": (x) => x.status === 200 });
  }

  // 2) Autosave every 30 s (spread so students do not all save in the same second)
  sleep(20 + Math.random() * 20);
  const body = JSON.stringify({ 1: "Amazon S3", 2: "Amazon RDS", 3: "Amazon SQS", 4: `t${Date.now()}` });
  const s = http.put(`${BASE}/api/exams/${EXAM_ID}/answers`, body, { headers, tags: { name: "PUT autosave" } });
  saveTime.add(s.timings.duration);
  if (s.status === 403) blocked.add(1);
  saveFailed.add(s.status !== 200);
  check(s, { "autosave 200": (x) => x.status === 200 });
}
