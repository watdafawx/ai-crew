"""The crew cards in a real client, single player through the fse launcher (python test/run_cards.py [--scale 2]):
test/ac-cards drives the game; with the loader's web plugin the cards are the web page (cards.lua, web/cards.html).
This runner answers the test's wants (ac-cards-want-<n>.txt): "shot <name>" -> run/script-output/ac-cards-<name>.png,
the game window and the page over it as the screen shows them (PrintWindow of each, the page cut by its region: never
a grab of the screen); "click <member>" -> that card clicked in the page (its DOM click: the page's own handler sends
the message); "hover <member>" -> the mouse onto that card (its mouseenter); "cmd <act>" -> the corner card's
order button clicked. --scale N: the game's GUI at N x 100 % (a config of the run's own). Never while your Factorio is open."""
import json, os, re, shutil, subprocess, sys, time, urllib.error, urllib.request
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
NATIVE = Path(os.environ.get("FSE_DIR") or next((d / "fse" for d in ROOT.parents if (d / "fse").exists()), ROOT / "fse"))
sys.path.insert(0, str(NATIVE / "test"))
from factorio_paths import run_dir, watch_game  # noqa: E402
from gui_input import grab  # noqa: E402

running = subprocess.run(["powershell", "-NoProfile", "-Command",
                          "Get-CimInstance Win32_Process -Filter \"name='factorio.exe'\" | ForEach-Object { $_.CommandLine }"],
                         capture_output=True, text=True).stdout.splitlines()
if any(l.strip() and not any(f in l for f in ("--benchmark", "--create", "--start-server", "--dump-data"))
       and "\\run\\" not in l.lower() and "/run/" not in l.lower() for l in running):
    raise SystemExit("Factorio is running with a window (your game?): close it first, this test opens one")

SCALE = sys.argv[sys.argv.index("--scale") + 1] if "--scale" in sys.argv else None
TEST, KEY, TOKEN = "ac-cards", "ai-crew/aic_cards", "ai-crew-cards-token"
RUN = run_dir(HERE / "run")
MODS, OUT = RUN / "cards-mods", RUN / "script-output"
shutil.rmtree(MODS, ignore_errors=True)
MODS.mkdir(parents=True)
OUT.mkdir(parents=True, exist_ok=True)
shutil.copytree(HERE.parent, MODS / "ai-crew", ignore=shutil.ignore_patterns("test", ".git", "__pycache__"))
shutil.copytree(NATIVE / "mods" / "fse-std", MODS / "fse-std")
shutil.copytree(HERE / TEST, MODS / TEST)
names = ["base", "elevated-rails", "quality", "space-age", "fse-std", "ai-crew", TEST]
(MODS / "mod-list.json").write_text(json.dumps({"mods": [{"name": n, "enabled": True} for n in names]}))
for f in OUT.glob(TEST + "*"):
    f.unlink()
# (the GUI scale in a config of the run's own)
base = (RUN / "config.ini").read_text(encoding="utf-8") if (RUN / "config.ini").exists() else ""
lines = [l for l in base.splitlines() if not l.startswith(("ui-scale-mode=", "custom-ui-scale="))]
if SCALE:
    if "[interface]" in lines:
        i = lines.index("[interface]") + 1
        lines[i:i] = ["ui-scale-mode=manual-pixels", f"custom-ui-scale={SCALE}"]
    else:
        lines += ["[interface]", "ui-scale-mode=manual-pixels", f"custom-ui-scale={SCALE}"]
CONFIG = RUN / "config-cards.ini"
CONFIG.write_text("\n".join(lines) + "\n", encoding="utf-8")
env = dict(os.environ, FSE_WEB_TOKEN=TOKEN)
launch = [str(NATIVE / "dist" / "fse-launcher.exe"), "--config", str(CONFIG), "--mod-directory", str(MODS)]
save = RUN / (TEST + ".zip")
save.unlink(missing_ok=True)
subprocess.run(launch + ["--create", str(save)], capture_output=True, env=env)
game = watch_game(launch + ["--load-game", str(save)], env=env)

