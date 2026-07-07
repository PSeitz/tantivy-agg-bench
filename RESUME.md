# Resume notes — aggregation perf timeline run

Working handoff for the benchmark-over-time run of the [selected commits](SELECTED_COMMITS.md).
Paused 2026-07-06. Safe to pick up in a new session.

## Status: 41 / 41 DONE ✅ (all commits benchmarked)

All 41 selected commits are benchmarked; results in `results/COMP-HQX4QHXQ7W/`
(41 well-formed JSONs, instance = this machine's hostname; a different machine
writes to its own `results/<instance>/` dir). The **chart** is built too — an
interactive Plotly website in `site/` (`build_site.py` → `site/data.js`; see below).

Run history (2026-07-06/07): the buggy 7 ran with the two heavy quadratic benches
skipped (`SKIP_BENCHES=terms_many_with_single_term`, ~8 min each vs ~76 min), so
those commits have **gaps** on `terms_many_with_single_term_*_order_by_card` —
the ~57 s plateau is still captured by the earlier buggy commits (`65b5a1a3` +
the 6 after it). Mid-run the **disk filled to 100%**; freed 10.3 GB with
`cargo clean` (per-rev `target/` artifacts) and finished the last 7 with
`run_commits_lowdisk.sh` (cleans `target/` when free space < `MIN_FREE_GB`, 4G).
**NOTE: the data volume runs near-full system-wide** — clean `target/` before big
reruns. Bench counts: 168 base → 184 (filter, `70e591e2`) → 204 (composite,
`545169c0d`); skipped-buggy show 196 (204−8 heavy) or 176 (pre-composite).

**Done (19, chronological):** `945af922 811c68cd 2340dca6 fc93391d d410a3b0
dabcaa58 938bfec8 60225bdd 70e591e2 c363bbd2 f88b7200 63c66005 65b5a1a3 4a89e745
f1c29ba9 bb141abe 698f073f 7eca3314 cf760fd5`

**Remaining (22, chronological — first one was interrupted mid-run, no JSON):**

```
18fedd938 545169c0d 3859cc869 a9535156b 3cd9011f8 04beab3b2 58aa4b707 2e16243f9
4fbae9218 73ad18fa1 ca139d8eb d47abdf10 edfb02b47 d99a5d4e9 46b3fb9ed b19f0ddc7
c096b2ad8 1e859fd78 74a510cb5 348ca1e30 715590b35 6b8bd7b88
```

## How to resume

```sh
cd ~/Development/tantivy-agg-bench
scripts/run_commits.sh 18fedd938 545169c0d 3859cc869 a9535156b 3cd9011f8 04beab3b2 \
  58aa4b707 2e16243f9 4fbae9218 73ad18fa1 ca139d8eb d47abdf10 edfb02b47 d99a5d4e9 \
  46b3fb9ed b19f0ddc7 c096b2ad8 1e859fd78 74a510cb5 348ca1e30 715590b35 6b8bd7b88
```

`run_commits.sh` calls `run.sh` per commit (pin → fresh index → full suite →
`results/<instance>/<date>-<short>.json`), restoring `Cargo.toml` after each. A
commit that fails is logged `RUN_FAILED` and skipped. Run it in the background;
re-running an already-done commit just overwrites its file (harmless).

## Remaining timing: skip the heavy benches on the buggy 7 (~3.5–4 h total)

The fix (below) lands *inside* this set, so only the first 7 remaining commits are
still buggy; the rest are healthy again. **No need to add an external commit —
the spike-and-recovery is fully contained in the timeline.**

The whole ~76 min/commit cost on buggy commits was just the two quadratic benches
`terms_many_with_single_term_order_by_card` + `..._2_order_by_card` (~57 s each on
full/dense/multivalue = ~340 s of the ~347 s total). We **skip those two** on the
buggy commits via `SKIP_BENCHES` (see below) — the ~57 s plateau is already
captured by the done buggy commits (`65b5a1a3` + the 6 after it), so the buggy 7
just get gaps there. Measured: `18fedd938` dropped from ~76 min to **~8 min**
(sum-of-medians 6.3 s, 176 benches). The other 9 regressed benches are all
sub-second and kept.

- **Buggy (~8 min each, heavy benches skipped), 2026-02-19 → 2026-04-13:**
  `18fedd938 545169c0d 3859cc869 a9535156b 3cd9011f8 04beab3b2 58aa4b707`
- **Fixed (~11 min each, full suite), 2026-04-21 → 2026-07-03:** `2e16243f9`
  (← recovery point) `4fbae9218 73ad18fa1 ca139d8eb d47abdf10 edfb02b47 d99a5d4e9
  46b3fb9ed b19f0ddc7 c096b2ad8 1e859fd78 74a510cb5 348ca1e30 715590b35 6b8bd7b88`

Estimate: 7×8 + 15×11 ≈ **~3.5–4 h**.

### Resume driver (what's running now)

`scripts/resume_remaining.sh` runs the buggy 7 with
`SKIP_BENCHES=terms_many_with_single_term` then the fixed 15 with the full suite:

