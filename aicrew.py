"""AI Crew's in-game side (fnative `py` plugin): chat answers from a free LLM, and text to speech.

Lua calls (strings in, JSON strings out):
  aicrew:ask    {message, to: [names], llm: {provider, key, model}, context}  -> {replies: [{who, text}], jobs: [...]}
  aicrew:ada    {text, llm}                                                 -> {text}  (ADA's line, reworded)
  aicrew:banter {llm, context}       -> {replies}  (chatter: idle while the player is away, or context.event reacted to)
  aicrew:check  {llm}                       -> {provider, key (masked), source, ok, seconds, model, error, tts}
  aicrew:speak  {text, voice}   queued and spoken on a thread; returns at once

Every provider speaks the OpenAI chat API. Keys are free to get (see NO_KEY); Ollama needs none.
Voices: edge-tts when installed (pip install edge-tts), else Windows' own SAPI voices.
"""
import json
import os
import queue
import re
import subprocess
import tempfile
import threading
import time
import urllib.error
import urllib.request

# name: (base url, default model or None to pick from /models, env var with the key)
PROVIDERS = {
    "pollinations": ("https://gen.pollinations.ai/v1", "openai", "POLLINATIONS_API_KEY"),  # free key at enter.pollinations.ai
    "openrouter": ("https://openrouter.ai/api/v1", None, "OPENROUTER_API_KEY"),
    "groq": ("https://api.groq.com/openai/v1", "llama-3.3-70b-versatile", "GROQ_API_KEY"),
    "gemini": ("https://generativelanguage.googleapis.com/v1beta/openai", "gemini-2.5-flash", "GEMINI_API_KEY"),
    "cerebras": ("https://api.cerebras.ai/v1", None, "CEREBRAS_API_KEY"),
    "mistral": ("https://api.mistral.ai/v1", "mistral-small-latest", "MISTRAL_API_KEY"),
    "ollama": ("http://127.0.0.1:11434/v1", None, None),
}
KEY_PREFIXES = (("sk-or-", "openrouter"), ("sk_", "pollinations"), ("gsk_", "groq"), ("AIza", "gemini"), ("csk-", "cerebras"))
# OpenRouter's free list changes every few weeks: prefer these when present, else the first free one
PREFERRED = ("gemma-4-31b", "nemotron-3-super", "llama-3.3-70b", "llama-4", "qwen3", "deepseek", "gpt-oss", "gemma", "llama")
PERSONAS = {
    "Rook": "gruff, dry humour, an old construction hand",
    "Mara": "upbeat and chatty, loves a tidy factory",
    "Juno": "calm, precise, a little nerdy about ratios",
    "Bolt": "eager, fast talker, always wants the next task",
    "Pip": "small, cheerful, easily impressed by big machines",
    "Sable": "laconic and cool, quietly competent",
    "Tess": "precise and dry, keeps lists of everything",
    "Orin": "gruff old hand, secretly fond of the biters",
}
MANNERS = {  # (control.lua's TRAITS: names not in PERSONAS get one of these)
    "gruff": "gruff, dry humour", "upbeat": "upbeat and chatty", "precise": "calm, precise, a little nerdy",
    "eager": "eager, fast talker", "cheerful": "small, cheerful, easily impressed", "laconic": "laconic and cool",
}
_said = []  # the crew's last lines, so the model doesn't repeat itself


def persona(c):
    return PERSONAS.get(c.get("name"), MANNERS.get(c.get("manner"), "a friendly helper"))


def _note_said(replies):
    _said.extend(r.get("text", "") for r in replies if isinstance(r, dict))
    del _said[:-30]
ADA = ("You are ADA, the calm, slightly dry corporate AI assistant of a factory-building pioneer (in the style of "
       "Satisfactory's ADA). Reword the announcement as ADA would say it: one or two short sentences, no emoji, keep "
       "the facts.")
JOBS_HELP = """Jobs the crew can do (use internal item names such as iron-plate, iron-gear-wheel, stone, wood):
  build        place every ghost (blueprint) near the player that items are available for
  deconstruct  remove everything marked for deconstruction near the player
  upgrade      carry out the upgrade planner's marks near the player (recipes and contents kept)
  mine         gather a raw resource by hand: item, count
  craft        hand-craft: item, count
  get          obtain an item any way (chests, mining or crafting): item, count
  deliver      bring what they carry to the player
  goal         the crew's long-term aim, worked on whenever they're free: item, count to have; "line": true to have a production
               line planned and built for it (bpgen), "rate": per minute
  attack       destroy the enemy nests (spawners, worms) near the player
  roam         wander round the player on their own, dealing with what they find (nests, dark machines)
  remember     keep a note where the player stands (what a place is for, a wish): "text"; "keep_out": true to keep out
               of there (no taking from its chests, no borrowing its machines). Their notes are in the state as "notes"
  follow / stay / stop"""

