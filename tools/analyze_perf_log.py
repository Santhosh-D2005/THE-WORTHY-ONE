"""Summarise a PerfProbe log (user://perf_log.txt) pulled from a device.

    adb shell run-as com.theworthyone.game cat files/perf_log.txt > perf_log.txt
    python tools/analyze_perf_log.py perf_log.txt [launch_wall_seconds]

`launch_wall_seconds` is the phone clock (`adb shell date +%s.%N`) read just before the launch; with it the
script prints launch -> first rendered frame. Frame lines are  F,<engine_ms>,<delta_ms>,<STATE>,<draw calls>,<primitives>.
Frame deltas include any wait for vsync, so a 60 Hz panel cannot report better than ~16.7 ms.
"""
import statistics
import sys


def percentile(values, p):
    values = sorted(values)
    if not values:
        return float("nan")
    k = (len(values) - 1) * p / 100.0
    lo, hi = int(k), min(int(k) + 1, len(values) - 1)
    return values[lo] + (values[hi] - values[lo]) * (k - lo)


def summarise(name, deltas):
    if len(deltas) < 5:
        print(f"  {name:<22} (only {len(deltas)} frames)")
        return
    mean = statistics.fmean(deltas)
    print(f"  {name:<22} frames={len(deltas):5d}  avg FPS={1000.0 / mean:5.1f}  median={statistics.median(deltas):5.1f} ms"
          f"  p95={percentile(deltas, 95):5.1f} ms  p99={percentile(deltas, 99):5.1f} ms  worst={max(deltas):6.1f} ms")


def main():
    path = sys.argv[1]
    launch_wall = float(sys.argv[2]) if len(sys.argv) > 2 else None
    marks, timings, frames = [], [], []
    header = ""
    for line in open(path, encoding="utf-8", errors="replace"):
        line = line.strip()
        if line.startswith("#"):
            header = line
        elif line.startswith("M,"):
            parts = line.split(",")
            marks.append((parts[1], int(parts[2].split("=")[1]), float(parts[3].split("=")[1])))
        elif line.startswith("T,"):
            parts = line.split(",")
            timings.append((parts[1], float(parts[2].split("=")[1])))
        elif line.startswith("F,"):
            p = line.split(",")
            frames.append((int(p[1]), float(p[2]), p[3], int(p[4]), int(p[5])))
    print(header)
    print("\nStartup marks (engine ms since process start):")
    for label, ms, wall in marks:
        extra = f"   launch+{wall - launch_wall:6.2f} s" if launch_wall else ""
        print(f"  {label:<22} {ms:7d} ms{extra}")
    if timings:
        print("\nBlock timings:")
        for label, ms in timings:
            print(f"  {label:<22} {ms:8.1f} ms")
    # Skip the very first frames (loading hitches) and any pause gap > 500 ms for steady-state numbers.
    # Frames before the first READY are the load / entrance sequence (shader + asset warm-up); they are
    # reported separately so they do not pollute the gameplay states (the entrance is state EXTRACTING too).
    first_ready_ms = next((ms for label, ms, _ in marks if label == "state_READY"), 0)
    startup = [f for f in frames if f[0] < first_ready_ms]
    steady = [f for f in frames if f[0] >= first_ready_ms and f[1] < 500.0]
    print(f"\nFrames logged: {len(frames)} (before first READY: {len(startup)}; steady-state: {len(steady)})")
    summarise("STARTUP (pre-READY)", [f[1] for f in startup])
    summarise("ALL", [f[1] for f in steady])
    for state in ("READY", "PLAYING", "EXTRACTING", "FAILED", "PAUSED"):
        summarise(state, [f[1] for f in steady if f[2] == state])
    draw = [f[3] for f in frames if f[3] > 0]
    prim = [f[4] for f in frames if f[4] > 0]
    if draw:
        print(f"\nDraw calls per frame: median {statistics.median(draw):.0f}, max {max(draw)};"
              f" primitives per frame: median {statistics.median(prim):.0f}")
    hitches = [f for f in frames if f[1] >= 100.0]
    print(f"Frames >= 100 ms: {len(hitches)}")


main()
