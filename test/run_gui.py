"""A real client through the fnative launcher (python run_gui.py [test], default ac-gui: the window, every tab
screenshotted; ac-follow: the crew follow the player through machines). Results in run/script-output/<test>-*."""
import json, os, shutil, subprocess, sys, time
from pathlib import Path
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
# fnative: FNATIVE_DIR, else an fnative/ beside a folder above this one
NATIVE = Path(os.environ.get("FNATIVE_DIR") or next((d / "fnative" for d in ROOT.parents if (d / "fnative").exists()), ROOT / "fnative"))
from factorio_paths import run_dir  # noqa: E402
RUN = run_dir(HERE / "run")
MODS, OUT = RUN / "gui-mods", RUN / "script-output"
shutil.rmtree(MODS, ignore_errors=True)
MODS.mkdir(parents=True)
shutil.copytree(HERE.parent, MODS / "ai-crew", ignore=shutil.ignore_patterns("test", ".git", "__pycache__"))
shutil.copytree(NATIVE / "mods" / "fnative-std", MODS / "fnative-std")
TEST = sys.argv[1] if len(sys.argv) > 1 else "ac-gui"
shutil.copytree(HERE / TEST, MODS / TEST)
names = ["base", "elevated-rails", "quality", "space-age", "fnative-std", "ai-crew", TEST]
(MODS / "mod-list.json").write_text(json.dumps({"mods": [{"name": n, "enabled": True} for n in names]}))
for f in OUT.glob(TEST + "*"):
    f.unlink()
save = RUN / (TEST + ".zip")
save.unlink(missing_ok=True)
launch = [str(NATIVE / "dist" / "factorio-native.exe"), "--config", str(RUN / "config.ini"), "--mod-directory", str(MODS)]
subprocess.run(launch + ["--create", str(save)], capture_output=True)
game = subprocess.Popen(launch + ["--load-game", str(save)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
start = time.time()
while time.time() - start < 300 and not (OUT / (TEST + "-done.txt")).exists() and game.poll() is None:
    time.sleep(1)
time.sleep(2)
game.kill()
res = OUT / (TEST + "-result.txt")
print(res.read_text() if res.exists() else "no result")
print("screenshots:", sorted(f.name for f in OUT.glob(TEST + "-*.png")))
log = (RUN / "factorio-current.log").read_text(errors="replace").splitlines()
print("errors:", "\n".join(l for l in log if "Error" in l or "non-recoverable" in l)[-2000:] or "none")