_models = {}  # provider -> picked model
_history = []  # recent turns, shared by the crew


NO_KEY = ("no API key. Get a free one and paste it in Settings > Mod settings > Per player > API key: "
          "openrouter.ai/keys, console.groq.com/keys, aistudio.google.com/apikey or cloud.cerebras.ai "
          "(or pick ollama if you run one locally)")


def pick_provider(llm):
    """(name, base url, key, model) from the in-game settings, else environment keys"""
    name = (llm.get("provider") or "auto").lower()
    key = (llm.get("key") or "").strip()
    if name == "auto":
        name = next((p for prefix, p in KEY_PREFIXES if key.startswith(prefix)), None)
        if not name and not key:
            name = next((p for p, (_, _, env) in PROVIDERS.items() if env and os.environ.get(env)), None)
        name = name or ("openrouter" if key else None)
        if not name:
            raise ValueError(NO_KEY)
    if name not in PROVIDERS:
        raise ValueError(f"unknown provider {name}")
    base, model, env = PROVIDERS[name]
    key = key or (os.environ.get(env, "") if env else "")
    if env and not key:
        raise ValueError(f"{name}: " + NO_KEY)
    return name, base, key, (llm.get("model") or "").strip() or model


def _request(url, key, body=None, timeout=45):
    headers = {"Content-Type": "application/json", "User-Agent": "ai-crew/0.1"}
    if key:
        headers["Authorization"] = "Bearer " + key
    if "openrouter.ai" in url:
        headers["X-Title"] = "Factorio AI Crew"
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, headers=headers, method="POST" if data else "GET")
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode("utf-8"))


def choose_model(name, ids, skip=()):
    """a model from a provider's /models list (on OpenRouter only the :free ones)"""
    ids = [i for i in ids if i not in skip and (name != "openrouter" or i.endswith(":free"))]
    for want in PREFERRED:
        for i in ids:
            if want in i:
                return i
    return ids[0] if ids else None


_failed = set()  # auto-picked models that errored this session


def _model(name, base, key):
    if name not in _models:
        ids = [m["id"] for m in _request(base + "/models", key, timeout=20).get("data", [])]
        _models[name] = choose_model(name, ids, _failed)
        if not _models[name]:
            raise RuntimeError(f"{name} lists no usable model")
    return _models[name]


def chat(llm, messages, max_tokens=500):
    """the reply text. A model picked automatically that fails (free models get rate-limited or retired) is
    swapped for the next one, up to three tries."""
    name, base, key, model = pick_provider(llm)
    for _ in range(3):
        use = model or _model(name, base, key)
        try:
            out = _request(base + "/chat/completions", key,
                           {"model": use, "messages": messages, "temperature": 0.7, "max_tokens": max_tokens})
            return out["choices"][0]["message"].get("content") or ""
        except urllib.error.HTTPError as e:
            body = e.read().decode("utf-8", "replace")
            try:  # (most APIs: {"error": {"message": ...}})
                err = json.loads(body).get("error")
                body = err.get("message", body) if isinstance(err, dict) else (err or body)
            except (ValueError, AttributeError):
                pass
            detail = f"{name} {use}: HTTP {e.code} {str(body)[:200]}"
            if model or e.code in (401, 402, 403):
                raise RuntimeError(detail) from None
            print(f"[aicrew] {detail}; trying another model")
            _failed.add(use)
            _models.pop(name, None)
    raise RuntimeError(detail)


def extract_json(text):
    """the first JSON object in a model's reply (models wrap it in prose or ``` fences)"""
    text = re.sub(r"<think>.*?</think>", "", text, flags=re.S)
    start = text.find("{")
    first = None
    while start != -1:
        try:
            obj = json.JSONDecoder().raw_decode(text[start:])[0]
            if isinstance(obj, dict) and ("replies" in obj or "jobs" in obj or "text" in obj and "who" not in obj):
                return obj
            first = first if first is not None else obj
        except ValueError:
            pass
        start = text.find("{", start + 1)
    return first if isinstance(first, dict) and "who" not in first else None


