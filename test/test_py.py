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
assert aicrew.kokoro_voice_for("ada") == aicrew.kokoro_voice_for("ada:heart") == ("af_heart", "en-us")
assert aicrew.kokoro_voice_for("ada:alice") == ("bf_alice", "en-gb") and aicrew.kokoro_voice_for("ada:jenny")[0] == "af_heart"
assert aicrew.kokoro_voice_for(9) == aicrew.KOKORO_CREW[1] == ("af_bella", "en-us") and aicrew.kokoro_voice_for(None)[0] == "bm_george"

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
# a reaction to an event: the event and the lines already said go to the model; a member not in PERSONAS gets its manner
seen = []
aicrew.chat = lambda llm, msgs, max_tokens=500: seen.append(msgs[0]["content"]) or '{"replies":[{"who":"Zed","text":"Ouch."}]}'
aicrew.banter(json.dumps({"context": {"crew": [{"name": "Zed", "manner": "laconic"}], "event": "Rook was killed"}}))
assert "Rook was killed" in seen[0] and "laconic and cool" in seen[0] and "Too quiet." in seen[0], seen[0]
aicrew.chat = lambda *a, **k: (_ for _ in ()).throw(RuntimeError("down"))
assert json.loads(aicrew.banter("{}")) == {"replies": []}
# a stock line in the member's own words: one plain line; the bank's when the model's is no good or it fails
cl = aicrew.clean_line
assert cl('Rook: "Biters again. Grabbing my wrench."\nmore', "Rook", "Biters.") == "Biters again. Grabbing my wrench."
assert cl("**Rook**: Here.", "Rook", "Biters.") == "Here."
assert cl("", "Rook", "Biters.") == "Biters." and cl("x" * 200, "Rook", "Biters.") == "Biters."
assert cl("Make some gears?", "Juno", "Make 100 gears?") == "Make 100 gears?"  # (a number lost)
assert json.loads(aicrew.line(json.dumps({"name": "Rook", "text": "Biters."}))) == {"text": "Biters."}  # (chat is down)
seen = []
aicrew.chat = lambda llm, msgs, max_tokens=500: seen.append(msgs) or "Bugs at the wall. Moving."
a = json.loads(aicrew.line(json.dumps({"name": "Pip", "manner": "cheerful", "event": "alarm", "text": "Not the wall! Coming!"})))
assert a == {"text": "Bugs at the wall. Moving."} and "cheerful" in seen[0][0]["content"] and "Not the wall" in seen[0][1]["content"], a
aicrew.chat = lambda *a, **k: (_ for _ in ()).throw(RuntimeError("down"))
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
# warm: Kokoro loaded and run once on a thread, nothing raised without it, once only when it worked
real_model = aicrew.kokoro_model


def warm_wait():
    if aicrew._warming:
        aicrew._warming.join(5)
        assert not aicrew._warming.is_alive()


def no_kokoro():
    raise ImportError("kokoro_onnx")


aicrew.kokoro_model = no_kokoro
assert aicrew.warm("{}") == "ok" and aicrew.warm("{}") == "ok"
warm_wait()
assert not aicrew._warmed
aicrew.kokoro_model = lambda: None  # (files still coming: tried again on the next call)
assert aicrew.warm("{}") == "ok"
warm_wait()
assert not aicrew._warmed


class FakeKokoro:
    calls = 0

    def create(self, text, **kw):
        FakeKokoro.calls += 1
        return [0.0], 24000


aicrew.kokoro_model = FakeKokoro
assert aicrew.warm("{}") == "ok"
warm_wait()
assert aicrew.warm("{}") == "ok" and aicrew.warm("{}") == "ok"
warm_wait()
assert aicrew._warmed and FakeKokoro.calls == 1, FakeKokoro.calls
aicrew.kokoro_model = real_model
aicrew._warmed, aicrew._warming = False, None
# control.lua's files, statically (no game): each file's imports are shared by some file (or control.lua's A) and
# match its link; each shared name is defined in its file; no file uses a name it never declares (a global, a typo).
# Best effort, scope-blind: a name declared anywhere in a file counts as declared all through it.
import re  # noqa: E402

LUA_KEYWORDS = set("and break do else elseif end false for function goto if in local nil not or repeat return then "
                   "true until while".split())
GLOBALS = set("game script storage defines prototypes helpers rendering settings remote commands serpent log "
              "localised_print table_size native mods data assert error ipairs pairs next pcall xpcall print select "
              "setmetatable getmetatable rawget rawset rawequal rawlen tonumber tostring type unpack table string math "
              "debug load require _G _ENV utf8 bit32 os".split())


LONG = re.compile(r"\[(=*)\[")
TOKEN = re.compile(r"[A-Za-z_]\w*|0[xX][0-9a-fA-F]+|\d+\.?\d*(?:[eE][-+]?\d+)?|\.\d+|\.\.\.|\.\.|::|[=~<>]=|.")


def lua_tokens(src):
    """(kind, text, line): names, numbers, symbols; strings come back as one "str" token, comments are dropped."""
    out, i, line, n = [], 0, 1, len(src)
    while i < n:
        c = src[i]
        if c == "\n":
            line, i = line + 1, i + 1
        elif c in " \t\r":
            i += 1
        elif src.startswith("--", i):
            m = LONG.match(src, i + 2)
            j = src.find("]" + m.group(1) + "]", i) if m else src.find("\n", i)
            j = n if j < 0 else j + len(m.group(1)) + 2 if m else j
            line, i = line + src.count("\n", i, j), j
        elif c == "[" and LONG.match(src, i):
            eq = LONG.match(src, i).group(1)
            j = src.find("]" + eq + "]", i) + len(eq) + 2
            out.append(("str", "", line))
            line, i = line + src.count("\n", i, j), j
        elif c in "\"'":
            j = i + 1
            while src[j] != c:
                j += 2 if src[j] == "\\" else 1
            out.append(("str", "", line))
            line, i = line + src.count("\n", i, j), j + 1
        else:
            m = TOKEN.match(src, i)
            t = m.group(0)
            out.append(("name" if re.match(r"[A-Za-z_]", t) and t not in LUA_KEYWORDS else "sym", t, line))
            i += len(t)
    return out


