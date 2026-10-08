"""AI Crew's window in a real client through the fnative launcher: screenshots in run/script-output/ac-gui-*.png."""
import json, os, shutil, subprocess, sys, time
from pathlib import Path
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
# fnative: FNATIVE_DIR, else beside this repo, else inside the dev repo
NATIVE = Path(os.environ.get("FNATIVE_DIR") or next((p for p in (ROOT.parent / "fnative", ROOT / "native") if p.exists()), ROOT / "native"))
from factorio_paths import run_dir  # noqa: E402
RUN = run_dir(HERE / "run")
MODS, OUT = RUN / "gui-mods", RUN / "script-output"
shutil.rmtree(MODS, ignore_errors=True)
MODS.mkdir(parents=True)
shutil.copytree(HERE.parent, MODS / "ai-crew", ignore=shutil.ignore_patterns("test", ".git", "__pycache__"))
shutil.copytree(NATIVE / "mods" / "fnative-std", MODS / "fnative-std")
shutil.copytree(HERE / "ac-gui", MODS / "ac-gui")
names = ["base", "elevated-rails", "quality", "space-age", "fnative-std", "ai-crew", "ac-gui"]
(MODS / "mod-list.json").write_text(json.dumps({"mods": [{"name": n, "enabled": True} for n in names]}))
for f in OUT.glob("ac-gui*"):
    f.unlink()
save = RUN / "ac-gui.zip"
save.unlink(missing_ok=True)
launch = [str(NATIVE / "dist" / "factorio-native.exe"), "--config", str(RUN / "config.ini"), "--mod-directory", str(MODS)]
subprocess.run(launch + ["--create", str(save)], capture_output=True)
game = subprocess.Popen(launch + ["--load-game", str(save)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
start = time.time()
while time.time() - start < 240 and not (OUT / "ac-gui-done.txt").exists() and game.poll() is None:
    time.sleep(1)
time.sleep(2)
game.kill()
res = OUT / "ac-gui-result.txt"
print(res.read_text() if res.exists() else "no result")
print("screenshots:", sorted(f.name for f in OUT.glob("ac-gui-*.png")))
log = (RUN / "factorio-current.log").read_text(errors="replace").splitlines()
print("errors:", "\n".join(l for l in log if "Error" in l or "non-recoverable" in l)[-2000:] or "none")
