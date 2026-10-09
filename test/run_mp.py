"""AI Crew in multiplayer: fse's harness (a headless server and one client on this machine, both with fse) with the
ac-mp test mod. Passes when both peers show the same crew and AI state at the same ticks, an AI answer (here an
error: the key is fake) reached them, and neither desynced. Needs fse built (FSE_DIR, else ../../fse); opens a game
window, so not while you play."""
import os, subprocess, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
MOD = HERE.parent
FSE = Path(os.environ.get("FSE_DIR") or next((d / "fse" for d in MOD.parents if (d / "fse").exists()), MOD / "fse"))
sys.exit(subprocess.run([sys.executable, str(FSE / "test" / "run_mp.py"), "--mod", str(MOD), "--mod", str(HERE / "ac-mp"),
                         "--expect", r"crew 2 ai groq .*401", "--no-kick"]).returncode)
