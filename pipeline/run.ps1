# Overnight runner. The "Waifu Pipeline Runner" scheduled task starts it every 15 minutes;
# the lock makes overlapping starts exit at once. Safe to run by hand: .\pipeline\run.ps1
#
# Flow per task: queue/ -> active/ -> builder (opencode) -> verify.ps1 -> review/ or blocked/.
# The builder works in a separate worktree on branch "pipeline", so the main checkout
# stays free for planning. Nothing here pushes, and nothing merges into main.
param([int] $MaxTasks = 8, [int] $TaskTimeoutMin = 120, [ValidateSet('card', 'art', 'motion', 'design', 'qa', 'fix')] [string] $Lane = 'card')

# 'Continue' because git and Godot write progress to stderr; exit codes are checked by hand.
$ErrorActionPreference = 'Continue'
$P = $PSScriptRoot
$OpenCode = "$env:APPDATA\npm\node_modules\opencode-ai\bin\opencode.exe"
# Lanes run in parallel, each with its own repo/branch, worktree, queue, agent and verifier.
# The art lane is the image pipeline: a separate repo, per the AGENTS.md handoff contract.
# Models are a fallback CHAIN (dev: "rely on free agents as much as we can, plenty of fallbacks"):
# a provider/quota error moves the lane to the next model; a failed first attempt retries one step
# further down. Free = Space Bunny Free only (no training on data, as in the KaT playbook).
$Free = 'opencode/space-bunny-free'; $Flash = 'opencode-go/deepseek-v4.1-flash'; $Kimi = 'opencode-go/kimi-k3'
$Root = Split-Path $P -Parent
$Lanes = @{
    card   = @{ Repo = $Root; Wt = 'E:\AI\waifu-pipeline-wt'; Branch = 'pipeline'; Q = "$P\tasks"; Agent = 'builder'; Models = @($Flash, $Free); Verify = "$P\verify.ps1"; Tag = '' }
    art    = @{ Repo = 'E:\AI\Waifu Image Pipeline'; Wt = 'E:\AI\waifu-art-wt'; Branch = 'pipeline'; Q = "$P\tasks-art"; Agent = 'artist'; Models = @($Free, $Flash); Verify = "$P\verify-art.ps1"; Tag = '-art' }
    motion = @{ Repo = $Root; Wt = 'E:\AI\waifu-motion-wt'; Branch = 'motion'; Q = "$P\tasks-motion"; Agent = 'animator'; Models = @($Kimi, $Flash, $Free); Verify = "$P\verify.ps1"; Tag = '-motion' }
    design = @{ Repo = $Root; Wt = 'E:\AI\waifu-design-wt'; Branch = 'design'; Q = "$P\tasks-design"; Agent = 'designer'; Models = @($Kimi, $Flash, $Free); Verify = "$P\verify.ps1"; Tag = '-design' }
    qa     = @{ Repo = $Root; Wt = 'E:\AI\waifu-qa-wt'; Branch = 'qa'; Q = "$P\tasks-qa"; Agent = 'qa'; Models = @($Free, $Kimi); Verify = "$P\verify.ps1"; Tag = '-qa' }
    fix    = @{ Repo = $Root; Wt = 'E:\AI\waifu-fix-wt'; Branch = 'fix'; Q = "$P\tasks-fix"; Agent = 'fixer'; Models = @($Flash, $Free); Verify = "$P\verify.ps1"; Tag = '-fix' }
}
$L = $Lanes[$Lane]
$Repo = $L.Repo; $Wt = $L.Wt; $Q = $L.Q
$Branch = $L.Branch
# Budget override: pipeline/FREE_ONLY makes every lane free-only (Claude sets it when the cap is hit).
# No local models: they would fight the image renders for the GPU (dev's call).
# "alt|<model>" runs on the dev's second opencode account (its own login in E:\AI\Tools\opencode-alt,
# which the dev signs into themselves); used only after the main account's options are exhausted.
$AltHome = 'E:\AI\Tools\opencode-alt'
$HasAlt = Test-Path "$AltHome\opencode\auth.json"
# Free ladder (dev 2026-10-11: "stay free but try different free models ... go down the list
# until we have to go to the paid tier"). Ranked by the 00:29 smoke test
# (pipeline/logs/model-smoke.txt): these five answered a trivial prompt in seconds while
# space-bunny-free hung at the 90s timeout (it hangs intermittently since 10-10 12:24, so it
# stays last and verification decides). Main account first, then the alt account, then the
# paid tier as the final fallback only. Re-ranked by the 14:17 probe
# (pipeline/logs/model-probe-2026-10-11.txt): only ultra and step-5 answered; Test-ModelAlive
# skips whichever is hanging at run time, so order only decides speed, not correctness.
$FreeChain = @('opencode/nemotron-3-ultra-free', 'opencode/step-5-preview-free', 'opencode/nemotron-3.5-lightning-free', 'opencode/ling-3.1-flash-free', 'opencode/longcat-2.5-preview-free', 'opencode/space-bunny-free')
$Models = if (Test-Path "$P\FREE_ONLY") { @($FreeChain) + @($FreeChain | ForEach-Object { "alt|$_" }) + @($Flash, $Kimi) } else { $L.Models }
if (-not $HasAlt) { $Models = @($Models | Where-Object { $_ -notlike 'alt|*' }) }
$OffsetFile = "$P\.model-offset$($L.Tag)"
$Offset = [int](Get-Content $OffsetFile -ErrorAction SilentlyContinue)
function Pick-Model([int] $attempt) { $Models[[Math]::Min($Offset + $attempt - 1, $Models.Count - 1)] }
foreach ($d in 'queue', 'active', 'review', 'blocked', 'done') { New-Item -ItemType Directory -Force "$Q\$d" | Out-Null }
New-Item -ItemType Directory -Force "$P\logs", "$P\shots" | Out-Null
$RunLog = "$P\logs\runner$($L.Tag).log"
$F = '```'   # markdown fence; spelled once because backticks are PowerShell's escape char