```sh
cd ~/Development/tantivy-agg-bench
scripts/resume_remaining.sh > /tmp/resume_remaining.log 2>&1 &
```

`SKIP_BENCHES` is a comma-separated substring list honored by the `register!`
macro in `benches/agg_bench.rs` (`skip_bench`): any bench whose name contains a
listed substring is not registered. The harness edit persists across commit runs
(`run.sh` restores only `Cargo.toml`, not `agg_bench.rs`). Empty/unset = run all.
Re-running an already-done commit just overwrites its JSON.

## The regression we found — introduced #2759, fixed by ed3453606

**Introduced:** `65b5a1a3` — "one collector per agg request instead per bucket"
(#2759, 2026-01-06). **Fixed:** `ed3453606` — "agg fix: compute memory
consumption only for current bucket" (2026-04-21, Pascal Seitz), a 1-file change
in `bucket/term_agg.rs` that stops recomputing memory consumption too often (once
per current bucket instead of repeatedly). Already merged to `main`, so **current
tantivy is NOT affected** — the bug lived only in the window 2026-01-06 →
2026-04-21. Quadratic blow-up in **term aggregations ordered by / with a
sub-aggregation**:

| bench | before | after |
| ----- | ------ | ----- |
| `terms_many_with_single_term_order_by_card` | 267 ms | **56,355 ms** (~211×) |
| `terms_many_with_single_term_2_order_by_card` | 650 ms | 56,882 ms (~87×) |
| `terms_zipf_1000_with_terms_status_sub_agg` | 15 ms | 231 ms (~15×) |

11 benches regressed >3×; all `terms_* + sub-agg`. The `terms_many_*` variants
plateau at a near-constant ~56.7–56.9 s (O(terms²) over the fixed 150k-term set),
stable across every buggy-era commit → real, not noise. Plain aggs
(`average_u64`, histogram, etc.) are unaffected. `f88b7200` also shows a genuine
*improvement* (`full/average_u64` 3.95 → 3.1 ms) unrelated to the bug.

## Chart — an interactive website (`site/`)

The chart is a **static, self-contained website** (Plotly.js) — zoom/pan, hover a
point for the commit's date + `#PR · title`, and **click a point to open that
PR on GitHub** (`quickwit-oss/tantivy`, the upstream remote; falls back to the
commit when a point has no PR). PRs are resolved per commit via
`gh api repos/<slug>/commits/<sha>/pulls` and cached in `scripts/pr_cache.json`
(immutable per full SHA, committed); `build_site.py --no-pr` opts out (offline →
commit links). Build + view:

```sh
python3 scripts/build_site.py          # regenerate site/data.js from results/
open site/index.html                   # or: python3 -m http.server -d site 8000
```

Files: `site/index.html` (the app — hand-authored), `site/data.js` (generated:
the **whole** dataset + per-commit git metadata + GitHub URLs). Plotly loads from
CDN (`cdn.plot.ly/plotly-2.35.2.min.js`), so **viewing needs internet** — to make
it offline again, vendor that file locally and point the `<script src>` at it.
`build_site.py` is pure stdlib + `git`; no other deps.

Three views (a segmented toggle), all **log y-axis**, commits on an evenly-spaced
ordinal x ordered by **committer date**, labelled `date short`, with the #2759
window (2026-01-06 .. 2026-04-21) shaded:

- **Overview** — one line per category (average, stats, percentiles, cardinality,
  histogram, range, terms, composite, filter) = geomean of its benches normalised
  to each bench's first measurement (cheap/expensive weigh equally; a bench
  entering/leaving doesn't jolt the line).
- **Per category** — every bench in the chosen category, one line each, at the
  chosen cardinality. Category = primary agg from the bench-name prefix.
- **Per benchmark** — one line per cardinality (full/dense/sparse/multivalue).

Metric toggle: **Latency** (`median_ns`→ms) or **Memory** (`avg_memory`→KiB) — the
memory view visibly shows the #2759 blow-up (heavy benches ~5 GB in-window).
Missing points are **gaps** (Plotly `connectgaps:false`): composite/filter empty
before they exist; the two heavy `terms_many_*_order_by_card` benches gap over the
7 skipped commits (verified in headless-Chrome renders). State is mirrored to the
URL hash (`#view=bench&bench=...&metric=...&card=...`) so a specific chart is a
shareable link. Re-run `build_site.py` whenever new results land.

Bench-count context: 168 base → 184 at `70e591e2` (filter agg) → 204 at
`545169c0d` (composite); skipped-buggy commits show 196/176 (heavy benches gap).

## Harness facts (see README.md)

- `num_iter_group=1` baked in `bench_agg` (single sample; NUM_ITER_GROUP overrides).
- `SKIP_BENCHES=<substr>[,<substr>...]` excludes matching benches (via `skip_bench`).
- Index reuse is default & per-cardinality (`agg_bench/{full,dense,sparse,multivalue}/`);
  `run.sh` sets `REUSE_AGG_BENCH_INDEX=0` for a fresh index per commit.
- Unsupported aggs (composite/filter on older commits) auto-skip via `agg_supported`.
- tantivy pinned via the single `Cargo.toml` git dep; `run.sh` rewrites & restores it.
