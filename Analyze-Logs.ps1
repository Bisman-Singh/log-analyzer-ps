<#
.SYNOPSIS
    Parses log files using regex patterns and generates summary statistics.

.DESCRIPTION
    Analyze-Logs.ps1 reads log files, matches lines against regex patterns,
    filters by date range, and outputs a summary table showing match counts
    and percentages. Useful for quickly analyzing error rates, warning frequency,
    and keyword occurrences in application or system logs.

.PARAMETER LogPath
    Path to the log file or directory of log files to analyze.

.PARAMETER Pattern
    Regex pattern(s) to search for. Accepts multiple patterns separated by commas
    or a predefined set: "errors", "warnings", "all".

.PARAMETER StartDate
    Filter log entries from this date (inclusive). Format: yyyy-MM-dd.

.PARAMETER EndDate
    Filter log entries up to this date (inclusive). Format: yyyy-MM-dd.

.PARAMETER Top
    Number of top results to display. Default: 20.

.PARAMETER Help
    Display help information.

.EXAMPLE
    .\Analyze-Logs.ps1 -LogPath .\app.log -Pattern "ERROR|WARN"

.EXAMPLE
    .\Analyze-Logs.ps1 -LogPath .\logs\ -Pattern errors -StartDate 2026-04-01 -EndDate 2026-04-18

.EXAMPLE
    .\Analyze-Logs.ps1 -LogPath .\app.log -Pattern "timeout,connection refused,404" -Top 10
#>

[CmdletBinding()]
param(
    [string]$LogPath = "",
    [string]$Pattern = "",
    [string]$StartDate = "",
    [string]$EndDate = "",
    [int]$Top = 20,
    [switch]$Help
)

# ─── Help ────────────────────────────────────────────────────────────────────────
if ($Help) {
    @"
Analyze-Logs.ps1 - Log File Pattern Analyzer

USAGE:
    .\Analyze-Logs.ps1 -LogPath <path> -Pattern <pattern> [-StartDate <date>] [-EndDate <date>] [-Top <n>] [-Help]

PARAMETERS:
    -LogPath     Path to log file or directory of log files
    -Pattern     Regex pattern or comma-separated patterns to search for
                 Presets: "errors" = common error patterns
                          "warnings" = common warning patterns
                          "all" = errors + warnings + info
    -StartDate   Filter from this date (yyyy-MM-dd)
    -EndDate     Filter to this date (yyyy-MM-dd)
    -Top         Number of top results to show (default: 20)
    -Help        Show this help message

EXAMPLES:
    .\Analyze-Logs.ps1 -LogPath .\app.log -Pattern "ERROR"
    .\Analyze-Logs.ps1 -LogPath .\logs\ -Pattern errors
    .\Analyze-Logs.ps1 -LogPath .\app.log -Pattern "timeout,404,500" -Top 10
    .\Analyze-Logs.ps1 -LogPath .\app.log -Pattern all -StartDate 2026-04-01
"@
    exit 0
}

# ─── Validate inputs ────────────────────────────────────────────────────────────
if ([string]::IsNullOrWhiteSpace($LogPath)) {
    Write-Error "LogPath is required. Use -Help for usage information."
    exit 1
}

if (-not (Test-Path $LogPath)) {
    Write-Error "Path not found: $LogPath"
    exit 1
}

if ([string]::IsNullOrWhiteSpace($Pattern)) {
    Write-Error "Pattern is required. Use -Help for usage information."
    exit 1
}

# ─── Parse dates ─────────────────────────────────────────────────────────────────
$filterStartDate = $null
$filterEndDate = $null

if (-not [string]::IsNullOrWhiteSpace($StartDate)) {
    try {
        $filterStartDate = [datetime]::ParseExact($StartDate, "yyyy-MM-dd", $null)
    }
    catch {
        Write-Error "Invalid StartDate format. Use yyyy-MM-dd."
        exit 1
    }
}

if (-not [string]::IsNullOrWhiteSpace($EndDate)) {
    try {
        $filterEndDate = [datetime]::ParseExact($EndDate, "yyyy-MM-dd", $null).AddDays(1).AddSeconds(-1)
    }
    catch {
        Write-Error "Invalid EndDate format. Use yyyy-MM-dd."
        exit 1
    }
}

# ─── Resolve pattern presets ─────────────────────────────────────────────────────
$patternList = @()

