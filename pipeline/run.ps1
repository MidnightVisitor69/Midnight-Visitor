# Overnight runner. The "Waifu Pipeline Runner" scheduled task starts it every 15 minutes;
# the lock makes overlapping starts exit at once. Safe to run by hand: .\pipeline\run.ps1
#
# Flow per task: queue/ -> active/ -> builder (opencode) -> verify.ps1 -> review/ or blocked/.
# The builder works in a separate worktree on branch "pipeline", so the main checkout
# stays free for planning. Nothing here pushes, and nothing merges into main.
param([int] $MaxTasks = 8, [int] $TaskTimeoutMin = 60)

# 'Continue' because git and Godot write progress to stderr; exit codes are checked by hand.
$ErrorActionPreference = 'Continue'
$P = $PSScriptRoot
$Repo = Split-Path $P -Parent
$Wt = 'E:\AI\waifu-pipeline-wt'
$Branch = 'pipeline'
$OpenCode = "$env:APPDATA\npm\node_modules\opencode-ai\bin\opencode.exe"
$Model = 'opencode-go/deepseek-v4.1-flash'
$Q = "$P\tasks"
foreach ($d in 'queue', 'active', 'review', 'blocked', 'done') { New-Item -ItemType Directory -Force "$Q\$d" | Out-Null }
New-Item -ItemType Directory -Force "$P\logs", "$P\shots" | Out-Null
$RunLog = "$P\logs\runner.log"

function Log([string] $m) { "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $m" | Add-Content $RunLog -Encoding utf8 }
function G { & git -C $Wt @args 2>&1 | ForEach-Object { "$_" } }
function TaskId([IO.FileInfo] $f) { ($f.BaseName -split '-')[0..1] -join '-' }

function Write-Status([string] $note = '') {
    $lines = @("# Pipeline status", "", "Updated $(Get-Date -Format 'yyyy-MM-dd HH:mm')  ")
    if (Test-Path "$P\STOP") { $lines += "**STOPPED** (delete ``pipeline/STOP`` to resume)  " }
    if (Test-Path "$P\.cooldown") { $lines += "Cooling down after a model/infra failure until $(Get-Content "$P\.cooldown")  " }
    if ($note) { $lines += "$note  " }
    foreach ($d in 'active', 'queue', 'review', 'blocked', 'done') {
        $items = Get-ChildItem "$Q\$d\*.md" -ErrorAction SilentlyContinue | Sort-Object Name
        $lines += "", "## $d ($($items.Count))"
        foreach ($i in $items) {
            $why = ''
            if ($d -eq 'blocked') { $why = ' - ' + ((Select-String -Path $i.FullName -Pattern '^Blocked: (.*)$' | Select-Object -Last 1).Matches.Groups[1].Value) }
            $lines += "- $($i.BaseName)$why"
        }
    }
    $lines | Set-Content "$P\STATUS.md" -Encoding utf8
}

function Move-Task([IO.FileInfo] $f, [string] $to, [string] $append = '') {
    if ($append) { "`n$append" | Add-Content $f.FullName -Encoding utf8 }
    $dest = "$Q\$to\$($f.Name)"
    Move-Item $f.FullName $dest -Force
    Remove-Item "$($f.FullName).state.json" -ErrorAction SilentlyContinue
    return Get-Item $dest
}

