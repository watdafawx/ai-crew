"""aicrew.py checks. Offline by default; --live KEY also asks that provider (key prefix picks it) one question."""
import json
import sys
from pathlib import Path

for up in (1, 2):  # aicrew.py: next to the mod (its own repo) or a level up (the dev repo)
    sys.path.insert(0, str(Path(__file__).resolve().parents[up]))
import aicrew  # noqa: E402

pp = aicrew.pick_provider
import os  # noqa: E402
for _, _, env in aicrew.PROVIDERS.values():
    os.environ.pop(env or "-", None)
try:
    pp({})
    raise AssertionError("no key must fail")
except ValueError as e:
    assert "openrouter.ai/keys" in str(e)
assert pp({"provider": "ollama"})[2] == ""
assert pp({"key": "sk-or-v1-abc"})[0:3:2] == ("openrouter", "sk-or-v1-abc")
assert pp({"key": "gsk_x"})[0] == "groq" and pp({"key": "AIzaX"})[0] == "gemini" and pp({"key": "csk-1"})[0] == "cerebras"
assert pp({"provider": "groq", "key": "k", "model": "m"}) == ("groq", aicrew.PROVIDERS["groq"][0], "k", "m")
assert aicrew.choose_model("openrouter", ["a/b", "x/gemma-4-31b-it:free", "y/z:free"]) == "x/gemma-4-31b-it:free"
assert aicrew.choose_model("openrouter", ["a/b", "y/z:free"]) == "y/z:free"
assert aicrew.choose_model("openrouter", ["a/b"]) is None
assert aicrew.choose_model("openrouter", ["x/gemma-4-31b-it:free", "y/z:free"], {"x/gemma-4-31b-it:free"}) == "y/z:free"
assert aicrew.extract_json('Sure!\n```json\n{"replies": [], "jobs": [{"kind": "build"}]}\n```') == {"replies": [], "jobs": [{"kind": "build"}]}
assert aicrew.extract_json("<think>{nope}</think> {bad {\"a\": 1}") == {"a": 1}
assert aicrew.extract_json("no json") is None
assert aicrew.voice_for("ada:jenny") == "en-US-JennyNeural"
assert aicrew.voice_for("ada") == "en-US-AvaNeural" and aicrew.voice_for(9) == aicrew.CREW_VOICES[1]

# ask() with a faked model reply: plain text falls back to a spoken reply, JSON passes through
real = aicrew.chat
aicrew.chat = lambda llm, msgs, max_tokens=500: "Hey boss."
a = json.loads(aicrew.ask(json.dumps({"message": "hi", "to": ["Rook"], "context": {}})))
assert a == {"replies": [{"who": "Rook", "text": "Hey boss."}], "jobs": []}, a
aicrew.chat = lambda llm, msgs, max_tokens=500: '{"replies":[{"who":"Mara","text":"On it"}],"jobs":[{"who":"Mara","kind":"get","item":"iron-plate","count":20}]}'
a = json.loads(aicrew.ask(json.dumps({"message": "plates pls", "to": ["Mara"], "context": {}})))
assert a["jobs"][0]["item"] == "iron-plate"
aicrew.chat = lambda *a, **k: (_ for _ in ()).throw(RuntimeError("down"))
assert "down" in json.loads(aicrew.ask("{}"))["error"]
assert json.loads(aicrew.ada(json.dumps({"text": "Research complete."}))) == {"text": "Research complete."}
aicrew.chat = lambda *a, **k: '{"replies":[{"who":"Rook","text":"Quiet."},{"who":"Mara","text":"Too quiet."}]}'
assert len(json.loads(aicrew.banter(json.dumps({"context": {"crew": [{"name": "Rook"}, {"name": "Mara"}]}})))["replies"]) == 2
aicrew.chat = lambda *a, **k: (_ for _ in ()).throw(RuntimeError("down"))
assert json.loads(aicrew.banter("{}")) == {"replies": []}
c = json.loads(aicrew.check(json.dumps({"llm": {"key": "gsk_abcdefghijklmnop"}})))
assert c["provider"] == "groq" and c["key"] == "gsk_ab...mnop" and c["source"] == "mod settings" and not c["ok"], c
c = json.loads(aicrew.check("{}"))
assert c["ok"] is False and "openrouter.ai/keys" in c["error"] and c["tts"], c
aicrew.chat = lambda *a, **k: "ready"
c = json.loads(aicrew.check(json.dumps({"llm": {"key": "sk-or-v1-0123456789", "model": "x/y:free"}})))
assert c["ok"] and c["provider"] == "openrouter" and c["model"] == "x/y:free", c
aicrew.chat = real
aicrew._history.clear()
import wave  # noqa: E402
with wave.open(aicrew.ada_chime()) as w:
    assert w.getframerate() == 44100 and 0.5 < w.getnframes() / 44100 < 2
# a reply cut off mid-JSON (out of tokens), as seen in game: its finished parts, never the raw JSON
cut = ('{"replies": [{"who": "Juno", "text": "First, audit your current output per minute; identify bottlenecks."}, '
       '{"who": "Rook", "text": "I\'ll grab the plates."}], "jobs": [{"who": "Rook", "kind": "get", "item": "iron-plate", '
       '"count": 50}, {"who": "Juno", "kind": "goal", "item": "iron-gear-wheel", "count": 200, "line": true}, {"who": "Ju')
assert aicrew.extract_json(cut) is None
sv = aicrew.salvage(cut)
assert [r["who"] for r in sv["replies"]] == ["Juno", "Rook"] and sv["replies"][1]["text"] == "I'll grab the plates.", sv
assert [j["kind"] for j in sv["jobs"]] == ["get", "goal"] and sv["jobs"][1]["line"] is True, sv
real_chat = aicrew.chat
aicrew.chat = lambda *a, **k: cut
a = json.loads(aicrew.ask(json.dumps({"message": "help", "to": ["Juno"], "context": {}})))
assert len(a["replies"]) == 2 and len(a["jobs"]) == 2, a
aicrew.chat = lambda *a, **k: '{"replies": [{"who": "Juno", "text": "First, audit your'
a = json.loads(aicrew.ask(json.dumps({"message": "help", "to": ["Juno"], "context": {}})))
assert "{" not in a["replies"][0]["text"] and "audit" in a["replies"][0]["text"], a
aicrew.chat = real_chat
aicrew._history.clear()
print("offline OK")

if "--live" in sys.argv:
    ctx = {"crew": [{"name": "Rook", "doing": "following"}], "player_inventory": {"iron-plate": 40},
           "resources_nearby": ["iron-ore", "stone"], "ghosts_nearby": 12}
    key = sys.argv[sys.argv.index("--live") + 1]
    a = json.loads(aicrew.ask(json.dumps({"message": "Rook, grab me 30 stone and then build the blueprint", "to": ["Rook"],
                                          "context": ctx, "llm": {"key": key}})))
    print(json.dumps(a, indent=1))
    assert "error" not in a and a["replies"], a
    print("live OK")
