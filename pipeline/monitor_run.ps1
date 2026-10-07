# Starts one read-only monitoring pass (scheduled every 30 min). Free model first, local fallback.
$ErrorActionPreference = 'Continue'
$P = $PSScriptRoot; $Root = Split-Path $P -Parent
$OpenCode = "$env:APPDATA\npm\node_modules\opencode-ai\bin\opencode.exe"
$lock = "$P\.monitor.lock"
if ((Test-Path $lock) -and (Get-Process -Id ([int](Get-Content $lock -Raw)) -ErrorAction SilentlyContinue)) { exit 0 }
Set-Content $lock $PID
try {
    foreach ($model in 'opencode/space-bunny-free', 'ollama/devstral:latest') {
        $log = "$P\logs\monitor.log"
        "`n==== $(Get-Date -Format 'yyyy-MM-dd HH:mm') $model" | Add-Content $log -Encoding utf8
        $proc = Start-Process $OpenCode -ArgumentList "run --agent monitor --model $model --dir `"$Root`" `"Run your monitoring pass now.`"" `
            -WorkingDirectory $Root -NoNewWindow -PassThru -RedirectStandardOutput "$log.out" -RedirectStandardError "$log.err"
        if (-not $proc.WaitForExit(15 * 60000)) { & taskkill /PID $proc.Id /T /F 2>&1 | Out-Null }
        Get-Content "$log.out" -Tail 20 -ErrorAction SilentlyContinue | Add-Content $log -Encoding utf8
        # A fresh report means the pass worked; otherwise try the next model.
        $rep = Get-Item "$P\MONITOR_REPORT.md" -ErrorAction SilentlyContinue
        if ($rep -and $rep.LastWriteTime -gt (Get-Date).AddMinutes(-16)) { break }
    }
} finally { Remove-Item $lock -ErrorAction SilentlyContinue }
