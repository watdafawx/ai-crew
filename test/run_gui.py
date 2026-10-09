"""A real client through the fse launcher (python run_gui.py [test], default ac-gui: the window, every tab
screenshotted; ac-follow: the crew follow the player through machines; ac-info: the crew's rows in the game's own
info panel, grabbed from the game window). Results in run/script-output/<test>-*."""
import json, os, shutil, subprocess, sys, time
from pathlib import Path
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
# fse: FSE_DIR, else an fse/ beside a folder above this one
NATIVE = Path(os.environ.get("FSE_DIR") or next((d / "fse" for d in ROOT.parents if (d / "fse").exists()), ROOT / "fse"))
from factorio_paths import run_dir  # noqa: E402
RUN = run_dir(HERE / "run")
MODS, OUT = RUN / "gui-mods", RUN / "script-output"
shutil.rmtree(MODS, ignore_errors=True)
MODS.mkdir(parents=True)
shutil.copytree(HERE.parent, MODS / "ai-crew", ignore=shutil.ignore_patterns("test", ".git", "__pycache__"))
shutil.copytree(NATIVE / "mods" / "fse-std", MODS / "fse-std")
TEST = sys.argv[1] if len(sys.argv) > 1 else "ac-gui"
shutil.copytree(HERE / TEST, MODS / TEST)
names = ["base", "elevated-rails", "quality", "space-age", "fse-std", "ai-crew", TEST]
(MODS / "mod-list.json").write_text(json.dumps({"mods": [{"name": n, "enabled": True} for n in names]}))
for f in OUT.glob(TEST + "*"):
    f.unlink()
save = RUN / (TEST + ".zip")
save.unlink(missing_ok=True)
launch = [str(NATIVE / "dist" / "fse-launcher.exe"), "--config", str(RUN / "config.ini"), "--mod-directory", str(MODS)]
subprocess.run(launch + ["--create", str(save)], capture_output=True)
game = subprocess.Popen(launch + ["--load-game", str(save)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
start = time.time()


def window_shot(path):
    """the game window only, drawn by itself (PrintWindow, full content: works behind other windows and never
    captures anything else on the screen)"""
    import ctypes
    from ctypes import wintypes
    from PIL import Image
    u, g = ctypes.windll.user32, ctypes.windll.gdi32
    found = []
    proc = ctypes.WINFUNCTYPE(ctypes.c_bool, wintypes.HWND, wintypes.LPARAM)

    def each(h, _):
        buf = ctypes.create_unicode_buffer(256)
        u.GetWindowTextW(h, buf, 256)
        if buf.value.startswith("Factorio") and u.IsWindowVisible(h):
            found.append(h)
        return True
    u.EnumWindows(proc(each), 0)
    if not found:
        print("no game window to grab")
        return
    h = found[0]
    r = wintypes.RECT()
    u.GetClientRect(h, ctypes.byref(r))
    w, ht = r.right, r.bottom
    hdc = u.GetDC(h)
    mem = g.CreateCompatibleDC(hdc)
    bmp = g.CreateCompatibleBitmap(hdc, w, ht)
    g.SelectObject(mem, bmp)
    u.PrintWindow(h, mem, 3)  # (PW_CLIENTONLY | PW_RENDERFULLCONTENT)
    bits = ctypes.create_string_buffer(w * ht * 4)
    hdr = (ctypes.c_uint32 * 10)(40, w, -ht, 1 | (32 << 16), 0, 0, 0, 0, 0, 0)
    g.GetDIBits(mem, bmp, 0, ht, bits, hdr, 0)
    Image.frombuffer("RGBA", (w, ht), bits, "raw", "BGRA", 0, 1).convert("RGB").save(path)
    g.DeleteObject(bmp)
    g.DeleteDC(mem)
    u.ReleaseDC(h, hdc)


grabbed = False
while time.time() - start < 300 and not (OUT / (TEST + "-done.txt")).exists() and game.poll() is None:
    # a test can ask for a grab of the game window as drawn (what the game draws itself, like the info panel under the
    # minimap, isn't in game.take_screenshot): it writes <test>-grab.txt and holds still a few seconds
    if not grabbed and (OUT / (TEST + "-grab.txt")).exists():
        time.sleep(0.5)
        window_shot(OUT / (TEST + "-screen.png"))
        grabbed = True
    time.sleep(0.25)
time.sleep(2)
game.kill()
res = OUT / (TEST + "-result.txt")
print(res.read_text() if res.exists() else "no result")
print("screenshots:", sorted(f.name for f in OUT.glob(TEST + "-*.png")))
log = (RUN / "factorio-current.log").read_text(errors="replace").splitlines()
print("errors:", "\n".join(l for l in log if "Error" in l or "non-recoverable" in l)[-2000:] or "none")
