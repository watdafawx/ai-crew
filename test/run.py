"""Headless checks of AI Crew on vanilla: python test/run.py [CASE [TICKS]] | --all [-j N]"""
import re

import factorio_paths
from factorio_paths import main

# ac-perf's profiler numbers (Lua can't read them) held to loose bounds: the crew's cost a tick on a big base (time a
# tick with crew less time without), one plan() and one hint. Measured ~0.2-0.4 ms, 3-9 ms, 1 ms (2.2-4.3 ms a tick
# before the chests were cached and arming throttled)
PERF_BOUNDS = {"tick": 1.5, "plan": 30, "hint": 20}
_headless = factorio_paths.headless


def headless(run, mods, case, *a, **k):
    status, text = _headless(run, mods, case, *a, **k)
    if case != "ac-perf" or status != "PASS":
        return status, text
    ms = {m[1]: float(m[2]) for m in re.finditer(r"^(.+?): Duration: ([\d.]+)ms", text, re.M)}
    got = {"tick": ms["crew, 3000 ticks"] / 3000 - ms["no crew, 1000 ticks"] / 1000,
           "plan": max(v / 10 for k, v in ms.items() if k.startswith("plan ")), "hint": ms["hint x5"] / 5}
    over = [f"{k} {got[k]:.2f} ms > {b} ms" for k, b in PERF_BOUNDS.items() if got[k] > b]
    text += "PERF " + ", ".join(f"{k} {v:.2f} ms" for k, v in got.items()) + "\n"
    return ("FAIL", text + "FAIL too slow: " + ", ".join(over) + "\n") if over else ("PASS", text)


factorio_paths.headless = headless
main(__file__, {"ac-test": 36010, "ac-place": 36010, "ac-asmfurnace": 36010, "ac-upgrade": 18010, "ac-arm": 18010,
                "ac-arm2": 36010, "ac-human": 8900, "ac-defend": 9100, "ac-spam": 7300, "ac-car": 12100,
                "ac-train": 9100, "ac-belt": 6100, "ac-hint": 18800, "ac-jet": 6100, "ac-roam": 36010,
                "ac-roam2": 36010, "ac-farpower": 18100, "ac-fight": 36010, "ac-line": 72010, "ac-power": 144010,
                "ac-boot": 36010, "ac-goal": 36010, "ac-path": 7510, "ac-bots": 3610, "ac-trip": 7300, "ac-backed": 3100,
                "ac-plates": 6100, "ac-fetch": 9100, "ac-base": 10100, "ac-short": 3100, "ac-quality": 2500, "ac-orders": 6100, "ac-perf": 4720,
                "ac-parity": 9000, "ac-shoot": 5000,
                "ac-checks": 36010, "ac-reuse": 36010})
