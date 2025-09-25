#!/usr/bin/env bash
# filters coverage/lcov.info to keep only entries for contracts/Router.sol (and optionally others)
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LCOV_IN="$ROOT_DIR/coverage/lcov.info"
LCOV_OUT="$ROOT_DIR/coverage/lcov.router.info"
TARGET_PATTERN="contracts/Router.sol"

if [ ! -f "$LCOV_IN" ]; then
  echo "lcov info not found at $LCOV_IN. Run 'forge coverage --ir-minimum' first."
  exit 1
fi

# Extract only sections for files matching the pattern
awk -v pat="$TARGET_PATTERN" '
  BEGIN {keep=0}
  /^SF:/ {keep = ($0 ~ pat)}
  { if (keep) print $0 }
' "$LCOV_IN" > "$LCOV_OUT"

if [ ! -s "$LCOV_OUT" ]; then
  echo "No entries matched pattern $TARGET_PATTERN"
  exit 1
fi

# compute simple coverage percentages from filtered file
# count total lines (DA: lines found by 'DA:'), tested lines (DA lines with count>0), branches (BRDA) and taken
total_lines=0
covered_lines=0
while read -r line; do
  if [[ $line == DA:* ]]; then
    total_lines=$((total_lines+1))
    # DA:lineno,count
    count=${line#DA:*,}
    if [[ $count != 0 ]]; then
      covered_lines=$((covered_lines+1))
    fi
  fi
  if [[ $line == BRDA:* ]]; then
    # ensure branch counting present; we'll rely on `genhtml` for detailed branch metrics if needed
    :
  fi
done < "$LCOV_OUT"

pct_lines=0
if [ $total_lines -gt 0 ]; then
  pct_lines=$(awk "BEGIN {printf \"%.2f\", ($covered_lines/$total_lines)*100}")
fi

echo "Filtered LCOV written to: $LCOV_OUT"
echo "Router-only lines covered: $covered_lines / $total_lines ($pct_lines%)"

# Print the filtered file path for CI consumption
exit 0
