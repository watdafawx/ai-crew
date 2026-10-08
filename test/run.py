"""Headless check of AI Crew on vanilla."""
import json, shutil, subprocess, sys
from pathlib import Path
HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
sys.path.insert(0, str(ROOT))
from factorio_paths import PATHS  # noqa: E402
from factorio_paths import run_dir  # noqa: E402
RUN = run_dir(Path(__file__).resolve().parent / "run")
MODS = RUN / "ac-mods"
shutil.rmtree(MODS, ignore_errors=True)
MODS.mkdir(parents=True)
shutil.copytree(HERE.parent, MODS / "ai-crew", ignore=shutil.ignore_patterns("test", ".git", "__pycache__"))
TEST = sys.argv[1] if len(sys.argv) > 1 else "ac-test"
TICKS = int(sys.argv[2]) if len(sys.argv) > 2 else 36010
shutil.copytree(HERE / TEST, MODS / TEST)
names = ["base", "elevated-rails", "quality", "space-age", "ai-crew", TEST]
(MODS / "mod-list.json").write_text(json.dumps({"mods": [{"name": n, "enabled": True} for n in names]}))
out = RUN / "script-output" / (TEST + ".txt")
out.unlink(missing_ok=True)
save = RUN / "ac-test.zip"
save.unlink(missing_ok=True)
common = [str(PATHS["factorio_exe"]), "--config", str(RUN / "config.ini"), "--mod-directory", str(MODS)]
for args in (["--create", str(save)], ["--benchmark", str(save), "--benchmark-ticks", str(TICKS), "--disable-audio"]):
    p = subprocess.run(common + args, capture_output=True, text=True, encoding="utf-8", errors="replace")
    if p.returncode or "non-recoverable" in p.stdout or "Error" in p.stdout:
        print(p.stdout[-3000:]); sys.exit(1)
print(out.read_text() if out.exists() else "no result")
