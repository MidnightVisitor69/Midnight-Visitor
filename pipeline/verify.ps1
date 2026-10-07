# Independent check of the builder's work. The builder's own report is not trusted:
# this script decides whether a task lands. Exit 0 = pass, 1 = fail.
param(
    [Parameter(Mandatory)] [string] $Worktree,
    [Parameter(Mandatory)] [string] $BaseRef,     # commit the task started from
    [Parameter(Mandatory)] [string] $ShotDir      # where screenshots go (outside git)
)
$ErrorActionPreference = 'Continue'
$G = 'E:\AI\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe'
$client = Join-Path $Worktree 'client'
$fail = [System.Collections.Generic.List[string]]::new()

function Invoke-Godot([string[]] $GodotArgs, [int] $TimeoutSec = 180) {
    # Godot exits 0 on script errors, so callers must scan the text, not just the code.
    $out = & $G @GodotArgs 2>&1 | Out-String -Width 300
    return @{ Text = $out; Code = $LASTEXITCODE }
}
function Get-Errors([string] $text) {
    ($text -split "`r?`n") | Where-Object { $_ -match 'SCRIPT ERROR|Parse Error|^\s*ERROR:|SHADER ERROR' }
}

Write-Output "== import"
$r = Invoke-Godot @('--headless', '--path', $client, '--import')
$errs = Get-Errors $r.Text
if ($errs) { $fail.Add("import errors:`n" + ($errs -join "`n")) } else { Write-Output 'clean' }

Write-Output "== unit tests"
$r = Invoke-Godot @('--headless', '--path', $client, '--script', 'res://tests/run_tests.gd')
($r.Text -split "`r?`n") | Where-Object { $_ -match '^(PASS|FAIL|RESULT)' } | Write-Output
if ($r.Code -ne 0) { $fail.Add("unit tests exit $($r.Code)") }
$errs = Get-Errors $r.Text
if ($errs) { $fail.Add("errors during tests:`n" + ($errs -join "`n")) }

Write-Output "== smoke run (main scene, headless)"
$r = Invoke-Godot @('--headless', '--path', $client, '--quit-after', '60')
$errs = Get-Errors $r.Text
if ($errs) { $fail.Add("main scene errors:`n" + ($errs -join "`n")) } else { Write-Output 'clean' }

Write-Output "== GPU screenshots (every scene that defines screenshot_count)"
$scenes = Get-ChildItem (Join-Path $client 'scenes') -Recurse -Filter *.tscn -ErrorAction SilentlyContinue
foreach ($s in $scenes) {
    $scriptRefs = Select-String -Path $s.FullName -Pattern 'path="(res://[^"]+\.gd)"' -AllMatches |
        ForEach-Object { $_.Matches } | ForEach-Object { $_.Groups[1].Value }
    $hasShots = $false
    foreach ($ref in $scriptRefs) {
        $file = Join-Path $client ($ref -replace '^res://', '')
        if ((Test-Path $file) -and (Select-String -Path $file -Pattern 'func screenshot_count' -Quiet)) { $hasShots = $true }
    }
    if (-not $hasShots) { continue }
    $res = 'res://' + ($s.FullName.Substring($client.Length + 1) -replace '\\', '/')
    $r = Invoke-Godot @('--path', $client, '--position', '-4000,-4000', '--resolution', '540x960',
        '--script', 'res://tests/screenshot.gd', '--', $res, $ShotDir)
    $shots = ($r.Text -split "`r?`n") | Where-Object { $_ -match '^SHOT ' }
    $errs = Get-Errors $r.Text
    Write-Output "$res -> $($shots.Count) shots"
    if ($errs) { $fail.Add("render errors in ${res}:`n" + ($errs -join "`n")) }
    if ($shots.Count -eq 0) { $fail.Add("no screenshots from $res") }
}

$audioDir = Join-Path $client 'audio'
if (Test-Path $audioDir) {
    Write-Output "== audio guard (loudness, pitch, clicks)"
    $out = & 'E:\AI\ComfyUI\python_embeded\python.exe' (Join-Path $PSScriptRoot 'check_audio.py') $audioDir 2>&1 | Out-String -Width 300
    $code = $LASTEXITCODE
    Write-Output $out.TrimEnd()
    if ($code -ne 0) {
        $why = ($out -split "`r?`n") | Where-Object { $_ -match '^FAIL' }
        $fail.Add("audio guard failed:`n" + ($why -join "`n"))
    }
}

$nodeTests = Get-ChildItem (Join-Path $Worktree 'tools') -Recurse -Filter *.test.mjs -ErrorAction SilentlyContinue
if ($nodeTests) {
    Write-Output "== node tests"
    Push-Location $Worktree
    $out = & node --test ($nodeTests | ForEach-Object { $_.FullName }) 2>&1 | Out-String -Width 300
    $code = $LASTEXITCODE
    Pop-Location
    ($out -split "`r?`n") | Where-Object { $_ -match '^# (tests|pass|fail)|^not ok' } | Write-Output
    if ($code -ne 0) {
        $why = ($out -split "`r?`n") | Where-Object { $_ -match 'not ok|Error|expected|actual' } | Select-Object -First 30
        $fail.Add("node tests exit ${code}:`n" + ($why -join "`n"))
    }
}

Write-Output "== diff guards"
Push-Location $Worktree
$changed = git diff --name-only "$BaseRef..HEAD"
$protected = $changed | Where-Object {
    $_ -match '^(AGENTS\.md|opencode\.json|pipeline/|shared/art/)' -or
    $_ -match '^supabase/migrations/2026100707|^supabase/migrations/20261007063932' -or
    $_ -match '^client/scripts/config\.gd$|^client/tests/(run_tests|test_case|screenshot)\.gd$'
}
if ($protected) { $fail.Add("touched protected files: " + ($protected -join ', ')) }
$binArt = $changed | Where-Object { $_ -match '\.(png|jpe?g|webp|psd|exr)$' }
if ($binArt) { $fail.Add("added image files (art is the image pipeline's job): " + ($binArt -join ', ')) }
$diff = git diff "$BaseRef..HEAD" | Out-String
if ($diff -match 'sb_secret_|service_role|SUPABASE_SERVICE|-----BEGIN [A-Z ]*PRIVATE KEY') {
    $fail.Add('possible secret in diff')
}
$authors = git log --format='%an <%ae>' "$BaseRef..HEAD" | Sort-Object -Unique
$bad = $authors | Where-Object { $_ -ne 'waifu-dev <waifu-dev@users.noreply.local>' }
if ($bad) { $fail.Add("non-anonymous commit author: " + ($bad -join ', ')) }
$dirty = git status --porcelain | Where-Object { $_ -notmatch '\.task\.md|\.shots/|\.godot/' }
if ($dirty) { Write-Output "uncommitted: $($dirty -join '; ')" }
Pop-Location
Write-Output ("changed files: " + ($changed -join ', '))

if ($fail.Count) {
    Write-Output "`nVERIFY: FAIL"
    $fail | ForEach-Object { Write-Output "- $_" }
    exit 1
}
Write-Output "`nVERIFY: PASS"
exit 0
