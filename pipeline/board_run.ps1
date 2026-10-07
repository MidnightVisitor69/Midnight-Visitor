# Regenerates pipeline\board.html every minute (scheduled). No model involved.
# Uses main's copy of the board script once B-001 lands, else the card lane's worktree copy.
$root = 'E:\AI\Waifu Card Game'
foreach ($s in "$root\tools\board\board.mjs", 'E:\AI\waifu-pipeline-wt\tools\board\board.mjs') {
    if (Test-Path $s) { & node $s --root $root --out "$root\pipeline\board.html" 2>&1 | Out-Null; break }
}
