#!/usr/bin/env bash
# Experiment: does NUM_ITER_GROUP=1 still give stable numbers?
#
# num_iter_group is binggan's OUTER loop: the whole group is run that many times
# and min/max/median/average are computed over those samples. At 1 there is a
# single sample per bench (min==max==median), so stability can only be judged by
# REPEATING the whole run and comparing medians. We do R runs at group=1 and R at
# the default 32, on the same benches, and compare run-to-run spread.
#
# Uses REUSE_AGG_BENCH_INDEX so the (real `full`) index is built once and reused;
# the `full` workload is the fastest -> the worst case for timing noise, so it is
# a conservative stability test.
set -euo pipefail

R=6
FILTER='average_u64 OR percentiles_f64 OR terms_7 OR terms_many_top_1000 OR terms_all_unique OR cardinality_agg_low_card'

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.."
export REUSE_AGG_BENCH_INDEX=1

exp=/tmp/niter_exp
rm -rf "$exp"; mkdir -p "$exp"

rm -rf agg_bench   # drop any stale/empty index dir so the first REUSE run rebuilds it
echo ">> building tantivy + index once (reused for every run) ..."
BINGGAN_HOME="$exp/warmup" cargo bench -- "$FILTER" >"$exp/build.log" 2>&1
echo ">> build done"

run() {                 # run <setting-label> <run-idx> <extra-env...>
  local label=$1 i=$2; shift 2
  local home="$exp/${label}_run${i}"; mkdir -p "$home"
  env "$@" BINGGAN_HOME="$home" cargo bench -- "$FILTER" >"$home/out.log" 2>&1
}

for i in $(seq 1 "$R"); do
  echo ">> group=1  run $i/$R"
  run g1 "$i" NUM_ITER_GROUP=1
done
for i in $(seq 1 "$R"); do
  echo ">> group=32 run $i/$R"
  run g32 "$i"                 # default (32)
done

echo ">> EXPERIMENT_DONE"
