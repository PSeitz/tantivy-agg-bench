#!/usr/bin/env bash
# Like run_commits.sh, but for a near-full disk: after each commit, if free space
# on the data volume drops below MIN_FREE_GB, `cargo clean` to reclaim the ~11 GB
# of accumulated per-rev build artifacts (safe/reproducible; next build recompiles).
#
# Usage: scripts/run_commits_lowdisk.sh <commit> [<commit> ...]
set -uo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.."

MIN_FREE_GB=${MIN_FREE_GB:-4}
# -k is portable across GNU and BSD df; avail is column 4 in 1K blocks.
free_gb() { df -k /System/Volumes/Data 2>/dev/null | awk 'NR==2{print int($4/1024/1024)}'; }

ok=0; fail=0; failed=""
for c in "$@"; do
  fg=$(free_gb)
  if [ -n "$fg" ] && [ "$fg" -lt "$MIN_FREE_GB" ]; then
    echo "===== $(date +%H:%M:%S) LOW DISK (${fg}G < ${MIN_FREE_GB}G) -> cargo clean ====="
    cargo clean
  fi
  echo "===== $(date +%H:%M:%S) START $c (free ${fg}G) ====="
  ./scripts/run.sh "$c"; rc=$?
  if [ $rc -eq 0 ]; then
    echo "===== $(date +%H:%M:%S) OK $c ====="; ok=$((ok+1))
  else
    echo "===== $(date +%H:%M:%S) RUN_FAILED $c rc=$rc ====="; fail=$((fail+1)); failed="$failed $c"
  fi
done
echo "DRIVER_DONE ok=$ok fail=$fail failed=[$failed]"
