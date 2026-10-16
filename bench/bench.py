#!/usr/bin/env python3
"""Helpers for scripts/bench.sh. Standard library only (macOS ships 3.9).

  bench.py memory PID OUT            footprint of a server and its WebKit processes
  bench.py trace-records SOCKET OUT  the server's recent stage records (`trace` command)
  bench.py summarize RAW OUT KEY=VALUE...
  bench.py check RESULTS BUDGETS
  bench.py budgets RESULTS FACTOR    budgets at FACTOR x the results, on stdout
"""

import ctypes
import json
import os
import socket
import statistics
import subprocess
import sys
import tempfile

TRACE_ORDER = ["cliStart", "accept", "sent", "parsed", "dispatch", "jsStart", "jsEnd",
               "visible", "painted", "reply", "received"]


def percentile(values, fraction):
    ordered = sorted(values)
    if not ordered:
        return None
    position = (len(ordered) - 1) * fraction
    low = int(position)
    high = min(low + 1, len(ordered) - 1)
    return ordered[low] + (ordered[high] - ordered[low]) * (position - low)


# Memory -------------------------------------------------------------------
#
# WebKit runs each WKWebView's content, networking and GPU work in XPC
# services (com.apple.WebKit.*) whose parent is launchd, so the process tree
# doesn't connect them to the server. macOS does record the "responsible"
# process for each one, which is the app that caused the launch. The private
# but stable libsystem call responsibility_get_pid_responsible_for_pid reads
# it (Activity Monitor groups processes the same way). We sum `footprint`'s
# phys_footprint (the number Activity Monitor shows as Memory) over the
# server and every process it is responsible for.

def responsible_for(pid):
    lib = ctypes.CDLL(None)
    lookup = lib.responsibility_get_pid_responsible_for_pid
    lookup.argtypes = [ctypes.c_int]
    lookup.restype = ctypes.c_int
    listing = subprocess.run(["ps", "-axo", "pid=,comm="], capture_output=True, text=True, check=True).stdout
    owned = []
    for line in listing.splitlines():
        fields = line.strip().split(None, 1)
        if len(fields) != 2:
            continue
        child = int(fields[0])
        if child != pid and lookup(child) == pid:
            owned.append(child)
    return owned


def footprints(pids):
    with tempfile.NamedTemporaryFile(suffix=".json") as handle:
        subprocess.run(["footprint", "-f", "bytes", "--noCategories", "-j", handle.name] + [str(p) for p in pids],
                       capture_output=True, check=True)
        report = json.load(open(handle.name))
    return [{"pid": p["pid"], "name": p["name"], "bytes": p["auxiliary"]["phys_footprint"]}
            for p in report.get("processes", [])]


def memory(pid, out):
    processes = footprints([pid] + responsible_for(pid))
    total = sum(p["bytes"] for p in processes)
    result = {"mb": round(total / 1048576, 1), "processes": processes}
    json.dump(result, open(out, "w"), indent=2)


# Trace --------------------------------------------------------------------

def trace_records(path, out):
    conn = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    conn.settimeout(5)
    conn.connect(path)
    conn.sendall(b'{"cmd":"trace"}\n')
    data = b""
    while True:
        chunk = conn.recv(65536)
        if not chunk:
            break
        data += chunk
    conn.close()
    event = json.loads(data.splitlines()[0])
    json.dump(event.get("stages", []), open(out, "w"), indent=2)


def trace_breakdown(lines_path, records_path):
    """Median ms since cliStart per stage. CLI lines give the stages that
    are in the reply; server records add the ones that land after it
    (`visible` on a new panel), placed relative to the line's `accept`."""
    if not os.path.exists(lines_path):
        return None
    lines = [json.loads(line) for line in open(lines_path) if line.startswith("{")]
    records = {}
    if os.path.exists(records_path):
        records = {r["id"]: r["stages"] for r in json.load(open(records_path))}
    samples = {}
    for index, line in enumerate(lines, start=1):
        stages = dict(line["stages"])
        server = records.get("bench-trace-%d" % index, {})
        if "accept" in stages and "accept" in server:
            for name, value in server.items():
                stages.setdefault(name, stages["accept"] + (value - server["accept"]) / 1e6)
        stages["total"] = line["total_ms"]
        for name, value in stages.items():
            samples.setdefault(name, []).append(value)
    order = TRACE_ORDER + ["total"]
    names = sorted(samples, key=lambda n: (order.index(n) if n in order else len(order), n))
    return {"runs": len(lines), "median_ms": {n: round(statistics.median(samples[n]), 3) for n in names}}


# Summary ------------------------------------------------------------------

def wall_times(result):
    if "measurements" in result:
        return [m["time_wall_clock"]["value"] for m in result["measurements"]]
    return result["times"]