switch ($Pattern.ToLower()) {
    "errors" {
        $patternList = @(
            @{ Name = "ERROR";             Regex = "(?i)\bERROR\b" },
            @{ Name = "FATAL";             Regex = "(?i)\bFATAL\b" },
            @{ Name = "CRITICAL";          Regex = "(?i)\bCRITICAL\b" },
            @{ Name = "Exception";         Regex = "(?i)\bexception\b" },
            @{ Name = "Failed";            Regex = "(?i)\bfailed\b" },
            @{ Name = "Timeout";           Regex = "(?i)\btimeout\b" },
            @{ Name = "Connection refused"; Regex = "(?i)connection\s+refused" },
            @{ Name = "HTTP 5xx";          Regex = '(?i)\b5\d{2}\b' },
            @{ Name = "Null reference";    Regex = "(?i)null\s*(reference|pointer)" },
            @{ Name = "Out of memory";     Regex = "(?i)out\s+of\s+memory" }
        )
    }
    "warnings" {
        $patternList = @(
            @{ Name = "WARNING";  Regex = "(?i)\bWARN(ING)?\b" },
            @{ Name = "NOTICE";   Regex = "(?i)\bNOTICE\b" },
            @{ Name = "Slow";     Regex = "(?i)\bslow\b" },
            @{ Name = "Retry";    Regex = "(?i)\bretry\b" },
            @{ Name = "Deprecated"; Regex = "(?i)\bdeprecated\b" }
        )
    }
    "all" {
        $patternList = @(
            @{ Name = "ERROR";    Regex = "(?i)\bERROR\b" },
            @{ Name = "FATAL";    Regex = "(?i)\bFATAL\b" },
            @{ Name = "WARNING";  Regex = "(?i)\bWARN(ING)?\b" },
            @{ Name = "INFO";     Regex = "(?i)\bINFO\b" },
            @{ Name = "DEBUG";    Regex = "(?i)\bDEBUG\b" },
            @{ Name = "Exception"; Regex = "(?i)\bexception\b" },
            @{ Name = "Timeout";  Regex = "(?i)\btimeout\b" },
            @{ Name = "HTTP 4xx"; Regex = '(?i)\b4\d{2}\b' },
            @{ Name = "HTTP 5xx"; Regex = '(?i)\b5\d{2}\b' }
        )
    }
    default {
        # Custom pattern(s) - comma-separated
        $customPatterns = $Pattern -split ','
        foreach ($p in $customPatterns) {
            $p = $p.Trim()
            if (-not [string]::IsNullOrWhiteSpace($p)) {
                $patternList += @{ Name = $p; Regex = $p }
            }
        }
    }
}

if ($patternList.Count -eq 0) {
    Write-Error "No valid patterns to search for."
    exit 1
}

# ─── Collect log files ──────────────────────────────────────────────────────────
$logFiles = @()

if (Test-Path $LogPath -PathType Container) {
    $logFiles = Get-ChildItem -Path $LogPath -Filter "*.log" -File -Recurse -ErrorAction SilentlyContinue
    if ($logFiles.Count -eq 0) {
        # Try common log extensions
        $logFiles = Get-ChildItem -Path $LogPath -Include "*.log","*.txt","*.out" -File -Recurse -ErrorAction SilentlyContinue
    }
}
else {
    $logFiles = @(Get-Item -Path $LogPath -ErrorAction Stop)
}

if ($logFiles.Count -eq 0) {
    Write-Error "No log files found at: $LogPath"
    exit 1
}

# ─── Header ─────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "Log Analyzer" -ForegroundColor Cyan
Write-Host "============" -ForegroundColor Cyan
Write-Host "Timestamp:  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
Write-Host "Log source: $LogPath" -ForegroundColor Gray
Write-Host "Files:      $($logFiles.Count)" -ForegroundColor Gray
Write-Host "Patterns:   $($patternList.Count)" -ForegroundColor Gray
if ($filterStartDate) { Write-Host "From:       $($filterStartDate.ToString('yyyy-MM-dd'))" -ForegroundColor Gray }
if ($filterEndDate)   { Write-Host "To:         $($filterEndDate.ToString('yyyy-MM-dd'))" -ForegroundColor Gray }
Write-Host ""

# ─── Common date patterns in log files ──────────────────────────────────────────
$dateRegexPatterns = @(
    '(\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2})',   # ISO 8601: 2026-04-18T10:00:00
    '(\d{2}/\w{3}/\d{4}:\d{2}:\d{2}:\d{2})',       # Apache: 18/Apr/2026:10:00:00
    '(\w{3}\s+\d{1,2}\s+\d{2}:\d{2}:\d{2})',       # Syslog: Apr 18 10:00:00
    '(\d{2}/\d{2}/\d{4}\s+\d{2}:\d{2}:\d{2})'      # US: 04/18/2026 10:00:00
)

function Extract-DateFromLine {
    <#
    .SYNOPSIS
        Attempts to extract a date from a log line.
    #>
    param([string]$Line)

    foreach ($dp in $dateRegexPatterns) {
        if ($Line -match $dp) {
            try {
                $parsed = [datetime]::Parse($Matches[1])
                return $parsed
            }
            catch {
                # Try next pattern
            }
        }
    }
    return $null
}

