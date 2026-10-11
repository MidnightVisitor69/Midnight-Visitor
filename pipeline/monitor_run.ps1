# Starts one read-only monitoring pass (scheduled every 30 min). Free model first, local fallback.
$ErrorActionPreference = 'Continue'
$P = $PSScriptRoot; $Root = Split-Path $P -Parent
$OpenCode = "$env:APPDATA\npm\node_modules\opencode-ai\bin\opencode.exe"
$lock = "$P\.monitor.lock"
if ((Test-Path $lock) -and (Get-Process -Id ([int](Get-Content $lock -Raw)) -ErrorAction SilentlyContinue)) { exit 0 }
Set-Content $lock $PID
try {
    # Same ranked free ladder as run.ps1 (smoke-tested 2026-10-11 00:29; space-bunny-free hangs
    # intermittently, so it is last). No local models: the GPU belongs to renders.
    $chain = @('opencode/nemotron-3.5-lightning-free', 'opencode/ling-3.1-flash-free', 'opencode/step-5-preview-free', 'opencode/longcat-2.5-preview-free', 'opencode/nemotron-3-ultra-free', 'opencode/space-bunny-free')
    if (Test-Path 'E:\AI\Tools\opencode-alt\opencode\auth.json') { $chain += 'alt|opencode/space-bunny-free' }
    foreach ($entry in $chain) {
        $model = $entry -replace '^alt\|', ''
        if ($entry -like 'alt|*') { $env:XDG_DATA_HOME = 'E:\AI\Tools\opencode-alt' } else { Remove-Item Env:XDG_DATA_HOME -ErrorAction SilentlyContinue }
        $log = "$P\logs\monitor.log"
        "`n==== $(Get-Date -Format 'yyyy-MM-dd HH:mm') $entry" | Add-Content $log -Encoding utf8
        $proc = Start-Process $OpenCode -ArgumentList "run --agent monitor --model $model --dir `"$Root`" `"Run your monitoring pass now.`"" `
            -WorkingDirectory $Root -NoNewWindow -PassThru -RedirectStandardOutput "$log.out" -RedirectStandardError "$log.err"
        if (-not $proc.WaitForExit(15 * 60000)) { & taskkill /PID $proc.Id /T /F 2>&1 | Out-Null }
        Get-Content "$log.out" -Tail 20 -ErrorAction SilentlyContinue | Add-Content $log -Encoding utf8
        # A fresh report means the pass worked; otherwise try the next model.
        $rep = Get-Item "$P\MONITOR_REPORT.md" -ErrorAction SilentlyContinue
        if ($rep -and $rep.LastWriteTime -gt (Get-Date).AddMinutes(-16)) { break }
    }
} finally { Remove-Item $lock -ErrorAction SilentlyContinue }