def distribution(ms):
    return {"p50": round(percentile(ms, 0.5), 2), "p95": round(percentile(ms, 0.95), 2),
            "mean": round(statistics.mean(ms), 2), "min": round(min(ms), 2), "max": round(max(ms), 2),
            "runs": len(ms)}


def timing(path):
    result = json.load(open(path))["results"][0]
    return distribution([t * 1000 for t in wall_times(result)])


# metric: (records file, cmd, notes it must have or None, end stage). Each is
# the time from `accept` to the end stage in the server's own trace records.
SERVER_METRICS = {
    "server_show_new": ("server_show_new", "show", ("new", "fresh"), "reply"),
    "server_show_new_visible": ("server_show_new", "show", ("new", "fresh"), "visible"),
    "server_show_new_painted": ("server_show_new", "show", ("new", "fresh"), "painted"),
    "server_show_new_code": ("server_show_new_code", "show", ("new", "fresh"), "reply"),
    "server_show_replace": ("server_show_replace", "show", ("replace",), "reply"),
    "server_hide": ("server_hide", "hide", None, "reply"),
}


def server_metric(records, cmd, notes, end):
    chosen = [r for r in records if r.get("cmd") == cmd and (notes is None or r.get("note") in notes)]
    ms = [(r["stages"][end] - r["stages"]["accept"]) / 1e6 for r in chosen
          if "accept" in r["stages"] and end in r["stages"]]
    if not ms:
        return None
    metric = distribution(ms)
    if notes and "new" in notes:
        metric["pooled"] = sum(1 for r in chosen if r.get("note") == "new")
    return metric


def server_metrics(raw):
    metrics = {}
    for name, (source, cmd, notes, end) in SERVER_METRICS.items():
        path = os.path.join(raw, source + ".json")
        if os.path.exists(path):
            metric = server_metric(json.load(open(path)), cmd, notes, end)
            if metric:
                metrics[name] = metric
    return metrics


def summarize(raw, out, meta_pairs):
    metrics = {}
    for name in sorted(os.listdir(raw)):
        path = os.path.join(raw, name)
        if name.startswith("time_") and name.endswith(".json"):
            metrics[name[5:-5]] = timing(path)
        elif name.startswith("mem_") and name.endswith(".json"):
            metrics[name[:-5]] = json.load(open(path))
    metrics.update(server_metrics(raw))
    meta = dict(pair.split("=", 1) for pair in meta_pairs)
    trace = trace_breakdown(os.path.join(raw, "trace_lines.ndjson"), os.path.join(raw, "trace_records.json"))
    results = {"meta": meta, "metrics": metrics, "trace_show_new": trace}
    json.dump(results, open(out, "w"), indent=2)
    print_table(results)


def print_table(results):
    print("%-24s %10s %10s %8s" % ("metric", "p50 ms", "p95 ms", "MB"))
    for name, metric in results["metrics"].items():
        if "mb" in metric:
            print("%-24s %10s %10s %8.1f" % (name, "", "", metric["mb"]))
        else:
            print("%-24s %10.2f %10.2f %8s" % (name, metric["p50"], metric["p95"], ""))
    trace = results.get("trace_show_new")
    if trace:
        print("\nshow_new stages, median ms since cliStart (%d runs):" % trace["runs"])
        print("  " + "  ".join("%s %.2f" % item for item in trace["median_ms"].items()))


# Budgets ------------------------------------------------------------------

def check(results_path, budgets_path):
    metrics = json.load(open(results_path))["metrics"]
    budgets = json.load(open(budgets_path))
    regressions = []
    for name, budget in budgets.items():
        if name.startswith("_") or name not in metrics:
            continue
        for key, limit in budget.items():
            value = metrics[name].get(key)
            if value is not None and value > limit:
                regressions.append("%s %s: %s > budget %s" % (name, key, value, limit))
    for line in regressions:
        print("regression: " + line, file=sys.stderr)
    if not regressions:
        print("all metrics within budget")
    return 1 if regressions else 0


def budgets(results_path, factor):
    metrics = json.load(open(results_path))["metrics"]
    keys = ("p50", "p95", "mb")
    meta = json.load(open(results_path)).get("meta", {})
    out = {"_note": "Budgets at %sx the results of %s (git %s)." % (factor, meta.get("date"), meta.get("git"))}
    for name, metric in metrics.items():
        out[name] = {k: round(metric[k] * factor, 1) for k in keys if k in metric}
    print(json.dumps(out, indent=2))


def main(argv):
    command, args = argv[1], argv[2:]
    if command == "memory":
        memory(int(args[0]), args[1])
    elif command == "trace-records":
        trace_records(args[0], args[1])
    elif command == "summarize":
        summarize(args[0], args[1], args[2:])
    elif command == "check":
        return check(args[0], args[1])
    elif command == "budgets":
        budgets(args[0], float(args[1]))
    else:
        print(__doc__, file=sys.stderr)
        return 64
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