def salvage(text):
    """what can be read from a reply cut off mid-JSON (the model ran out of tokens): its finished replies and jobs"""
    replies = [{"who": w, "text": json.loads('"' + t + '"')}
               for w, t in re.findall(r'"who"\s*:\s*"([^"]*)"\s*,\s*"text"\s*:\s*"((?:[^"\\]|\\.)*)"', text)]
    jobs = []
    for m in re.finditer(r'\{[^{}]*"kind"\s*:[^{}]*\}', text):
        try:
            jobs.append(json.loads(m.group(0)))
        except ValueError:
            pass
    return {"replies": replies, "jobs": jobs} if replies or jobs else None


def build_messages(req):
    names = req.get("to") or []
    crew = req.get("context", {}).get("crew", []) or [{"name": n} for n in names]
    personas = "\n".join(f"  {c['name']}: {persona(c)}" for c in crew)
    system = f"""You voice the helper crew in a player's Factorio factory. Crew members:
{personas}
The player is talking to: {", ".join(names)}.
{JOBS_HELP}
Answer ONLY with a JSON object:
{{"replies": [{{"who": "<crew name>", "text": "<what they say out loud, under 25 words>"}}],
 "jobs": [{{"who": "<crew name>", "kind": "<job>", "item": "<item name or omit>", "count": <number or omit>, "text": "<remember only>"}}]}}
Give jobs only when the player asks for work; split work between members when it helps. Stay in character, be brief.
Respect the player's notes (keep-out places especially). Usually only one or two of them answer, the one it concerns most; not everyone has to speak. They remember what
happened lately ("recent" below) and may bring it up.
Current state: {json.dumps(req.get("context", {}), separators=(",", ":"))}"""
    return [{"role": "system", "content": system}] + _history[-12:] + [{"role": "user", "content": req.get("message", "")}]


def ask(s):
    try:
        req = json.loads(s)
        text = chat(req.get("llm") or {}, build_messages(req), 900)
        answer = extract_json(text)
        if not isinstance(answer, dict):
            answer = salvage(text)  # (cut off mid-JSON: the replies and jobs it finished)
        if not isinstance(answer, dict):  # a model that ignored the format: speak its words, never raw JSON
            words = text.strip() if "{" not in text else re.sub(r'[{}\[\]"]|\b(replies|who|text|jobs)\b\s*:?', " ", text)
            answer = {"replies": [{"who": (req.get("to") or [""])[0], "text": " ".join(words.split())[:300]}], "jobs": []}
        _note_said(answer.get("replies") or [])
        _history.extend([{"role": "user", "content": req.get("message", "")},
                         {"role": "assistant", "content": json.dumps(answer)}])
        del _history[:-24]
        return json.dumps({"replies": answer.get("replies") or [], "jobs": answer.get("jobs") or []})
    except Exception as e:  # noqa: BLE001 - the game shows the message
        return json.dumps({"error": f"{type(e).__name__}: {e}"[:300]})


def ada(s):
    req = json.loads(s)
    try:
        text = chat(req.get("llm") or {}, [{"role": "system", "content": ADA}, {"role": "user", "content": req["text"]}], 120)
        return json.dumps({"text": text.strip().strip('"')[:300] or req["text"]})
    except Exception as e:  # noqa: BLE001
        print(f"[aicrew] ada: {e}")
        return json.dumps({"text": req["text"]})


def check(s):
    """the in-game AI tab: which provider and key are used (masked), one real call timed, which voices"""
    req = json.loads(s or "{}")
    llm = req.get("llm") or {}
    try:
        import edge_tts  # noqa: F401
        tts = "edge-tts (natural voices)"
    except ImportError:
        tts = "Windows voices (pip install edge-tts for natural ones)"
    out = {"tts": tts}
    try:
        name, _, key, model = pick_provider(llm)
        env = PROVIDERS[name][2]
        out.update(provider=name, key=(key[:6] + "..." + key[-4:]) if len(key) > 12 else ("set" if key else None),
                   source="mod settings" if (llm.get("key") or "").strip() else (env if key else None))
        t = time.perf_counter()
        reply = chat(llm, [{"role": "user", "content": "Reply with one word: ready"}], 20)
        out.update(ok=True, seconds=round(time.perf_counter() - t, 2), reply=reply.strip()[:40],
                   model=model or _models.get(name))
    except Exception as e:  # noqa: BLE001 - shown in the AI tab
        out.update(ok=False, error=str(e)[:300])
    return json.dumps(out)


