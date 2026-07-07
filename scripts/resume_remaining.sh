#!/usr/bin/env bash
# Resume the paused agg-timeline run for the 22 remaining commits.
#
# The 7 buggy #2759 commits (2026-01-06..04-21 window) skip the two heavy
# quadratic benches (terms_many_with_single_term_*_order_by_card, ~57s each on
# full/dense/multivalue = ~340s/commit) via SKIP_BENCHES — they only re-confirm
# the known ~57s plateau already captured by the done buggy commits. The 15
# fixed commits (2e16243f9 onward) run the full suite.
set -uo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.."

echo "### BUGGY BATCH (7) — skip heavy *_order_by_card benches ###"
SKIP_BENCHES=terms_many_with_single_term \
  ./scripts/run_commits.sh 18fedd938 545169c0d 3859cc869 a9535156b 3cd9011f8 04beab3b2 58aa4b707

echo "### FIXED BATCH (15) — full suite ###"
./scripts/run_commits.sh 2e16243f9 4fbae9218 73ad18fa1 ca139d8eb d47abdf10 edfb02b47 \
  d99a5d4e9 46b3fb9ed b19f0ddc7 c096b2ad8 1e859fd78 74a510cb5 348ca1e30 715590b35 6b8bd7b88

echo "ALL_DONE"