function Log([string] $m) { "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $m" | Add-Content $RunLog -Encoding utf8 }
function G { & git -C $Wt @args 2>&1 | ForEach-Object { "$_" } }
function TaskId([IO.FileInfo] $f) { ($f.BaseName -split '-')[0..1] -join '-' }
# A task may declare "Requires: path, path" (worktree-relative). It waits in the queue until those
# exist on its branch, so lanes that depend on each other's merged work never start too early.
function Test-Ready([IO.FileInfo] $f) {
    $req = Select-String -Path $f.FullName -Pattern '^Requires:\s*(.+)$' | Select-Object -First 1
    if (-not $req) { return $true }
    foreach ($p in ($req.Matches[0].Groups[1].Value -split ',')) {
        # Strip trailing prose: "path.sql (does a thing)" must gate on the path only,
        # otherwise the task waits forever for a file that exists (MONITOR_REPORT 2026-10-10).
        $path = ($p.Trim() -replace '\s*\(.*\)\s*$', '').TrimEnd(' ', "`t", '/')
        if (-not (Test-Path (Join-Path $Wt $path))) { return $false }
    }
    return $true
}

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
    $lines | Set-Content "$P\STATUS$($L.Tag).md" -Encoding utf8
}

function Move-Task([IO.FileInfo] $f, [string] $to, [string] $append = '') {
    if ($append) { "`n$append" | Add-Content $f.FullName -Encoding utf8 }
    $dest = "$Q\$to\$($f.Name)"
    Move-Item $f.FullName $dest -Force
    Remove-Item "$($f.FullName).state.json" -ErrorAction SilentlyContinue
    return Get-Item $dest
}

# Free models hang for hours without erroring (2026-10-11 probe: 6 of 10 silent at 90s, and the set
# changes hour to hour), and a hang costs the whole $TaskTimeoutMin. A 60s trivial prompt first
# turns that into a 1-minute ladder step. Paid models skip it: it would spend allowance for nothing.
function Test-ModelAlive([string] $model) {
    if ($model -notlike '*-free') { return $true }
    $dir = Join-Path $env:TEMP 'waifu-model-probe'; New-Item -ItemType Directory -Force $dir | Out-Null
    $out = Join-Path $dir "probe$($L.Tag).txt"
    $proc = Start-Process -FilePath $OpenCode -ArgumentList "run --model $model --dir `"$dir`" `"Reply with exactly: OK`"" `
        -WorkingDirectory $dir -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError "$out.err"
    if (-not $proc.WaitForExit(60000)) { & taskkill /PID $proc.Id /T /F 2>&1 | Out-Null; return $false }
    return [bool]((Get-Content $out -Raw -ErrorAction SilentlyContinue) -match 'OK')
}