def banter(s):
    req = json.loads(s)
    try:
        ctx = req.get("context", {})
        crew = ctx.get("crew", [])
        personas = "\n".join(f"  {c['name']}: {persona(c)}" for c in crew)
        event = ctx.pop("event", None)
        if event:
            task = (f"This just happened: {event}. Write 1 or 2 lines (under 18 words each) of the crew reacting to it, "
                    "as people would in the moment. Someone it happened to who is no longer in the crew list can't speak.")
        else:
            task = (f"The player is away from the keyboard. Write {'2 to 4 lines between them' if len(crew) > 1 else 'one line'} "
                    "(under 20 words each) about what they're doing, the factory, their goal, something that happened "
                    "lately (recent) or whatever's on their mind.")
        said = "\n".join("  " + t for t in _said[-15:]) or "  (nothing yet)"
        system = f"""You write chatter for the helper crew in a Factorio factory.
Crew:
{personas}
{task}
In character, light and witty, no emoji. Never repeat or closely echo these lines they already said:
{said}
Answer ONLY with JSON: {{"replies": [{{"who": "<crew name>", "text": "<line>"}}]}}
State: {json.dumps(ctx, separators=(",", ":"))}"""
        text = chat(req.get("llm") or {}, [{"role": "system", "content": system}, {"role": "user", "content": "(the player is away)"}], 300)
        answer = extract_json(text) or {}
        _note_said(answer.get("replies") or [])
        return json.dumps({"replies": answer.get("replies") or []})
    except Exception as e:  # noqa: BLE001 - the game falls back to stock lines
        print(f"[aicrew] banter: {e}")
        return json.dumps({"replies": []})


# ------------------------------------------------------------------------------------------------- text to speech

EDGE_VOICES = {"ada": "en-US-AvaNeural"}
CREW_VOICES = ["en-GB-RyanNeural", "en-US-JennyNeural", "en-GB-SoniaNeural", "en-US-GuyNeural", "en-AU-NatashaNeural",
               "en-US-AndrewNeural", "en-IE-EmilyNeural", "en-AU-WilliamNeural"]
_queue = queue.Queue()
_worker = None
_sapi = None


def voice_for(voice):
    if isinstance(voice, str) and voice.startswith("ada:"):  # (the ADA voice picked in game: ava, jenny, ...)
        return "en-US-" + voice[4:].capitalize() + "Neural"
    if voice in EDGE_VOICES:
        return EDGE_VOICES[voice]
    try:
        return CREW_VOICES[int(voice) % len(CREW_VOICES)]
    except (TypeError, ValueError):
        return CREW_VOICES[0]


def _play_mp3(path):
    import ctypes
    mci = ctypes.windll.winmm.mciSendStringW
    mci(f'open "{path}" type mpegvideo alias aicrew', None, 0, None)
    mci("play aicrew wait", None, 0, None)
    mci("close aicrew", None, 0, None)


