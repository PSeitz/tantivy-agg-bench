# tantivy-agg-bench

Track [tantivy](https://github.com/quickwit-oss/tantivy) **aggregation
performance over time** — across commits and across machines.

The goal is a stable yardstick: the same benchmark suite, the same deterministic
dataset, run against any point in tantivy's history, so you can spot regressions,
compare releases, and re-measure old commits on new hardware.

## Why it can run against any commit

Aggregation requests are expressed as JSON (`serde_json::json!` →
`Aggregations`), and the benchmark only touches tantivy's stable surface
(`Index`, `Schema`, `AggregationCollector`, `Term`). That JSON interface barely
changes between versions, so the *same* file compiles and runs across a wide
range of commits — you only swap the pinned revision. Three things make this
work:

- **tantivy is a git dependency** — point it at any commit/branch/tag (see below).
- **The harness deps are pinned here** (`binggan`, `rand`, `rand_distr`,
  `serde_json`), independent of whatever versions the target tantivy uses
  internally. Cargo lets both coexist, so switching commits never drags the
  benchmark's own deps around.
- **Aggregations missing on a commit are auto-skipped**, not fatal — so old
  commits still produce results for everything they *do* support (see
  [Compatibility](#compatibility)).

## Quick start

```sh
cargo bench
```

First run builds the pinned tantivy and indexes a deterministic dataset (~1M docs
per cardinality variant), so it takes a few minutes. The index is then persisted
per cardinality under `agg_bench/` and **reused** on later runs (set
`REUSE_AGG_BENCH_INDEX=0` to force a rebuild). Each benchmark prints wall time and
peak memory (via binggan), plus the delta versus the previous run.

## Tracking performance over time

There are two axes — **which commit** and **which machine** — and they're
handled differently.

### Recording a run: `scripts/run.sh`

The main mechanism. Benchmark one commit and save the results as JSON:

```sh
scripts/run.sh <commit-ish> [instance]      # instance defaults to the hostname
scripts/run.sh 6b8bd7b8                      # a commit hash (short or full)
scripts/run.sh 0.25.0 ci-box                 # tags/branches work too
FILTER=cardinality scripts/run.sh 6b8bd7b8   # only matching benchmarks
```

It pins tantivy to that commit, runs the suite, and writes

```
results/<instance>/<date>-<short-hash>.json
results/<instance>/<date>-<short-hash>.log    # raw stdout, for reference
```

then restores `Cargo.toml`/`Cargo.lock` to their defaults. The JSON records the
resolved commit, machine/system info, and every benchmark's stats:

```json
{
  "instance": "my-macbook",
  "date": "2026-07-05",
  "commit": "6b8bd7b8847c...",
  "short_hash": "6b8bd7b8",
  "system": { "os": "Darwin", "arch": "arm64", "cpu": "Apple M1 Pro", "rustc": "rustc 1.x" },
  "benchmarks": {
    "full/cardinality_agg": { "min_ns": 12762227, "max_ns": 13531050, "average_ns": 13116668, "median_ns": 13062318, "avg_memory": 5938691 },
    "dense/cardinality_agg": { "...": "..." }
  }
}
```

binggan already emits each result as JSON, so the script just concatenates those
fragments and prepends metadata — **no jq or other tooling**, only bash +
coreutils, so it runs on any instance. Aggregations the commit doesn't support
simply don't appear in `benchmarks`.

To build a time series, run it per commit; to compare across hardware, run the
same commits under different `instance` labels. Diffing two runs is a plain JSON
comparison keyed by `benchmarks."<input>/<name>".median_ns`.

### The dataset is deterministic

The index is built from a fixed RNG seed (`StdRng::from_seed([1u8; 32])`), so
every run on every machine indexes the *same* documents. Numbers are therefore
comparable run-to-run and machine-to-machine for the same commit; nothing needs
to be captured or shared to reproduce the corpus.

### Across machines

Absolute times are **not** comparable between machines — only *trends* are. Run
`scripts/run.sh` under a distinct `instance` label per machine so each machine
gets its own `results/<instance>/` series. A regression that's real shows up as
the same relative jump on every machine; a machine-specific blip does not.

### Interactive A/B (binggan's delta column)

For quick, eyeball comparisons without recording files, run `cargo bench`
directly: binggan writes each result under `$BINGGAN_HOME` (→
`$CARGO_TARGET_DIR/binggan` → `target/binggan`) and, on the next run, prints the
change against it. So run on commit A, switch the pinned `rev` to commit B, run
again — the second output's delta column is the diff. Keep the machine idle.
(`scripts/run.sh` deliberately uses a throwaway `BINGGAN_HOME` so its captured
JSON only ever contains the current run.)

### Index reuse (`REUSE_AGG_BENCH_INDEX`)

By default the index is **persisted and reused**: each cardinality is built once
under its own directory (`agg_bench/{full,dense,multivalue,sparse}/`) and later
runs open it, skipping the multi-minute rebuild. The dataset is deterministic, so
a reused index is identical to a freshly built one.

Set `REUSE_AGG_BENCH_INDEX=0` (or `false`/`no`) to force a fresh build every time
— useful when the pinned commit changes the index format and an old on-disk index
can no longer be opened. `scripts/run.sh` sets this, so each recorded commit
builds its own index rather than reusing another commit's (see below).

## Pointing at a commit or release

Edit the single `tantivy = { ... }` line in `Cargo.toml`:

```toml
# exact commit (most reproducible)
tantivy = { git = "https://github.com/quickwit-oss/tantivy", rev = "<40-char sha>" }
# a branch (use `cargo update -p tantivy` to re-fetch a moving branch)
tantivy = { git = "https://github.com/quickwit-oss/tantivy", branch = "main" }
# a release tag
tantivy = { git = "https://github.com/quickwit-oss/tantivy", tag = "0.26.1" }
```

Release reference points:

| release | tag       | date       |
| ------- | --------- | ---------- |
| 0.24    | `0.24`    | 2025-04-09 |
| 0.24.1  | `0.24.1`  | 2025-04-22 |
| 0.24.2  | `0.24.2`  | 2025-07-17 |
| 0.25.0  | `0.25.0`  | 2025-08-20 |
| 0.26.1  | `0.26.1`  | 2026-05-10 |

Note 0.24's initial tag is `0.24`, not `0.24.0`. There are 259 commits on `main`
between `0.24` and the currently pinned commit.

### Benchmarking local, uncommitted work

Swap the git dependency for a path and switch commits in that checkout:

```toml
tantivy = { path = "/Users/pascal.seitz/Development/tantivy" }
```

```sh
( cd /Users/pascal.seitz/Development/tantivy && git checkout <commit> )
cargo bench
```

## What gets benchmarked

- **Inputs** — four cardinality shapes of the same corpus: `full`, `dense`,
  `sparse` (~50k docs), `multivalue` (~1M docs each otherwise).
- **Aggregations** — terms (various cardinalities, ordering, sub-aggs),
  histogram / date_histogram, range, cardinality, stats / extended_stats,
  percentiles, top_hits, and — where the pinned commit supports them —
  composite and filter.

Filter which benchmarks run by name: `cargo bench cardinality`. (The index is
reused by default, so after the first build only the selected benchmarks run.)

## Compatibility

Aggregations that don't exist on the pinned commit are skipped automatically, so
the same file runs across versions without edits. Before registering the
`composite` and `filter` benchmarks, `bench_agg` probes the build with
`agg_supported()` (a throwaway `serde_json::from_value::<Aggregations>`); if the
aggregation isn't recognized it prints

```
skipping composite benchmarks: not supported by this tantivy build
```

and leaves them out. This matters because `execute_agg` `.unwrap()`s the JSON
deserialization and **binggan does not isolate panics** — one unsupported
aggregation would otherwise abort the whole run before any results print.

If you add benchmarks for other newer-only aggregations, gate them the same way.
`cargo test` checks that the existing probes still deserialize against the pinned
tantivy, so a supported aggregation is never skipped by mistake.

## Layout

```
Cargo.toml            # tantivy = { git = ..., rev/tag = ... }  (default pin)
benches/agg_bench.rs  # the benchmark suite
src/lib.rs            # empty crate root + probe tests (cargo test)
scripts/run.sh        # run one commit -> results/<instance>/<date>-<short>.json
results/<instance>/   # recorded runs, one JSON (+ log) per commit
```