PORT = None


def api(path, body=None, timeout=5):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(f"http://127.0.0.1:{PORT}{path}", data=data, method="POST" if data else "GET",
                                 headers={"Authorization": f"Bearer {TOKEN}"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return json.loads(r.read())
    except urllib.error.HTTPError as e:
        return json.loads(e.read() or b"{}")


def find_port():
    global PORT
    for p in range(8790, 8800):
        PORT = p
        try:
            if api("/api/status", timeout=1).get("core"):
                return p
        except OSError:
            pass
    PORT = None


def status():
    try:
        return api("/api/native/web/shell_status", {}).get("result") or {}
    except OSError:
        return {}


def composite(path):
    st = status()
    s = (st.get("shells") or {}).get(KEY)
    gh = st.get("game")
    g_path, s_path = OUT / "ac-cards-game.png", OUT / "ac-cards-page.png"
    if not gh or not grab(gh, g_path):
        print("  no game window to grab")
        return
    g = Image.open(g_path).convert("RGB")
    if s and s.get("visible") and grab(s["hwnd"], s_path):
        w = Image.open(s_path).convert("RGB")
        mask = Image.new("L", w.size, 0)
        for l, t, r, b in s.get("region") or [(0, 0) + w.size]:
            mask.paste(255, (l, t, r, b))
        o = st["game_origin"]
        g.paste(w, (s["screen"][0] - o[0], s["screen"][1] - o[1]), mask)
    g.save(path)
    print("  screenshot", path.name, "(page shown)" if s and s.get("visible") else "(no page)", flush=True)


start, done_wants = time.time(), set()
while time.time() - start < 300 and not (OUT / (TEST + "-done.txt")).exists() and game.poll() is None:
    for f in sorted(OUT.glob(TEST + "-want-*.txt"), key=lambda f: int(re.findall(r"\d+", f.name)[-1])):
        if f.name in done_wants:
            continue
        done_wants.add(f.name)
        what, _, arg = f.read_text().strip().partition(" ")
        if PORT is None:
            find_port()
        time.sleep(0.4)  # (the page draws what it was sent)
        if what == "shot":
            composite(OUT / f"{TEST}-{arg}{'-x' + SCALE if SCALE else ''}.png")
        elif what == "hover":  # (the mouse onto a member's card: its mouseenter)
            r = api("/api/native/web/shell_eval", {"owner": "ai-crew", "name": "aic_cards", "js":
                    f"document.querySelector('.card[data-name=\"{arg}\"]').dispatchEvent(new MouseEvent('mouseenter'))"})
            print("  hovered", arg, "->", r.get("ok", r), flush=True)
        elif what == "cmd":  # (an order for everyone: the corner card's button clicked)
            r = api("/api/native/web/shell_eval", {"owner": "ai-crew", "name": "aic_cards",
                                                   "js": f"document.querySelector('.cmd[data-act=\"{arg}\"]').click()"})
            print("  order", arg, "->", r.get("ok", r), flush=True)
        elif what == "click":
            r = api("/api/native/web/shell_eval", {"owner": "ai-crew", "name": "aic_cards",
                                                   "js": f"document.querySelector('.card[data-name=\"{arg}\"]').click()"})
            print("  clicked", arg, "->", r.get("ok", r), flush=True)
    time.sleep(0.2)
time.sleep(1)
game.kill()
res = OUT / (TEST + "-result.txt")
print(res.read_text() if res.exists() else "no result")
log = (RUN / "factorio-current.log").read_text(errors="replace").splitlines()
print("errors:", "\n".join(l for l in log if "Error" in l or "non-recoverable" in l)[-2000:] or "none")
sys.exit(0 if res.exists() and "ALL PASS" in res.read_text() else 1)
