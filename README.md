# Log Analyzer

A PowerShell script that parses log files using regex patterns, counts occurrences, filters by date range, and generates summary tables with visual bars.

## Features

- Parse log files with custom or predefined regex patterns
- Predefined pattern sets: `errors`, `warnings`, `all`
- Date range filtering with auto-detection of common log date formats
- Proportional bar charts in console output
- Per-file breakdown when analyzing directories
- Color-coded output by severity
- Handles large files efficiently using StreamReader
- Top N results display

## Requirements

- PowerShell 5.1+ (Windows) or PowerShell 7+ (cross-platform)

## Usage

```powershell
# Search for a pattern in a log file
.\Analyze-Logs.ps1 -LogPath .\app.log -Pattern "ERROR"

# Use predefined error pattern set
.\Analyze-Logs.ps1 -LogPath .\app.log -Pattern errors

# Multiple custom patterns
.\Analyze-Logs.ps1 -LogPath .\app.log -Pattern "timeout,connection refused,404"

# Filter by date range
.\Analyze-Logs.ps1 -LogPath .\logs\ -Pattern all -StartDate 2026-04-01 -EndDate 2026-04-18

# Show top 10 results
.\Analyze-Logs.ps1 -LogPath .\app.log -Pattern errors -Top 10

# Analyze all log files in a directory
.\Analyze-Logs.ps1 -LogPath .\logs\ -Pattern warnings

# Show help
.\Analyze-Logs.ps1 -Help
```

### Parameters

| Parameter | Description |
|-----------|-------------|
| `-LogPath` | Path to log file or directory |
| `-Pattern` | Regex pattern, comma-separated patterns, or preset (`errors`, `warnings`, `all`) |
| `-StartDate` | Filter from this date (`yyyy-MM-dd`) |
| `-EndDate` | Filter to this date (`yyyy-MM-dd`) |
| `-Top` | Number of top results to show (default: 20) |
| `-Help` | Show help information |

### Pattern Presets

| Preset | Patterns Included |
|--------|-------------------|
| `errors` | ERROR, FATAL, CRITICAL, Exception, Failed, Timeout, Connection refused, HTTP 5xx, Null reference, Out of memory |
| `warnings` | WARNING/WARN, NOTICE, Slow, Retry, Deprecated |
| `all` | ERROR, FATAL, WARNING, INFO, DEBUG, Exception, Timeout, HTTP 4xx, HTTP 5xx |

## Sample Output

```
Log Analyzer
============
Timestamp:  2026-04-18 10:00:00
Log source: ./app.log
Files:      1
Patterns:   10

Analyzing logs...

Pattern Analysis Results
========================

Pattern                             Count    % Total Bar
-------------------------------------------------------------------------------------
ERROR                                 342      1.71% ####################
Exception                             187      0.94% ###########
Timeout                                89      0.45% #####
Failed                                 67      0.34% ####
HTTP 5xx                               45      0.23% ###
FATAL                                  12      0.06% #
Connection refused                      8      0.04% #
CRITICAL                                3      0.02%
Out of memory                           1      0.01%
Null reference                          0         0%

Summary
=======
  Total files analyzed: 1
  Total lines scanned: 20000
  Total pattern matches: 754
  Match rate: 3.77%
  Error-level matches: 357
```



<sub><sup>Originally developed and tested locally during learning. Later organized and pushed to GitHub for portfolio visibility.</sup></sub>
