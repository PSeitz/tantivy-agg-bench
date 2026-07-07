# Selected commits for the aggregation performance timeline

These are the tantivy commits benchmarked to chart **aggregation performance over
time**. Each is a commit that actually changed the aggregation code, so every
point on the graph corresponds to a real aggregation change and can be labelled
with its commit info (date, hash, author, subject).

**41 commits**, spanning **2025-07-02 → 2026-07-03** (committer date).

## How they were selected

1. **Range** — commits reachable from the current `main` tip
   (`6b8bd7b8`, tagged `upstream/main`, 2026-07-03) but not from the `0.24`
   release tag (2025-04-09): `0.24..6b8bd7b8`. That's 259 commits total.
2. **Filter: only aggregation changes** — keep commits that modify the
   aggregation module `src/aggregation/`. That narrows 259 → **83 commits**.
   (The earliest is 2025-07-02: there were no aggregation changes on `main` in
   the ~3 months right after 0.24.)
3. **Thin to ≤ 50: one commit per day** — collapse to at most one commit per
   calendar day, keyed by **committer date**, keeping the **newest** aggregation
   commit of each day. That yields **41 commits** — already under the 50 cap, so
   no further thinning was needed.

Why these choices:

- **Committer date, not author date** — it's when the change actually landed on
  `main`, which is the timeline we plot. (Author date would place a few
  long-lived PRs months earlier and distort the x-axis; it also gives 53 days,
  over the cap.)
- **Newest-of-day** — a commit is benchmarked at its full tree state, so the
  last aggregation commit of a day captures that day's complete aggregation
  state.

Reproduce the selection from a tantivy checkout:

```sh
git log 0.24..6b8bd7b8 --date=short --format='%cd|%h|%s' -- src/aggregation/ \
  | awk -F'|' '!seen[$1]++'      # newest per committer-day (log is newest-first)
```

Total aggregation churn across the 41 selected commits: **+11,173 / −2,001**
lines (137 file-changes under `src/aggregation/`).

## Benchmarking them

Run one recorded benchmark per commit (oldest → newest), writing
`results/<instance>/<date>-<short>.json` each:

```sh
for c in 945af922d 811c68cdb 2340dca62 fc93391d0 d410a3b0c dabcaa580 938bfec8b \
         60225bdd4 70e591e23 c363bbd23 f88b7200b 63c66005d 65b5a1a30 4a89e7459 \
         f1c29ba97 bb141abe2 698f073f8 7eca33143 cf760fd5b 18fedd938 545169c0d \
         3859cc869 a9535156b 3cd9011f8 04beab3b2 58aa4b707 2e16243f9 4fbae9218 \
         73ad18fa1 ca139d8eb d47abdf10 edfb02b47 d99a5d4e9 46b3fb9ed b19f0ddc7 \
         c096b2ad8 1e859fd78 74a510cb5 348ca1e30 715590b35 6b8bd7b88; do
  scripts/run.sh "$c"
done
```

At ~508 s of benchmark wall-time per commit, 41 commits is ≈ 5.8 h (plus a
tantivy recompile per commit).

## The commits

Chronological (oldest first). Churn = lines added/removed under
`src/aggregation/` by that commit.

