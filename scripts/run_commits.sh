#!/usr/bin/env bash
# Drive scripts/run.sh over a list of commits (the aggregation-timeline set).
# Each commit: pin -> build fresh index -> full suite -> results/<instance>/...json
# A failing commit (e.g. won't compile against old tantivy) is logged and skipped.
#
# Usage: scripts/run_commits.sh <commit> [<commit> ...]
set -uo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.."

ok=0; fail=0; failed=""
for c in "$@"; do
  echo "===== $(date +%H:%M:%S) START $c ====="
  ./scripts/run.sh "$c"; rc=$?
  if [ $rc -eq 0 ]; then
    echo "===== $(date +%H:%M:%S) OK $c ====="; ok=$((ok+1))
  else
    echo "===== $(date +%H:%M:%S) RUN_FAILED $c rc=$rc ====="; fail=$((fail+1)); failed="$failed $c"
  fi
done
echo "DRIVER_DONE ok=$ok fail=$fail failed=[$failed]"
