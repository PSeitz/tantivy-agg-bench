#!/usr/bin/env bash
#
# Run the aggregation benchmark against a specific tantivy commit and save the
# results as JSON under results/<instance>/<date>-<short-hash>.json
#
# Usage:
#   scripts/run.sh <commit-ish> [instance]
#
#   <commit-ish>  tantivy commit hash (full or short). Tags/branches also work.
#   [instance]    label for this machine (default: short hostname). Numbers from
#                 different machines are not comparable, so keep them separate.
#
# Env:
#   FILTER   only run benchmarks whose name contains this substring.
#
# binggan already writes each benchmark's result as JSON, so there is nothing to
# parse: this script just concatenates those fragments into one document and
# prepends run metadata. No jq or other tooling required — only bash + coreutils,
# so it runs on any machine.

set -euo pipefail

REPO="https://github.com/quickwit-oss/tantivy"

commitish="${1:-}"
if [ -z "$commitish" ]; then
  echo "usage: scripts/run.sh <commit-ish> [instance]   (env: FILTER=<substr>)" >&2
  exit 2
fi
instance="${2:-$(hostname -s 2>/dev/null || hostname)}"

# Work from the project root (parent of this script's directory).
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "$script_dir/.."

# --- back up manifest/lock and the binggan output dir; restore on exit -------
toml_bak=$(mktemp)
cp Cargo.toml "$toml_bak"
lock_bak=""
[ -f Cargo.lock ] && { lock_bak=$(mktemp); cp Cargo.lock "$lock_bak"; }
bh=$(mktemp -d)                          # fresh binggan home => only this run's files
cleanup() {
  cp "$toml_bak" Cargo.toml; rm -f "$toml_bak"
  if [ -n "$lock_bak" ]; then cp "$lock_bak" Cargo.lock; rm -f "$lock_bak"; fi
  rm -rf "$bh"
}
trap cleanup EXIT

# --- point tantivy at the requested commit ----------------------------------
echo ">> pinning tantivy to '$commitish'"
sed -i.sedbak -E "s|^tantivy = .*|tantivy = { git = \"$REPO\", rev = \"$commitish\" }|" Cargo.toml
rm -f Cargo.toml.sedbak

# --- resolve to the exact commit cargo picked (from Cargo.lock, no jq) -------
echo ">> resolving ..."
cargo fetch >/dev/null 2>&1 || cargo fetch    # rerun visibly if it failed
full_sha=$(awk '/^name = "tantivy"$/{f=1} f && /^source = /{print; exit}' Cargo.lock \
             | sed -E 's/.*#([0-9a-fA-F]+)".*/\1/')
full_sha=${full_sha:-$commitish}
short=${full_sha:0:8}

date_str=$(date +%Y-%m-%d)
ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
out_dir="results/$instance"
mkdir -p "$out_dir"
out="$out_dir/$date_str-$short.json"
log="$out_dir/$date_str-$short.log"

# --- run --------------------------------------------------------------------
# Build a fresh index per commit: reuse is the bench default, but reusing an
# index another commit wrote risks a format mismatch (and muddies provenance),
# and a rebuild is only ~20s. Interactive `cargo bench` still reuses by default.
export REUSE_AGG_BENCH_INDEX=0
echo ">> benchmarking $short  (instance: $instance)"
if [ -n "${FILTER:-}" ]; then
  BINGGAN_HOME="$bh" cargo bench -- "$FILTER" 2>&1 | tee "$log"
else
  BINGGAN_HOME="$bh" cargo bench 2>&1 | tee "$log"
fi

# --- collect: each file in $bh is already a JSON object ----------------------
os=$(uname -s); arch=$(uname -m)
cpu=$(sysctl -n machdep.cpu.brand_string 2>/dev/null \
      || { grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2- | sed 's/^ *//'; } \
      || echo unknown)
rustc_v=$(rustc --version 2>/dev/null || echo unknown)

esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }   # minimal JSON string escaping

first=1
count=0
{
  printf '{\n'
  printf '  "instance": "%s",\n'      "$(esc "$instance")"
  printf '  "date": "%s",\n'          "$date_str"
  printf '  "timestamp": "%s",\n'     "$ts"
  printf '  "requested_ref": "%s",\n' "$(esc "$commitish")"
  printf '  "commit": "%s",\n'        "$full_sha"
  printf '  "short_hash": "%s",\n'    "$short"
  printf '  "filter": %s,\n' "$( [ -n "${FILTER:-}" ] && printf '"%s"' "$(esc "$FILTER")" || printf 'null' )"
  printf '  "system": { "os": "%s", "arch": "%s", "cpu": "%s", "rustc": "%s" },\n' \
         "$(esc "$os")" "$(esc "$arch")" "$(esc "$cpu")" "$(esc "$rustc_v")"
  printf '  "benchmarks": {\n'
  for f in "$bh"/*; do
    [ -f "$f" ] || continue
    base=${f##*/}; name=${base#_}                 # strip leading _ (empty runner name)
    case "$name" in                               # split "<input>_<bench>" -> "<input>/<bench>"
      full_*)       key="full/${name#full_}";;
      dense_*)      key="dense/${name#dense_}";;
      sparse_*)     key="sparse/${name#sparse_}";;
      multivalue_*) key="multivalue/${name#multivalue_}";;
      *)            key="$name";;
    esac
    [ $first -eq 0 ] && printf ',\n'
    printf '    "%s": %s' "$key" "$(head -n1 "$f")"
    first=0; count=$((count + 1))
  done
  printf '\n  }\n'
  printf '}\n'
} > "$out"

echo ">> wrote $out  ($count benchmarks)"
echo ">> log:   $log"