function Invoke-Builder([string] $id, [string] $message, [string] $logFile, [string] $model) {
    # The child process inherits XDG_DATA_HOME at launch, so set it only around Start-Process.
    $useAlt = $model -like 'alt|*'
    if ($useAlt) { $model = $model.Substring(4); $env:XDG_DATA_HOME = $AltHome }
    $alive = Test-ModelAlive $model
    if (-not $alive) {
        if ($useAlt) { Remove-Item Env:XDG_DATA_HOME -ErrorAction SilentlyContinue }
        Log "$id skipped $model`: no answer to a 60s health check"
        return 'infra'
    }
    # PS 5.1 Start-Process joins arguments without quoting, so quote by hand.
    $argLine = "run --agent $($L.Agent) --model $model --auto --dir `"$Wt`" --title `"$id`" `"$message`""
    $proc = Start-Process -FilePath $OpenCode -ArgumentList $argLine -WorkingDirectory $Wt -NoNewWindow -PassThru `
        -RedirectStandardOutput $logFile -RedirectStandardError "$logFile.err"
    if ($useAlt) { Remove-Item Env:XDG_DATA_HOME -ErrorAction SilentlyContinue }
    if (-not $proc.WaitForExit($TaskTimeoutMin * 60000)) {
        & taskkill /PID $proc.Id /T /F 2>&1 | Out-Null
        Log "$id builder timed out after $TaskTimeoutMin min; killed"
        return 'timeout'
    }
    # Quota/auth/provider errors are not the task's fault: back off instead of burning attempts.
    # Only when the builder delivered no report: task text itself may mention 401/429 (T-005 did,
    # and an earlier version of this check threw away finished work).
    $stdout = Get-Content $logFile -Raw -ErrorAction SilentlyContinue
    if ($stdout -match '## Report') { return 'ok' }
    $errText = Get-Content "$logFile.err" -Raw -ErrorAction SilentlyContinue
    # 504/upstream-idle: the provider dropped the stream mid-task (seen on nemotron-3.5-lightning
    # 2026-10-11 02:49, A-004: "Streaming response failed: [504] Upstream idle timeout exceeded").
    # That is the model hanging, not the task failing: walk the ladder instead of burning attempts.
    if ($errText -match '(?i)rate.?limit|quota|insufficient.?(balance|credit)|ProviderModelNotFound|ECONNREFUSED|ENOTFOUND|AI_APICallError|upstream.?(idle|timeout)|streaming response failed|\[504\]|http.?504|status.?504') { return 'infra' }
    return 'ok'
}

# ---------------------------------------------------------------- start-up guards
if (Test-Path "$P\STOP") { Log 'STOP present; not starting'; Write-Status; exit 0 }
# Dev 2026-10-11: no pipeline work while streaming. Builds and Godot verify runs (windows, CPU, RAM)
# compete with OBS. A task already running when OBS opens finishes its current step.
if (Get-Process obs64, obs32, obs -ErrorAction SilentlyContinue) { Log 'OBS is open (streaming); not starting'; Write-Status; exit 0 }
$Cooldown = "$P\.cooldown$($L.Tag)"   # per lane: one provider outage shouldn't idle every lane
if (Test-Path $Cooldown) {
    if ((Get-Date) -lt [datetime](Get-Content $Cooldown)) { Write-Status; exit 0 }
    Remove-Item $Cooldown
}
$Lock = "$P\.runner$($L.Tag).lock"
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

    # QA loop: when the fix lane is idle and main moved since the last sweep, queue a new sweep.
    # Capped so a never-converging loop can't burn the night.
    if ($Lane -eq 'qa' -and (Test-Path "$P\qa\SWEEP_TEMPLATE.md")) {
        $fixBusy = @(Get-ChildItem "$P\tasks-fix\queue\*.md", "$P\tasks-fix\active\*.md" -ErrorAction SilentlyContinue).Count
        $qaBusy = @(Get-ChildItem "$Q\queue\*.md", "$Q\active\*.md" -ErrorAction SilentlyContinue).Count
        $mainHead = (git -C $Repo rev-parse main) | Select-Object -Last 1
        $sweeps = @(Get-ChildItem "$Q\*\Q-*.md" -ErrorAction SilentlyContinue).Count
        if (-not $fixBusy -and -not $qaBusy -and $mainHead -ne (Get-Content "$P\.qa-last-main" -ErrorAction SilentlyContinue) -and $sweeps -lt 12) {
            $sid = 'Q-{0:000}' -f ($sweeps + 1)
            (Get-Content "$P\qa\SWEEP_TEMPLATE.md" -Raw).Replace('{ID}', $sid).Replace('{N}', [string]($sweeps + 1)) |
                Set-Content "$Q\queue\$sid-sweep.md" -Encoding utf8
            Set-Content "$P\.qa-last-main" $mainHead
            Log "queued $sid (main at $mainHead)"
        }
    }

    $done = 0
    while ($done -lt $MaxTasks -and -not (Test-Path "$P\STOP")) {
        # Pick up whatever landed on main (merged work, fixes, new rules) before choosing a task.
        G merge -q --no-edit main | Out-Null
        if ($LASTEXITCODE) {
            G merge --abort | Out-Null
            Log "merge of main into $Branch conflicts; stopping"
            Write-Status "Merging main into the $Branch branch conflicts. Claude/dev must resolve before anything else runs."
            break
        }
        G clean -fdq -e .godot | Out-Null
        $task = Get-ChildItem "$Q\queue\*.md" -ErrorAction SilentlyContinue | Sort-Object Name | Where-Object { Test-Ready $_ } | Select-Object -First 1
        if (-not $task) { break }
        $id = TaskId $task
        $base = (G rev-parse HEAD) | Select-Object -Last 1

        $task = Move-Task $task 'active'
        @{ base = $base; started = (Get-Date).ToString('s') } | ConvertTo-Json | Set-Content "$($task.FullName).state.json"
        Copy-Item $task.FullName "$Wt\.task.md" -Force
        Remove-Item "$Wt\.verify.txt" -ErrorAction SilentlyContinue
        if ($Lane -eq 'qa') {
            # So QA never files duplicates of fixes already queued or in progress.
            Get-ChildItem "$P\tasks-fix\queue\*.md", "$P\tasks-fix\active\*.md", "$P\tasks-fix\review\*.md" -ErrorAction SilentlyContinue |
                ForEach-Object { (Get-Content $_.FullName -TotalCount 1) } | Set-Content "$Wt\.qa_open_fixes.txt" -Encoding utf8
        }
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
            $model = Pick-Model $attempt
            Log "$id attempt $attempt on $model"
            $b = Invoke-Builder $id $msg $log $model
            if ($b -eq 'infra') { $result = 'infra'; break }

            # The runner commits leftovers so verify judges exactly what will land.
            if (G status --porcelain | Where-Object { $_ -notmatch '\.task\.md|\.verify\.txt' }) {
                G add -A | Out-Null
                G reset -q -- .task.md .verify.txt | Out-Null
                G commit -q -m "${id}: changes the builder left uncommitted (committed by runner)" | Out-Null
            }
            if (((G rev-parse HEAD) | Select-Object -Last 1) -eq $base) { $verifyOut = 'builder made no changes'; continue }

            Remove-Item $shots -Recurse -Force -ErrorAction SilentlyContinue
            $verifyOut = & powershell -NoProfile -ExecutionPolicy Bypass -File $L.Verify -Worktree $Wt -BaseRef $base -ShotDir $shots 2>&1 | Out-String -Width 300
            $verifyOut | Set-Content "$P\logs\$id.verify$attempt.txt" -Encoding utf8
            if ($LASTEXITCODE -eq 0) { $result = 'pass'; break }
            $verifyOut | Set-Content "$Wt\.verify.txt" -Encoding utf8
            Log "$id attempt $attempt failed verification"
        }

        $report = ''
        $lastLog = Get-ChildItem "$P\logs\$id.attempt*.log" | Sort-Object Name | Select-Object -Last 1
        if ($lastLog) {
            # An empty log makes -Raw emit nothing, and .LastIndexOf on that crashed the runner right after
            # VERIFY: PASS (2026-10-11, "runner CRASHED at line 256/261"). A [string] cast does NOT fix
            # it (an empty pipeline cast stays $null); interpolation always yields a string.
            $txt = "$(Get-Content $lastLog.FullName -Raw)"
            $at = $txt.LastIndexOf('## Report')
            $report = if ($at -ge 0) { $txt.Substring($at) } else { "(builder wrote no report; see pipeline/logs/$($lastLog.Name))" }
        }
        $commits = (G log --oneline "$base..HEAD") -join "`n"

        if ($result -eq 'infra') {
            G reset -q --hard $base | Out-Null
            Move-Task $task 'queue' | Out-Null
            if ($Offset + 1 -lt $Models.Count) {
                $Offset++; Set-Content $OffsetFile $Offset
                Log "$id hit a provider/quota error on $model; falling back to $($Models[$Offset])"
                continue
            }
            Set-Content $OffsetFile 0
            (Get-Date).AddMinutes(60).ToString('s') | Set-Content $Cooldown
            Log "${id}: every model in the chain failed; requeued, lane cooling down 60 min"
            break
        }
        if ($result -eq 'pass') {
            $note = @(
                '---', "# Pipeline result: VERIFIED $(Get-Date -Format 'yyyy-MM-dd HH:mm')",
                "Commits (on branch $Branch, from $base):", $F, $commits, $F,
                "Screenshots: pipeline/shots/$id", '', $report, '',
                '<details><summary>verify output</summary>', '', $F, $verifyOut, $F, '</details>'
            ) -join "`n"
            Move-Task $task 'review' $note | Out-Null
            Log "$id VERIFIED -> review"
            if ($Lane -eq 'qa' -and (Test-Path "$Wt\.qa_out")) {
                New-Item -ItemType Directory -Force "$P\qa\reports", "$P\tasks-fix\queue" | Out-Null
                Copy-Item "$Wt\.qa_out\report.md" "$P\qa\reports\$id.md" -ErrorAction SilentlyContinue
                Get-ChildItem "$Wt\.qa_out\fix_tasks\*.md" -ErrorAction SilentlyContinue | ForEach-Object {
                    # Flow problems (not bugs) go to the design lane, per the dev.
                    $dest = if ((Get-Content $_.FullName -Raw) -match '(?im)^Kind:\s*flow') { "$P\tasks-design\queue" } else { "$P\tasks-fix\queue" }
                    Copy-Item $_.FullName $dest
                }
                Get-ChildItem "$Wt\.qa_out" -Recurse -File | Remove-Item -Force
                Log "$id fix tasks filed"
            }
            # Claude is near its usage limit, so verified work lands automatically. Verification is
            # independent and the QA loop re-checks main after merges; a conflict leaves it in review.
            # Opt-in only: the dev creates pipeline/AUTO_MERGE to allow it.
            if (-not (Test-Path "$P\AUTO_MERGE")) { Log "$id waiting in review (auto-merge off)" }
            elseif ((& git -C $Repo merge --no-ff --no-edit $Branch -m "Merge $id from $Branch" 2>&1 | Out-String) -and $LASTEXITCODE) {
                & git -C $Repo merge --abort 2>&1 | Out-Null
                Log "$id auto-merge into main CONFLICTED; left in review for the overseer"
            } else {
                Move-Item "$Q\review\$($task.Name)" "$Q\done\" -Force -ErrorAction SilentlyContinue
                Log "$id auto-merged into main"
            }
        } else {
            G tag -f "failed/$id" | Out-Null
            G reset -q --hard $base | Out-Null
            $first = ($verifyOut -split "`r?`n" | Where-Object { $_ -match '^- |no changes' } | Select-Object -First 1)
            $note = @(
                '---', "# Pipeline result: FAILED $(Get-Date -Format 'yyyy-MM-dd HH:mm')",
                "Work kept on tag failed/$id, branch rolled back to $base.", '', $report, '',
                $F, $verifyOut, $F, "Blocked: $first"
            ) -join "`n"
            Move-Task $task 'blocked' $note | Out-Null
            Log "$id FAILED -> blocked ($first)"
        }
        Remove-Item "$Wt\.task.md", "$Wt\.verify.txt" -ErrorAction SilentlyContinue
        # A finished task (pass or fail) sends the next one back to the top of the ladder: free models
        # recover within hours, and a remembered offset kept later tasks on the paid tier (2026-10-11,
        # design lane stuck on deepseek after one bad hour). Infra step-downs above still persist
        # within a task, because they `continue` before reaching this line.
        if ($Offset -ne 0) { $Offset = 0; Set-Content $OffsetFile 0 }
        $done++
    }
    Write-Status
}
catch {
    # Without this the runner died silently: finally dropped the lock and the next tick filed the
    # task as "interrupted" (2026-10-11: T-011, M-003, A-003 all died right after VERIFY: PASS).
    Log "runner CRASHED at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)"
    throw
}
finally {
    # No catch line above plus a task still in active/ means the process was killed from outside.
    Remove-Item $Lock -ErrorAction SilentlyContinue
}