function Invoke-Builder([string] $id, [string] $message, [string] $logFile) {
    # PS 5.1 Start-Process joins arguments without quoting, so quote by hand.
    $argLine = "run --agent builder --model $Model --auto --dir `"$Wt`" --title `"$id`" `"$message`""
    $proc = Start-Process -FilePath $OpenCode -ArgumentList $argLine -WorkingDirectory $Wt -NoNewWindow -PassThru `
        -RedirectStandardOutput $logFile -RedirectStandardError "$logFile.err"
    if (-not $proc.WaitForExit($TaskTimeoutMin * 60000)) {
        & taskkill /PID $proc.Id /T /F 2>&1 | Out-Null
        Log "$id builder timed out after $TaskTimeoutMin min; killed"
        return 'timeout'
    }
    $out = (Get-Content $logFile, "$logFile.err" -Raw -ErrorAction SilentlyContinue) -join "`n"
    # Quota/auth/provider errors are not the task's fault: back off instead of burning attempts.
    if ($out -match '(?i)rate.?limit|quota|insufficient.?(balance|credit)|unauthori[sz]ed|\b401\b|\b429\b|ProviderModelNotFound|ECONNREFUSED|ENOTFOUND') {
        if ((Get-Item $logFile -ErrorAction SilentlyContinue).Length -lt 4000) { return 'infra' }
    }
    return 'ok'
}

# ---------------------------------------------------------------- start-up guards
if (Test-Path "$P\STOP") { Log 'STOP present; not starting'; Write-Status; exit 0 }
if (Test-Path "$P\.cooldown") {
    if ((Get-Date) -lt [datetime](Get-Content "$P\.cooldown")) { Write-Status; exit 0 }
    Remove-Item "$P\.cooldown"
}
$Lock = "$P\.runner.lock"
if (Test-Path $Lock) {
    $old = Get-Content $Lock -Raw
    if ($old -and (Get-Process -Id ([int]$old) -ErrorAction SilentlyContinue | Where-Object ProcessName -match 'powershell')) { exit 0 }
    Log "stale lock (PID $old) cleared"
}
Set-Content $Lock $PID

