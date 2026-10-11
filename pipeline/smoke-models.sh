#!/bin/bash
# Smoke-test candidate free models: one trivial prompt each, bounded at 90s.
OC="$APPDATA/npm/node_modules/opencode-ai/bin/opencode.exe"
OUT="/e/AI/Waifu Card Game/pipeline/logs/model-smoke.txt"
: > "$OUT"
MODELS=(
  opencode/mimo-v2.6-flash-free
  opencode/nemotron-3.5-lightning-free
  opencode/ling-3.1-flash-free
  opencode/step-5-preview-free
  opencode/longcat-2.5-preview-free
  opencode/nemotron-3-ultra-free
  opencode/exo-free
  opencode/ling-3.0-flash-fin-free
  opencode/muse-spark-1.3-contributor-free
  opencode/space-bunny-free
)
for m in "${MODELS[@]}"; do
  echo "=== $m $(date +%H:%M:%S)" >> "$OUT"
  resp=$(timeout 90 "$OC" run --model "$m" --dir "E:\\AI\\Waifu Card Game" "Reply with exactly: OK" 2>>"$OUT")
  rc=$?
  if [ $rc -eq 124 ]; then
    echo "RESULT $m TIMEOUT90" >> "$OUT"
  elif [ -n "$resp" ]; then
    echo "RESULT $m OK :: $(echo "$resp" | head -c 120 | tr '\n' ' ')" >> "$OUT"
  else
    echo "RESULT $m EMPTY rc=$rc" >> "$OUT"
  fi
done
echo "SMOKE DONE $(date +%H:%M:%S)" >> "$OUT"
