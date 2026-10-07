# Independent check of the art lane (image pipeline repo). Exit 0 = pass, 1 = fail.
param(
    [Parameter(Mandatory)] [string] $Worktree,
    [Parameter(Mandatory)] [string] $BaseRef,
    [string] $ShotDir
)
$ErrorActionPreference = 'Continue'
$PY = 'E:\AI\ComfyUI\python_embeded\python.exe'
$fail = [System.Collections.Generic.List[string]]::new()
Push-Location $Worktree

Write-Output "== compile"
$py = Get-ChildItem -Recurse -Filter *.py | Where-Object FullName -notmatch '\\out\\|__pycache__'
foreach ($f in $py) { $o = & $PY -m py_compile $f.FullName 2>&1 | Out-String; if ($LASTEXITCODE) { $fail.Add("compile $($f.Name): $o") } }
Write-Output "$($py.Count) files"

Write-Output "== unit tests"
if (Test-Path tests) {
    $o = & $PY -m unittest discover -s tests 2>&1 | Out-String
    ($o -split "`r?`n") | Where-Object { $_ -match '^(Ran|OK|FAILED|ERROR|FAIL:)' } | Write-Output
    if ($LASTEXITCODE) { $fail.Add("unit tests failed:`n" + (($o -split "`r?`n") | Select-Object -Last 25 | Out-String)) }
}

Write-Output "== content guards on set files"
$banned = 'school|student|uniform|teen|minor|loli|shota|child|kid\b|young|petite|nude|naked|nipple|topless|see-through|sheer|explicit|nsfw|sex|marin|bulma|velma|jill|ada wong|rias|akeno|saeko|valentine|kitagawa|dxd|highschool'
foreach ($s in Get-ChildItem sets -Filter *.json -ErrorAction SilentlyContinue) {
    $raw = Get-Content $s.FullName -Raw
    if ($raw -match "(?i)\b($banned)") { $fail.Add("$($s.Name): banned term '$($Matches[1])'") }
    try { $j = $raw | ConvertFrom-Json } catch { $fail.Add("$($s.Name): invalid JSON"); continue }
    foreach ($c in $j.cards) {
        if ($c.rating -notin 'general', 'sensitive') { $fail.Add("$($s.Name)/$($c.card_id): rating '$($c.rating)'") }
        if ($c.rating -eq 'sensitive' -and $c.rarity -notin 'epic', 'legendary') { $fail.Add("$($s.Name)/$($c.card_id): sensitive on $($c.rarity)") }
    }
}

Write-Output "== diff guards"
$changed = git diff --name-only "$BaseRef..HEAD"
$img = $changed | Where-Object { $_ -match '\.(png|jpe?g|webp|onnx|safetensors|mp4)$' }
if ($img) { $fail.Add("binary/art files committed: $($img -join ', ')") }
if ($changed | Where-Object { $_ -match '^(ARTIST\.md|opencode\.json)$' }) { $fail.Add('touched protected files') }
$authors = git log --format='%an <%ae>' "$BaseRef..HEAD" | Sort-Object -Unique | Where-Object { $_ -ne 'waifu-dev <waifu-dev@users.noreply.local>' }
if ($authors) { $fail.Add("non-anonymous author: $authors") }
Write-Output ("changed: " + ($changed -join ', '))
Pop-Location

if ($fail.Count) { Write-Output "`nVERIFY: FAIL"; $fail | ForEach-Object { Write-Output "- $_" }; exit 1 }
Write-Output "`nVERIFY: PASS"; exit 0