try {
    if (-not (Test-Path "$Wt\.git")) {
        if (git -C $Repo branch --list $Branch) { git -C $Repo worktree add $Wt $Branch 2>&1 | Out-Null }
        else { git -C $Repo worktree add -b $Branch $Wt main 2>&1 | Out-Null }
        Log "worktree created at $Wt"
    }

    # A task left in active/ means the runner died mid-task (reboot, kill). Keep the
    # partial work on a tag, roll the branch back, and leave it for the dev to look at.
    foreach ($f in Get-ChildItem "$Q\active\*.md" -ErrorAction SilentlyContinue) {
        $id = TaskId $f
        $st = Get-Content "$($f.FullName).state.json" -Raw -ErrorAction SilentlyContinue | ConvertFrom-Json
        if (G status --porcelain) { G add -A | Out-Null; G commit -q -m "${id}: WIP left by an interrupted run" | Out-Null }
        G tag -f "interrupted/$id" | Out-Null
        if ($st.base) { G reset -q --hard $st.base | Out-Null }
        Move-Task $f 'blocked' "Blocked: runner was interrupted mid-task; partial work on tag interrupted/$id" | Out-Null
        Log "$id recovered from interrupted run"
    }

    $done = 0
    while ($done -lt $MaxTasks -and -not (Test-Path "$P\STOP")) {
        $task = Get-ChildItem "$Q\queue\*.md" -ErrorAction SilentlyContinue | Sort-Object Name | Select-Object -First 1
        if (-not $task) { break }
        $id = TaskId $task

        # Pick up whatever the dev committed on main (fixes, new rules) before building on top.
        G merge -q --no-edit main | Out-Null
        if ($LASTEXITCODE) {
            G merge --abort | Out-Null
            Log "merge of main into $Branch conflicts; stopping"
            Write-Status "Merging main into the pipeline branch conflicts. Claude/dev must resolve before anything else runs."
            break
        }
        G clean -fdq -e .godot | Out-Null
        $base = (G rev-parse HEAD) | Select-Object -Last 1

        $task = Move-Task $task 'active'
        @{ base = $base; started = (Get-Date).ToString('s') } | ConvertTo-Json | Set-Content "$($task.FullName).state.json"
        Copy-Item $task.FullName "$Wt\.task.md" -Force
        Remove-Item "$Wt\.verify.txt" -ErrorAction SilentlyContinue
        $shots = "$P\shots\$id"
        Write-Status "Building $id"
        Log "$id started from $base"

        $result = 'fail'; $verifyOut = ''
        for ($attempt = 1; $attempt -le 2; $attempt++) {
            $msg = if ($attempt -eq 1) {
                "Task $id. Read AGENTS.md, pipeline/BUILDER.md and .task.md, then do the task in .task.md."
            } else {
                "Task $id, attempt 2. Your first attempt failed independent verification; the output is in .verify.txt. Read AGENTS.md, pipeline/BUILDER.md, .task.md and .verify.txt, fix every problem listed, and commit."
            }
            $log = "$P\logs\$id.attempt$attempt.log"
            $b = Invoke-Builder $id $msg $log
            if ($b -eq 'infra') { $result = 'infra'; break }

            # The runner commits leftovers so verify judges exactly what will land.
            if (G status --porcelain | Where-Object { $_ -notmatch '\.task\.md|\.verify\.txt' }) {
                G add -A | Out-Null
                G reset -q -- .task.md .verify.txt | Out-Null
                G commit -q -m "${id}: changes the builder left uncommitted (committed by runner)" | Out-Null
            }
            if (((G rev-parse HEAD) | Select-Object -Last 1) -eq $base) { $verifyOut = 'builder made no changes'; continue }

            Remove-Item $shots -Recurse -Force -ErrorAction SilentlyContinue
            $verifyOut = & powershell -NoProfile -ExecutionPolicy Bypass -File "$P\verify.ps1" -Worktree $Wt -BaseRef $base -ShotDir $shots 2>&1 | Out-String -Width 300
            $verifyOut | Set-Content "$P\logs\$id.verify$attempt.txt" -Encoding utf8
            if ($LASTEXITCODE -eq 0) { $result = 'pass'; break }
            $verifyOut | Set-Content "$Wt\.verify.txt" -Encoding utf8
            Log "$id attempt $attempt failed verification"
        }

        $report = ''
        $lastLog = Get-ChildItem "$P\logs\$id.attempt*.log" | Sort-Object Name | Select-Object -Last 1
        if ($lastLog) {
            $txt = Get-Content $lastLog.FullName -Raw
            $at = $txt.LastIndexOf('## Report')
            $report = if ($at -ge 0) { $txt.Substring($at) } else { "(builder wrote no report; see pipeline/logs/$($lastLog.Name))" }
        }
        $commits = (G log --oneline "$base..HEAD") -join "`n"

        if ($result -eq 'infra') {
            G reset -q --hard $base | Out-Null
            Move-Task $task 'queue' | Out-Null
            (Get-Date).AddMinutes(60).ToString('s') | Set-Content "$P\.cooldown"
            Log "$id hit a model/provider error; requeued, cooling down 60 min"
            break
        }
        if ($result -eq 'pass') {
            Move-Task $task 'review' "---`n# Pipeline result: VERIFIED $(Get-Date -Format 'yyyy-MM-dd HH:mm')`nCommits (on branch $Branch, from $base):`n``````n$commits`n```````nScreenshots: pipeline/shots/$id`n`n$report`n`n<details><summary>verify output</summary>`n`n``````n$verifyOut`n```````n</details>" | Out-Null
            Log "$id VERIFIED -> review"
        } else {
            G tag -f "failed/$id" | Out-Null
            G reset -q --hard $base | Out-Null
            $first = ($verifyOut -split "`r?`n" | Where-Object { $_ -match '^- |no changes' } | Select-Object -First 1)
            Move-Task $task 'blocked' "---`n# Pipeline result: FAILED $(Get-Date -Format 'yyyy-MM-dd HH:mm')`nWork kept on tag failed/$id, branch rolled back to $base.`n`n$report`n`n``````n$verifyOut`n```````nBlocked: $first" | Out-Null
            Log "$id FAILED -> blocked ($first)"
        }
        Remove-Item "$Wt\.task.md", "$Wt\.verify.txt" -ErrorAction SilentlyContinue
        $done++
    }
    Write-Status
}
finally {
    Remove-Item $Lock -ErrorAction SilentlyContinue
}