def _say_sapi(text, female):
    """Windows' built-in voices, through one PowerShell kept open (text goes over stdin, never the command line)"""
    global _sapi
    if _sapi is None or _sapi.poll() is not None:
        script = ("Add-Type -AssemblyName System.Speech; $s = New-Object System.Speech.Synthesis.SpeechSynthesizer; "
                  "while (($l = [Console]::In.ReadLine()) -ne $null) { $g, $t = $l.Split('|', 2); "
                  "try { $s.SelectVoiceByHints($(if ($g -eq 'f') { 'Female' } else { 'Male' })) } catch {}; $s.Speak($t) }")
        _sapi = subprocess.Popen(["powershell", "-NoProfile", "-NonInteractive", "-Command", script],
                                 stdin=subprocess.PIPE, text=True, encoding="utf-8",
                                 creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
    _sapi.stdin.write(("f" if female else "m") + "|" + " ".join(text.split()) + "\n")
    _sapi.stdin.flush()


# ADA (Satisfactory) is, by the community's ear, Google's WaveNet en-US-Wavenet-C with a multi-voice chorus and a
# doubled, slightly detuned echo (satisfactory.guru's recipe: chorus speed 1.9 depth 2.9; 2 echoes at -18.7 dB, 0 s,
# -0.12 semitones each). Here: a neural edge-tts voice through the same effects in ffmpeg, when ffmpeg is installed.
ADA_FILTER = ("[0:a]asplit=3[a][b][c];"
              "[b]asetrate=24000*0.993092,aresample=24000,volume=0.116[b2];"   # one echo: -0.12 st, -18.7 dB
              "[c]asetrate=24000*0.986233,aresample=24000,volume=0.116[c2];"   # the second: -0.24 st
              "[a][b2][c2]amix=inputs=3:normalize=0,"
              "chorus=0.8:0.9:22:0.35:1.9:2.9,"                               # the chorus: speed 1.9, depth 2.9
              "highpass=f=120,volume=1.1")


def _ada_fx(path):
    """path's audio through ADA's effects (in place); False without ffmpeg"""
    import shutil
    ff = shutil.which("ffmpeg")
    if not ff:
        return False
    out = path[:-4] + "-ada.mp3"
    r = subprocess.run([ff, "-y", "-loglevel", "error", "-i", path, "-filter_complex", ADA_FILTER, "-b:a", "96k", out],
                       capture_output=True, creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
    if r.returncode or not os.path.exists(out):
        return False
    os.replace(out, path)
    return True


_chime = None


def ada_chime():
    """the wav played before ADA speaks: ada-chime.wav next to this file if there is one, else a synthesized one (two
    soft rising bell tones with an echo, in the spirit of Satisfactory's notification; not its sound)"""
    global _chime
    own = os.path.join(os.path.dirname(os.path.abspath(__file__)), "ada-chime.wav")
    if os.path.exists(own):
        return own
    if _chime and os.path.exists(_chime):
        return _chime
    import math
    import struct
    import wave
    rate, length = 44100, 0.9
    buf = [0.0] * int(rate * length)
    for start, freq in ((0.0, 987.77), (0.11, 1479.98)):  # B5 then F#6
        for i in range(int(rate * 0.6)):
            t = i / rate
            env = min(1.0, t / 0.006) * math.exp(-t * 7.0)
            v = env * (math.sin(2 * math.pi * freq * t) + 0.35 * math.sin(2 * math.pi * freq * 2.01 * t)
                       + 0.12 * math.sin(2 * math.pi * freq * 3.0 * t))
            for delay, gain in ((0.0, 1.0), (0.09, 0.35), (0.18, 0.12)):  # a short echo
                j = int((start + delay) * rate) + i
                if j < len(buf):
                    buf[j] += v * gain
    peak = max(abs(x) for x in buf) or 1
    _chime = os.path.join(tempfile.gettempdir(), "aicrew-ada-chime.wav")
    with wave.open(_chime, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(b"".join(struct.pack("<h", int(x / peak * 0.5 * 32767)) for x in buf))
    return _chime


def _play_chime():
    import winsound
    winsound.PlaySound(ada_chime(), winsound.SND_FILENAME)


def _say(text, voice):
    name = voice_for(voice)
    if isinstance(voice, str) and voice.startswith("ada"):
        try:
            _play_chime()
        except Exception as e:  # noqa: BLE001 - no chime is fine
            print(f"[aicrew] chime: {e}")
    try:
        import asyncio
        import edge_tts
    except ImportError:
        return _say_sapi(text, str(voice).startswith("ada") or any(w in name for w in ("Jenny", "Sonia", "Natasha", "Emily", "Ava")))
    fd, path = tempfile.mkstemp(suffix=".mp3", prefix="aicrew-")
    os.close(fd)
    try:
        ada = isinstance(voice, str) and voice.startswith("ada")
        try:
            asyncio.run(edge_tts.Communicate(text, name, rate="-3%" if ada else "+4%").save(path))
        except Exception as e:  # noqa: BLE001 - the online voice failed (503s happen): Windows' own voice instead
            print(f"[aicrew] edge-tts: {e}; Windows voice instead")
            return _say_sapi(text, ada or any(w in name for w in ("Jenny", "Sonia", "Natasha", "Emily", "Ava")))
        if ada:
            _ada_fx(path)
        _play_mp3(path)
    finally:
        os.unlink(path)


def _run():
    while True:
        text, voice = _queue.get()
        try:
            _say(text, voice)
        except Exception as e:  # noqa: BLE001 - a voice failing must never stop the queue
            print(f"[aicrew] speak: {e}")


def speak(s):
    global _worker
    req = json.loads(s)
    text = (req.get("text") or "").strip()
    if text and _queue.qsize() < 3:  # (a backlog is stale by the time it's spoken: dropped)
        if _worker is None or not _worker.is_alive():
            _worker = threading.Thread(target=_run, name="aicrew-tts", daemon=True)
            _worker.start()
        voice = req.get("voice")
        if voice == "ada" and req.get("ada_voice"):
            voice = "ada:" + str(req["ada_voice"])
        _queue.put((text[:400], voice))
    return "ok"
