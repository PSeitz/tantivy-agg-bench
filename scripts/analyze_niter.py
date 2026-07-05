#!/usr/bin/env python3
"""Analyze the NUM_ITER_GROUP stability experiment written to /tmp/niter_exp.

For each setting (g1 = num_iter_group 1, g32 = default 32) we have R run
directories, each a BINGGAN_HOME holding one JSON file per bench. We compare the
run-to-run coefficient of variation (CV = stdev/mean of median_ns across runs).
Lower CV = more stable. We also report whether min==max==median within a run.
"""
import glob, json, os, statistics as st

EXP = "/tmp/niter_exp"

def load(setting):
    # bench_name -> list of (median_ns, min_ns, max_ns) across runs.
    # Only use COMPLETE run dirs (same file count as the fullest run) so a
    # stopped/in-progress run is discarded rather than skewing the stats.
    run_dirs = sorted(glob.glob(f"{EXP}/{setting}_run*"))
    counts = {r: len([f for f in glob.glob(f"{r}/*") if os.path.isfile(f)])
              for r in run_dirs}
    full = max(counts.values()) if counts else 0
    runs = [r for r in run_dirs if counts[r] == full and full > 0]
    data = {}
    for r in runs:
        for f in glob.glob(f"{r}/*"):
            if not os.path.isfile(f):
                continue
            try:
                with open(f) as fh:
                    j = json.load(fh)
            except (json.JSONDecodeError, KeyError):
                continue
            name = os.path.basename(f).lstrip("_")
            data.setdefault(name, []).append(
                (j["median_ns"], j["min_ns"], j["max_ns"])
            )
    return data, len(runs)

def cv(xs):
    m = st.mean(xs)
    return (st.pstdev(xs) / m * 100.0) if m else 0.0

g1, n1 = load("g1")
g32, n32 = load("g32")

print(f"runs: g1={n1}  g32={n32}\n")
hdr = f"{'bench':<40}{'g32 med(µs)':>13}{'g32 CV%':>9}{'g1 med(µs)':>13}{'g1 CV%':>9}{'Δmed%':>8}"
print(hdr); print("-" * len(hdr))

names = sorted(set(g1) | set(g32))
g1_cvs, g32_cvs = [], []
for name in names:
    a = g32.get(name, []); b = g1.get(name, [])
    if not a or not b:
        continue
    a_med = [x[0] for x in a]; b_med = [x[0] for x in b]
    ma, mb = st.mean(a_med), st.mean(b_med)
    ca, cb = cv(a_med), cv(b_med)
    g32_cvs.append(ca); g1_cvs.append(cb)
    dmed = (mb - ma) / ma * 100.0 if ma else 0.0
    short = name.replace("cardinality_agg_low_card", "card_low")
    print(f"{short:<40}{ma/1000:>13.1f}{ca:>9.2f}{mb/1000:>13.1f}{cb:>9.2f}{dmed:>+8.1f}")

def summ(tag, cvs):
    if cvs:
        print(f"  {tag:<8} CV%  mean={st.mean(cvs):.2f}  max={max(cvs):.2f}  median={st.median(cvs):.2f}")

print("\nrun-to-run stability (lower CV% = more stable):")
summ("group=32", g32_cvs)
summ("group=1", g1_cvs)

# Within-run spread: at group=1 there is a single sample, so min==max==median.
def collapsed(data):
    tot = same = 0
    for runs in data.values():
        for med, mn, mx in runs:
            tot += 1
            if mn == mx == med:
                same += 1
    return same, tot

s1, t1 = collapsed(g1); s32, t32 = collapsed(g32)
print(f"\nwithin-run min==max==median: g1 {s1}/{t1}   g32 {s32}/{t32}")
print("(g1 collapses to a single sample per run -> no within-run min/max spread)")
