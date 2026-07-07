#!/usr/bin/env python3
"""Build the interactive benchmark website's data file.

Loads every results/<instance>/*.json (each file = one commit's recorded run)
straight into memory -- no intermediate CSV -- enriches each commit with its git
metadata (subject, author, committer date, GitHub URL), and writes a single
`site/data.js` blob that `site/index.html` renders with Plotly.

The site (index.html + vendored plotly.min.js + data.js) is fully static: open
site/index.html directly, or serve the dir. Re-run this after new benchmark
results land. Everything else -- the interactive charts, zoom, hover tooltips,
per-commit GitHub links -- lives in index.html.

Usage:
  scripts/build_site.py                     # default instance, ../tantivy repo
  scripts/build_site.py --instance COMP-... --repo /path/to/tantivy
"""
import argparse
import glob
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PROJ = os.path.dirname(HERE)
DEFAULT_REPO = os.path.normpath(os.path.join(PROJ, "..", "tantivy"))

# #2759 quadratic regression window (committer dates): [start, end), where
# 2e16243f9 on 2026-04-21 is the fixed recovery point.
BUG_WINDOW = ["2026-01-06", "2026-04-21"]

CARDINALITIES = ["full", "dense", "sparse", "multivalue"]
CATEGORY_ORDER = ["average", "stats", "percentiles", "cardinality",
                  "histogram", "range", "terms", "composite", "filter", "other"]
METRICS = ["median_ns", "avg_memory"]

SEP = "\x1f"  # unit separator: safe delimiter for git --format fields


def category(name):
    """Primary aggregation of a bench, from its name prefix."""
    if name.startswith("average"):
        return "average"
    if name.startswith(("stats_", "extendedstats")):
        return "stats"
    if name.startswith("percentiles"):
        return "percentiles"
    if name.startswith("cardinality"):
        return "cardinality"
    if name.startswith("histogram"):
        return "histogram"
    if name.startswith("composite"):
        return "composite"
    if name.startswith(("range", "avg_and_range")):
        return "range"
    if name.startswith("filter"):
        return "filter"
    if name.startswith("terms"):
        return "terms"
    return "other"


def repo_web_url(repo):
    """Canonical GitHub base URL: prefer upstream (quickwit-oss) over a fork."""
    for remote in ("upstream", "origin"):
        r = subprocess.run(["git", "-C", repo, "remote", "get-url", remote],
                           capture_output=True, text=True)
        if r.returncode == 0:
            m = re.search(r"github\.com[:/](.+?)(?:\.git)?$", r.stdout.strip())
            if m:
                return "https://github.com/" + m.group(1)
    return "https://github.com/quickwit-oss/tantivy"


def commit_meta(repo, commit):
    """(short, full, date, author, subject) for a commit via git, or None."""
    fmt = SEP.join(["%h", "%H", "%cd", "%an", "%s"])
    r = subprocess.run(
        ["git", "-C", repo, "show", "-s", f"--format={fmt}", "--date=short", commit],
        capture_output=True, text=True)
    if r.returncode != 0:
        return None
    parts = r.stdout.rstrip("\n").split(SEP)
    return parts if len(parts) == 5 else None


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--results", default=os.path.join(PROJ, "results"))
    ap.add_argument("--instance", default=None,
                    help="results/<instance> dir (default: the only/first one)")
    ap.add_argument("--repo", default=DEFAULT_REPO, help="tantivy git repo for commit metadata")
    ap.add_argument("--out", default=os.path.join(PROJ, "site", "data.js"))
    args = ap.parse_args()

    inst = args.instance
    if inst is None:
        dirs = sorted(d for d in glob.glob(os.path.join(args.results, "*"))
                      if os.path.isdir(d))
        if not dirs:
            sys.exit(f"no instance dirs under {args.results}")
        inst = os.path.basename(dirs[0])
        if len(dirs) > 1:
            print(f"note: {len(dirs)} instances; using {inst} (override with --instance)")
    results_dir = os.path.join(args.results, inst)
    base_url = repo_web_url(args.repo)

    files = sorted(glob.glob(os.path.join(results_dir, "*.json")))
    if not files:
        sys.exit(f"no result JSONs in {results_dir}")

    # runs[short] = {meta..., benchmarks}; benches = every bench name seen.
    runs, benches = {}, set()
    for fn in files:
        d = json.load(open(fn))
        short = d["short_hash"]
        m = commit_meta(args.repo, d["commit"])
        if m is None:
            print(f"warn: git can't resolve {short}; using run date")
            m = [short, d["commit"], d.get("date", ""), "", "(unknown)"]
        runs[short] = dict(
            short=m[0], full=m[1], date=m[2], author=m[3], subject=m[4],
            url=f"{base_url}/commit/{m[1]}", benchmarks=d["benchmarks"])
        for card in d["benchmarks"].values():
            benches.update(card.keys())

    # One commit per committer-day -> date orders them; tie-break on short hash.
    order = sorted(runs.values(), key=lambda r: (r["date"], r["short"]))
    commits = [{k: r[k] for k in ("short", "full", "date", "author", "subject", "url")}
               for r in order]
    benches = sorted(benches)

    # series[card][bench][metric] = list aligned to `commits`, null where absent.
    series = {}
    for card in CARDINALITIES:
        series[card] = {}
        for b in benches:
            per_metric = {m: [] for m in METRICS}
            for r in order:
                entry = r["benchmarks"].get(card, {}).get(b)
                for m in METRICS:
                    per_metric[m].append(None if entry is None else entry.get(m))
            series[card][b] = per_metric

    data = dict(
        instance=inst,
        repo_url=base_url,
        bug_window=BUG_WINDOW,
        cardinalities=CARDINALITIES,
        category_order=CATEGORY_ORDER,
        commits=commits,
        benches=benches,
        categories={b: category(b) for b in benches},
        series=series,
    )

    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    with open(args.out, "w") as f:
        f.write("// Generated by scripts/build_site.py -- do not edit by hand.\n")
        f.write("window.BENCH_DATA = ")
        json.dump(data, f, ensure_ascii=False, separators=(",", ":"))
        f.write(";\n")
    print(f"wrote {args.out}: {len(commits)} commits, {len(benches)} benches, "
          f"repo {base_url}")


if __name__ == "__main__":
    main()
