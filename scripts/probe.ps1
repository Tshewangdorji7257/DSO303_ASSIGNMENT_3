<#
  Failure-test probe (Assignment 3). Works in Windows PowerShell 5.1 and PowerShell 7.

  Every second it:
    1. GETs /api/health                -> is the service up?
    2. PUTs an autosave with counter N -> did the write get acknowledged?
  and logs one CSV line per second.

  When you press Ctrl+C (or -Seconds runs out) it prints:
    - DOWNTIME: first failure -> first success after it   (compare with RTO 1 h)
    - DATA LOSS: reads back the saved answer and checks that the last
      acknowledged counter is still in the database      (compare with RPO 5 min)

  Usage:
    .\scripts\probe.ps1 -BaseUrl https://dxxxx.cloudfront.net -Name rds-failover
    (start it, wait ~30 s, trigger the failure, wait until it recovers, then Ctrl+C)

  Output: evidence\probe-<Name>-<time>.csv  (screenshot the summary for the report)
#>
param(
  [Parameter(Mandatory = $true)][string]$BaseUrl,
  [string]$Name = "test",
  [int]$Seconds = 1800,
  [string]$ExamId = "1"
)

$ErrorActionPreference = "Stop"
$BaseUrl = $BaseUrl.TrimEnd("/")
$student = "probe-$Name"
$headers = @{ "x-user-id" = $student }
New-Item -ItemType Directory -Force evidence | Out-Null
$csv = "evidence\probe-$Name-$(Get-Date -Format yyyyMMdd-HHmmss).csv"
"time,health_status,health_ms,save_status,save_ms,counter" | Out-File $csv -Encoding utf8

function Call($method, $url, $body) {
  $sw = [Diagnostics.Stopwatch]::StartNew()
  try {
    if ($body) {
      $r = Invoke-WebRequest -Uri $url -Method $method -Headers $headers -Body $body `
             -ContentType "application/json" -TimeoutSec 5 -UseBasicParsing
    } else {
      $r = Invoke-WebRequest -Uri $url -Method $method -Headers $headers -TimeoutSec 5 -UseBasicParsing
    }
    return @([int]$r.StatusCode, $sw.ElapsedMilliseconds)
  } catch {
    $code = 0
    if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode }
    return @($code, $sw.ElapsedMilliseconds)
  }
}

$counter = 0; $lastAck = 0
$firstFail = $null; $recovered = $null; $failedSaves = 0
Write-Host "Probing $BaseUrl as $student. Trigger the failure now; Ctrl+C when recovered." -ForegroundColor Cyan

try {
  for ($i = 0; $i -lt $Seconds; $i++) {
    $t0 = Get-Date
    $counter++
    $h = Call "GET" "$BaseUrl/api/health" $null
    $s = Call "PUT" "$BaseUrl/api/exams/$ExamId/answers" ("{""1"":""probe-$counter""}")
    $ok = ($h[0] -eq 200 -and $s[0] -eq 200)
    if ($s[0] -eq 200) { $lastAck = $counter } else { $failedSaves++ }

    if (-not $ok -and -not $firstFail) { $firstFail = $t0 }
    if ($ok -and $firstFail -and -not $recovered) { $recovered = $t0 }

    $line = "{0},{1},{2},{3},{4},{5}" -f $t0.ToString("HH:mm:ss"), $h[0], $h[1], $s[0], $s[1], $counter
    $line | Out-File $csv -Append -Encoding utf8
    $color = if ($ok) { "Green" } else { "Red" }
    Write-Host $line -ForegroundColor $color

    $wait = 1000 - ((Get-Date) - $t0).TotalMilliseconds
    if ($wait -gt 0) { Start-Sleep -Milliseconds $wait }
  }
}
finally {
  Write-Host "`n===== SUMMARY ($Name) =====" -ForegroundColor Cyan
  if ($firstFail -and $recovered) {
    $down = [math]::Round(($recovered - $firstFail).TotalSeconds)
    Write-Host ("DOWNTIME: {0} s  (first failure {1}, recovered {2})  vs RTO 3600 s" -f `
      $down, $firstFail.ToString("HH:mm:ss"), $recovered.ToString("HH:mm:ss"))
  } elseif ($firstFail) {
    Write-Host "DOWNTIME: failure started $($firstFail.ToString('HH:mm:ss')) and had NOT recovered when the probe stopped"
  } else {
    Write-Host "DOWNTIME: 0 s (no failed request)"
  }
  Write-Host "Failed autosaves (not acknowledged, client would retry): $failedSaves"

  # RPO check: is the last ACKNOWLEDGED write still in the database?
  try {
    $exam = Invoke-RestMethod -Uri "$BaseUrl/api/exams/$ExamId" -Headers $headers -TimeoutSec 10
    $saved = ($exam.saved | Where-Object { $_.question_id -eq 1 }).answer
    $savedN = [int]($saved -replace "probe-", "")
    $lost = [math]::Max(0, $lastAck - $savedN)
    Write-Host "DATA LOSS: last acknowledged save #$lastAck, database has #$savedN -> $lost acknowledged saves lost (~$lost s)  vs RPO 300 s"
  } catch {
    Write-Host "DATA LOSS: could not read back (service still down?) - run the probe again after recovery"
  }
  Write-Host "CSV: $csv"
}