| committer date | commit | agg churn | author | subject |
| -------------- | ------ | --------- | ------ | ------- |
| 2025-07-02 | `945af922d` | +1/-1 | PSeitz | clippy (#2661) |
| 2025-07-21 | `811c68cdb` | +1/-0 | PSeitz-dd | fix field_names in top_hits aggregation (#2675) |
| 2025-09-19 | `2340dca62` | +1/-1 | PSeitz-dd | fix compiler warnings (#2699) |
| 2025-10-14 | `fc93391d0` | +9/-9 | Remi | Minor clarifications on the AggregationsWithAccessor refacto (#2716) |
| 2025-10-15 | `d410a3b0c` | +341/-12 | PSeitz | Add Filtering for Term Aggregations (#2717) |
| 2025-10-17 | `dabcaa580` | +143/-8 | PSeitz | fix merge intermediate aggregation results (#2719) |
| 2025-10-21 | `938bfec8b` | +5/-3 | PSeitz | use FxHashMap for Aggregations Request (#2722) |
| 2025-10-23 | `60225bdd4` | +19/-9 | PSeitz | cleanup (#2724) |
| 2025-11-18 | `70e591e23` | +1970/-38 | Moe | feat: added filter aggregation (#2711) |
| 2025-11-21 | `c363bbd23` | +516/-172 | Paul Masurel | Optimize term aggregation with low cardinality + some refactoring (#2740) |
| 2025-11-26 | `f88b7200b` | +3/-2 | Paul Masurel | Optimization when posting list are saturated. (#2745) |
| 2025-12-01 | `63c66005d` | +17/-15 | Paul Masurel | Lazy scorers (#2726) |
| 2026-01-06 | `65b5a1a30` | +2106/-1185 | PSeitz-dd | one collector per agg request instead per bucket (#2759) |
| 2026-01-30 | `4a89e7459` | +1/-1 | Paul Masurel | Fix rfc3339 typos and add Claude Code skills (#2823) |
| 2026-02-06 | `f1c29ba97` | +8/-0 | cong.xie | resolve conflcit |
| 2026-02-09 | `bb141abe2` | +5/-0 | cong.xie | feat(aggregation): add keys() accessor to IntermediateAggregationResults |
| 2026-02-11 | `698f073f8` | +3/-3 | cong.xie | fix fmt |
| 2026-02-12 | `7eca33143` | +5/-4 | cong.xie | Remove Datadog-specific references from comments |
| 2026-02-18 | `cf760fd5b` | +1/-1 | cong.xie | fix: remove internal reference from code comment |
| 2026-02-19 | `18fedd938` | +1/-2 | cong.xie | Fix nightly fmt: merge crate imports in percentiles tests |
| 2026-03-18 | `545169c0d` | +4356/-9 | Paul Masurel | Composite agg merge (#2856) |
| 2026-03-24 | `3859cc869` | +10/-8 | nuri | fix: deduplicate doc counts in term aggregation for multi-valued fields (#2854) |
| 2026-03-26 | `a9535156b` | +2/-4 | Charlie Tonneslan | Fix clippy warnings: deprecated gen_range, manual div_ceil, legacy import (#2860) |
| 2026-04-09 | `3cd9011f8` | +4/-4 | alexanderbianchi | Make BucketEntries::iter, PercentileValuesVecEntry fields, and TopNComputer::threshold public (#2890) |
| 2026-04-10 | `04beab3b2` | +487/-185 | Paul Masurel | Performance improvement for nested cardinality aggregation |
| 2026-04-13 | `58aa4b707` | +8/-12 | Paul Masurel | Fix cardinality aggregation using invalid coupons (#2893) |
| 2026-04-21 | `2e16243f9` | +11/-10 | Pascal Seitz | fix memory consumption for histogram |
| 2026-04-24 | `4fbae9218` | +69/-48 | Abdul Andha | send after key on last page |
| 2026-04-25 | `73ad18fa1` | +112/-6 | RJ Barman | fix: Add space for missing sentinel in allowed bitset when a missing key is provided (#119) (#2907) |
| 2026-04-27 | `ca139d8eb` | +70/-48 | trinity-1686a | Merge pull request #2910 from quickwit-oss/abdul.andha/composite-agg-after |
| 2026-04-28 | `d47abdf10` | +514/-25 | Pascal Seitz | early cut off for order by sub agg in term agg |
| 2026-05-05 | `edfb02b47` | +138/-63 | Pascal Seitz | switch to enum, fix mixed types for cardinality agg |
| 2026-05-16 | `d99a5d4e9` | +12/-5 | Mohammad Dashti | Rename validate_aggregation_fields to validate_aggregation_fields_exist |
| 2026-05-19 | `46b3fb9ed` | +8/-4 | Paul Masurel | Relying on upstream version of datasketch and stop using HLL 4. (#2936) |
| 2026-06-09 | `b19f0ddc7` | +18/-17 | Pascal Seitz | fix clippy |
| 2026-06-16 | `c096b2ad8` | +73/-17 | Pascal Seitz | aggregation/terms: charge fused term_counts to the memory limit |
| 2026-06-18 | `1e859fd78` | +22/-4 | Pascal Seitz | fix term aggregation u32::MAX overflow issue |
| 2026-06-29 | `74a510cb5` | +33/-19 | trinity.pointard | try to use select-nth instead of full sort in segment level agg top-k selection |
| 2026-06-30 | `348ca1e30` | +29/-11 | trinity.pointard | don't count matching doc twice |
| 2026-07-02 | `715590b35` | +3/-3 | trinity.pointard | rename local var |
| 2026-07-03 | `6b8bd7b88` | +38/-33 | Pascal Seitz | reorder if block |