# ─── Analyze ────────────────────────────────────────────────────────────────────
Write-Host "Analyzing logs..." -ForegroundColor Yellow

$totalLines = 0
$matchedLines = 0
$results = @{}
$fileStats = @{}

# Initialize result counters
foreach ($p in $patternList) {
    $results[$p.Name] = 0
}

foreach ($file in $logFiles) {
    $fileLineCount = 0
    $fileMatchCount = 0

    try {
        $reader = [System.IO.StreamReader]::new($file.FullName)

        while ($null -ne ($line = $reader.ReadLine())) {
            $totalLines++
            $fileLineCount++

            # Date filtering
            if ($filterStartDate -or $filterEndDate) {
                $lineDate = Extract-DateFromLine -Line $line
                if ($lineDate) {
                    if ($filterStartDate -and $lineDate -lt $filterStartDate) { continue }
                    if ($filterEndDate -and $lineDate -gt $filterEndDate) { continue }
                }
            }

            # Pattern matching
            foreach ($p in $patternList) {
                if ($line -match $p.Regex) {
                    $results[$p.Name]++
                    $matchedLines++
                    $fileMatchCount++
                }
            }
        }

        $reader.Close()
        $reader.Dispose()
    }
    catch {
        Write-Warning "Error reading file $($file.Name): $_"
        continue
    }

    $fileStats[$file.Name] = @{
        Lines   = $fileLineCount
        Matches = $fileMatchCount
    }
}

# ─── Display results ────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "Pattern Analysis Results" -ForegroundColor Green
Write-Host "========================" -ForegroundColor Green
Write-Host ""

# Sort by count descending and take top N
$sortedResults = $results.GetEnumerator() | Sort-Object { $_.Value } -Descending | Select-Object -First $Top

# Display table
$headerFmt = "{0,-30} {1,10} {2,10} {3,-30}"
Write-Host ($headerFmt -f "Pattern", "Count", "% Total", "Bar") -ForegroundColor White
Write-Host ("-" * 85) -ForegroundColor Gray

$maxCount = ($sortedResults | Measure-Object -Property Value -Maximum).Maximum
if ($maxCount -eq 0) { $maxCount = 1 }

foreach ($item in $sortedResults) {
    $count = $item.Value
    $pct = if ($totalLines -gt 0) { [math]::Round(($count / $totalLines) * 100, 2) } else { 0 }

    # Build proportional bar
    $barMaxWidth = 25
    $barWidth = [math]::Round(($count / $maxCount) * $barMaxWidth)
    $bar = "#" * $barWidth

    # Color based on relative frequency
    $color = if ($count -eq 0) { "Gray" }
             elseif ($pct -ge 5) { "Red" }
             elseif ($pct -ge 1) { "Yellow" }
             else { "Green" }

    Write-Host ($headerFmt -f $item.Key, $count, "${pct}%", $bar) -ForegroundColor $color
}

Write-Host ""

# ─── File breakdown ──────────────────────────────────────────────────────────────
if ($logFiles.Count -gt 1) {
    Write-Host "File Breakdown" -ForegroundColor Green
    Write-Host "==============" -ForegroundColor Green
    Write-Host ""

    $fileFmt = "{0,-40} {1,10} {2,10}"
    Write-Host ($fileFmt -f "File", "Lines", "Matches") -ForegroundColor White
    Write-Host ("-" * 65) -ForegroundColor Gray

    foreach ($fs in ($fileStats.GetEnumerator() | Sort-Object { $_.Value.Matches } -Descending)) {
        Write-Host ($fileFmt -f $fs.Key, $fs.Value.Lines, $fs.Value.Matches)
    }

    Write-Host ""
}

# ─── Summary ─────────────────────────────────────────────────────────────────────
Write-Host "Summary" -ForegroundColor Green
Write-Host "=======" -ForegroundColor Green
Write-Host "  Total files analyzed: $($logFiles.Count)"
Write-Host "  Total lines scanned: $totalLines"
Write-Host "  Total pattern matches: $matchedLines"
$matchPct = if ($totalLines -gt 0) { [math]::Round(($matchedLines / $totalLines) * 100, 2) } else { 0 }
Write-Host "  Match rate: ${matchPct}%"

# Determine severity level
if ($results.ContainsKey("ERROR") -or $results.ContainsKey("FATAL") -or $results.ContainsKey("CRITICAL")) {
    $errorCount = 0
    foreach ($key in @("ERROR", "FATAL", "CRITICAL")) {
        if ($results.ContainsKey($key)) { $errorCount += $results[$key] }
    }
    if ($errorCount -gt 0) {
        Write-Host "  Error-level matches: $errorCount" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "Done." -ForegroundColor Green