def lua_names(toks):
    """(declared, used): every name a file declares (local, params, for, its functions), and its free uses."""
    declared, used, stack = set(), [], []
    for k, (kind, t, ln) in enumerate(toks):
        prev = toks[k - 1][1] if k else ""
        nxt = toks[k + 1][1] if k + 1 < len(toks) else ""
        if kind == "sym" and t in ("(", "{", "["):
            stack.append(t)
        elif kind == "sym" and t in (")", "}", "]") and stack:
            stack.pop()
        if kind != "name":
            continue
        if (prev in ("local", "for") or (prev == "," and decl_list(toks, k))
                or (prev == "function" and toks[k - 2][1] == "local") or param(toks, k)):
            declared.add(t)
        elif prev in (".", ":", "::", "goto") or nxt == "::":
            pass
        elif nxt == "=" and stack and stack[-1] == "{" and prev in ("{", ",", ";"):
            pass  # (a table key)
        else:
            used.append((t, ln))
    return declared, used


def decl_list(toks, k):
    """is toks[k] (after a comma) in a `local a, b` or `for a, b` name list?"""
    while k >= 2 and toks[k - 1][1] == "," and toks[k - 2][0] == "name":
        k -= 2
    return k >= 1 and toks[k - 1][1] in ("local", "for")


def param(toks, k):
    """is toks[k] a function parameter?"""
    j = k - 1
    while j >= 0 and (toks[j][1] == "," or toks[j][0] == "name" or toks[j][1] == "..."):
        j -= 1
    if j < 1 or toks[j][1] != "(":
        return False
    j -= 1
    if toks[j][1] == "function":
        return True
    while j >= 1 and toks[j][0] == "name" and toks[j - 1][1] in (".", ":"):
        j -= 2
    return toks[j][0] == "name" and j >= 1 and toks[j - 1][1] == "function"


def lua_table_keys(text):
    """the keys of a flat `{ k = v, ... }` (one level of nesting skipped)."""
    flat = re.sub(r"\{[^{}]*\}", "{}", text.strip()[1:-1])
    return dict(re.findall(r"(\w+)\s*=\s*([\w.]+|\{\})", flat))


def check_links(mod):
    control = (mod / "control.lua").read_text(encoding="utf-8")
    files = re.search(r"FILE_NAMES = \{([^}]*)\}", control).group(1)
    files = re.findall(r'"(\w+)"', files)
    assert files, "control.lua: no FILE_NAMES"
    a = lua_table_keys(re.search(r"local A = (\{.*?\})\n", control, re.S).group(1))
    available = set(a)
    imports, problems = {}, []
    for name in files:
        src = (mod / (name + ".lua")).read_text(encoding="utf-8")
        ret = re.search(r"\nreturn \{\s*\n\s*share = (\{.*?\}),\s*\n\s*link = function\(A\)\n(.*?)\n\s*end,", src, re.S)
        assert ret, name + ".lua: no `return { share = {...}, link = function(A) ... end, }` at its end"
        share = lua_table_keys(ret.group(1))
        declared, _ = lua_names(lua_tokens(src[:ret.start()]))
        for k, v in share.items():
            if k != v:
                problems.append(f"{name}.lua shares {k} = {v} (not its own name)")
            elif v not in declared:
                problems.append(f"{name}.lua shares {k}, which it never defines")
            if k in available:
                problems.append(f"{name}.lua shares {k}, already shared by another file or control.lua")
            available.add(k)
        head = re.search(r"\(the other files' that this one uses: set by link.*\n(local .*\n(?:  .*\n)*)", src)
        decl = set(re.findall(r"\w+", head.group(1))[1:]) if head else set()
        got = set()
        for lhs, rhs in re.findall(r"^\s*([\w, ]+?)\s*=\s*(A\.[\w, .A]+)$", ret.group(2), re.M):
            lhs = [x.strip() for x in lhs.split(",")]
            rhs = [x.strip()[2:] for x in rhs.split(",")]
            if lhs != rhs:
                problems.append(f"{name}.lua link: {', '.join(lhs)} = {', '.join('A.' + x for x in rhs)} (mismatched)")
            got.update(rhs)
        for x in sorted(decl - got):
            problems.append(f"{name}.lua declares import {x}, which its link never sets")
        for x in sorted(got - decl):
            problems.append(f"{name}.lua link sets {x}, which it never declares at its top")
        imports[name] = got
    after = control[control.index("FILE_NAMES"):]
    imports["control"] = set(re.findall(r"\bA\.(\w+)", after.split("setmetatable(A, nil)")[0]))
    for name, got in imports.items():
        for x in sorted(got - available):
            problems.append(f"{name}.lua imports {x}, which no file shares")
    for name in files + ["control"]:
        declared, used = lua_names(lua_tokens((mod / (name + ".lua")).read_text(encoding="utf-8")))
        for t, ln in used:
            if t not in declared and t not in GLOBALS:
                problems.append(f"{name}.lua:{ln}: {t} is neither local, imported nor a Lua/Factorio global")
    return problems


links = check_links(Path(__file__).resolve().parents[1])
assert not links, "control.lua's files:\n  " + "\n  ".join(links)

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
