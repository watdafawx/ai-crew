-- AI Crew: what the crew say (bubbles, chat, voices, ADA's announcements), what they remember, their chatter,
-- and the AI jobs (Python: the LLM) that word it all. One of control.lua's files: see there.

-- (the other files' that this one uses: set by link, at the end)
local ADA_COLOR, add_job, context, crew, DIRS, dist2, find_member, job_for, LINES, members_of, pick, pretty, tell,
  TRAIT_ORDER, TRAITS

-- AI jobs (Python: the LLM). Every peer records a job in storage the same way; only the peer of the player it is for
-- runs it (its Python, its key) and, in multiplayer, sends the answer to all with native.sync (fse-std raises
-- "fse-sync"), so every peer applies the same answer in the same tick. In single player the answer applies at once.
local jobs = { running = {} } -- running: native job id -> job number (only on the peer running it); checked: the AI
-- was tested this session (single player); warmed: Kokoro warmed this session
local on_answer -- (with the chatter: what an answer does)
-- player index -> the last AI test (storage.ai_tests: the panel shows it, and every peer's panel must match)
local function ai_state()
  storage.ai_tests = storage.ai_tests or {}
  return storage.ai_tests
end

local function py()
  if not native then return false end
  -- (multiplayer answers travel through fse-std's sync)
  if game.is_multiplayer() and not script.active_mods["fse-std"] then return false end
  local ok, p = pcall(native.plugins)
  return ok and p and p.py ~= nil
end

-- does this peer run the job for `owner`? (in single player: always)
function jobs.runs_here(owner)
  if not game.is_multiplayer() then return true end
  return owner ~= nil and native.local_player ~= nil and native.local_player() == owner
end

function jobs.answered(n, st, out)
  local p = storage.jobs and storage.jobs[n]
  if not p then return end
  storage.jobs[n] = nil
  if st == "done" then on_answer(p, out)
  elseif p.kind ~= "ask" then on_answer(p, "{}")
  else
    local player = p.owner and game.get_player(p.owner)
    if player then player.print("[ai-crew] AI error: " .. tostring(out):sub(1, 300)) end
  end
end

-- the answer of job n, to every peer
function jobs.deliver(n, st, out)
  if game.is_multiplayer() then
    native.sync("ai-crew:answer", helpers.table_to_json({ n = n, st = st, out = out }))
  else
    jobs.answered(n, st, out)
  end
end

-- a Python job for `owner` (p: what to do with the answer, plain data); false if there is no Python
function jobs.start(owner, fn, input, p)
  if not py() then return false end
  storage.jobs = storage.jobs or {}
  storage.job_n = (storage.job_n or 0) + 1
  local n = storage.job_n
  p.at = game.tick
  storage.jobs[n] = p
  if jobs.runs_here(owner) then
    local id, err = native.start("py", fn, input)
    if id then jobs.running[id] = n else jobs.deliver(n, "error", tostring(err)) end
  end
  return true
end

local function player_setting(player, name)
  local ok, v = pcall(function() return settings.get_player_settings(player)[name].value end)
  if ok then return v end
end

-- the single player, for settings when no one gave the order
local function any_player()
  for _, p in pairs(game.connected_players) do return p end
end

-- "Crew ping places" (the [gps] map tag at the end of their lines and ADA's): on unless the owner (or a test) turned
-- it off
local function pings(owner)
  if storage.test_pings ~= nil then return storage.test_pings end
  local pl = owner and game.get_player(owner) or any_player()
  return not pl or player_setting(pl, "ai-crew-pings") ~= false
end

local function speak(text, voice, player)
  if game.is_multiplayer() then
    player = native and native.local_player and native.local_player() and game.get_player(native.local_player())
  end
  player = player or any_player()
  if not (player and py()) then return end
  if not player_setting(player, voice == "ada" and "ai-crew-ada" or "ai-crew-voices") then return end
  native.call("py", "aicrew:speak", helpers.table_to_json({ text = text, voice = voice,
    ada_voice = voice == "ada" and player_setting(player, "ai-crew-ada-voice") or nil,
    volume = (player_setting(player, voice == "ada" and "ai-crew-ada-volume" or "ai-crew-voice-volume") or 100) / 100 }))
end

local function llm_settings(player)
  if not player then return {} end
  return { provider = player_setting(player, "ai-crew-provider"), key = player_setting(player, "ai-crew-api-key"),
    model = player_setting(player, "ai-crew-model") }
end

-- ADA announces: an event of lines.lua's ada (one of its lines, not one said since it last went through them all,
-- vars filled in), or plain text
local function ada(text, vars)
  local set = LINES.ada[text]
  if set then
    storage.ada_said = storage.ada_said or {}
    local used = storage.ada_said[text] or {}
    local fresh = {}
    for _, l in ipairs(set) do if not used[l] then fresh[#fresh + 1] = l end end
    if #fresh == 0 then used, fresh = {}, set end
    local l = pick(fresh)
    used[l] = true
    storage.ada_said[text] = used
    text = l:gsub("{(%w+)}", function(k) return vars and vars[k] ~= nil and tostring(vars[k]) or "" end)
  end
  local gps = vars and vars.at and pings() and string.format(" [gps=%.1f,%.1f,%s]", vars.at.x, vars.at.y, vars.surface or "nauvis") or ""
  local p = any_player()
  if p and not player_setting(p, "ai-crew-ada") then return end
  if p and py() and player_setting(p, "ai-crew-ada-llm") then
    if jobs.start(p.index, "aicrew:ada", helpers.table_to_json({ text = text, llm = llm_settings(p) }),
           { kind = "ada", text = text, gps = gps }) then
      return
    end
  end
  game.print("[color=" .. ADA_COLOR .. "][ADA][/color] " .. text .. gps)
  speak(text, "ada")
end

local function trait(m) return TRAITS[m.name] or TRAIT_ORDER[(m.voice or 0) % #TRAIT_ORDER + 1] end

-- a stock line for the event in m's manner, not one it said since it last went through them all
local function line(m, event, vars)
  local set = LINES[event]
  local pool = {}
  for _, l in ipairs(set[trait(m)] or {}) do pool[#pool + 1] = l end
  for _, l in ipairs(set.any or {}) do pool[#pool + 1] = l end
  if #pool == 0 then pool = set.upbeat or set.any end
  m.recent = m.recent or {}
  local used = m.recent[event] or {}
  local fresh = {}
  for _, l in ipairs(pool) do if not used[l] then fresh[#fresh + 1] = l end end
  if #fresh == 0 then used, fresh = {}, pool end
  local l = pick(fresh)
  used[l] = true
  m.recent[event] = used
  local text = l:gsub("{(%w+)}", function(k) return vars and vars[k] ~= nil and tostring(vars[k]) or "" end)
  m.bank_line = { text = text, event = event, at = vars and vars.at } -- (say may have the AI word it; at: where it's about)
  return text
end

-- what happened lately, the crew's memory: the AI gets it with every request (saved; the last 20 per player)
local function remember(owner, text)
  storage.events = storage.events or {}
  local k = owner or 0
  local list = storage.events[k] or {}
  storage.events[k] = list
  list[#list + 1] = { tick = game.tick, text = text }
  if #list > 20 then table.remove(list, 1) end
end

-- Your notes for the crew ("remember ...") and the places they keep out of ("keep out", "don't touch this", "hands
-- off", "leave this alone"), saved, the AI told them all. In a keep-out zone (24 tiles round where you said it) they take
-- nothing from chests, borrow or refuel no machine, put nothing down and don't roam; what you mark there yourself
-- (ghosts, deconstruction, upgrades) they still do. chisle: zones count for everyone's crew, not just yours
local ZONE = 24
local function notes(owner)
  storage.notes = storage.notes or {}
  local k = owner or 0
  storage.notes[k] = storage.notes[k] or {}
  return storage.notes[k]
end

local function kept_out(surface, pos)
  for _, list in pairs(storage.notes or {}) do
    for _, n in ipairs(list) do
      if n.keep_out and n.surface == surface.name and dist2(n.pos, pos) <= ZONE * ZONE then return true end
    end
  end
  return false
end

-- Who speaks, and how loud. how: nil = news (in chat and out loud, unless someone just spoke or this one has been
-- talking a lot: then in chat only), "quiet" = routine (a bubble over its head, nothing else), "talk" = conversation
-- (an answer to the player, chatter: always in chat and out loud). The same news twice within 5 minutes is a bubble.
-- News from the line bank, with "Crew word their lines with the AI" on, goes to the AI first and comes back "worded":
-- in its own words, said like news (the checks against the same news twice were done on the bank's line).
-- at: where the line is about (a nest, a dark machine, an attack; a bank line's vars.at): the chat line ends in a map
-- tag for it ([gps=...]: a pin the player clicks to see the place), so "over here" says where. Not spoken, no bubble
-- turn to look at pos, standing still, as a player turns their character
local function face(m, pos)
  local e = m.entity
  if m.move or not e.valid then return end
  local d = math.floor(math.atan2(pos.x - e.position.x, -(pos.y - e.position.y)) / (math.pi / 4) + 0.5) % 8
  pcall(function() e.direction = DIRS[d + 1] end)
end

-- A line over a crew member's head, for `ttl` ticks. Short: a long one is cut at a word with "…" (the whole of it
-- goes to the chat). Raised above a teammate's nearby line instead of over it.
local BUBBLE_CHARS, BUBBLE_ROW = 44, 0.75
local function cut(text)
  if #text <= BUBBLE_CHARS then return text end
  local s = text:sub(1, BUBBLE_CHARS)
  while #s > 0 and s:byte(-1) >= 0x80 and s:byte(-1) < 0xC0 do s = s:sub(1, -2) end  -- (not inside a UTF-8 letter)
  if #s > 0 and s:byte(-1) >= 0xC0 then s = s:sub(1, -2) end
  local open, close = s:match(".*()%["), s:match(".*()%]")  -- (not inside a [tag])
  if open and (not close or close < open) then s = s:sub(1, open - 1) end
  local word = s:match("^(.*%S)%s+%S*$")  -- (at a word)
  if word and #word > BUBBLE_CHARS / 2 then s = word end
  return (s:gsub("[%s%p]+$", "")) .. "…"
end

local function bubble(m, text, scale, ttl)
  if m.bubble and m.bubble.valid then m.bubble.destroy() end
  m.bubble = nil
  local e = m.entity
  if not (e and e.valid) then return end
  text = cut(text)
  scale = scale or 1.1
  local w = #text * 0.2 * scale  -- (about how wide, in tiles)
  local p = e.position
  local taken = {}  -- (the heights of teammates' lines this one would cross)
  for _, o in pairs(crew()) do
    local oe = o.entity
    if o ~= m and o.bubble and o.bubble.valid and oe and oe.valid and oe.surface == e.surface then
      local q = oe.position
      if math.abs(q.x - p.x) < (w + (o.bubble_w or 4)) / 2 + 0.5 and math.abs(q.y - p.y) < 4 then
        taken[#taken + 1] = q.y + (o.bubble_dy or -2.9)
      end
    end
  end
  local dy = -2.9
  for _ = 1, 6 do
    local clear = true
    for _, y in ipairs(taken) do if math.abs(p.y + dy - y) < BUBBLE_ROW then clear = false break end end
    if clear then break end
    dy = dy - BUBBLE_ROW
  end
  m.bubble_w, m.bubble_dy = w, dy
  m.bubble = rendering.draw_text({ text = text, surface = e.surface, target = { entity = e, offset = { 0, dy } },
    color = m.color, scale = scale, alignment = "center", time_to_live = ttl or 300 })
  return m.bubble
end

local function say(m, text, how, at)
  local bank = m.bank_line
  m.bank_line = nil
  at = at or bank and bank.text == text and bank.at
  local e = m.entity
  local c = m.color
  local p = m.owner and game.get_player(m.owner) -- (they look at you when they talk, near you)
  local pc = p and p.valid and p.character
  if pc and pc.surface == e.surface and dist2(pc.position, e.position) < 900 then face(m, pc.position) end
  bubble(m, text, 1.1, 300)
  if how == "quiet" then return end
  local t = game.tick
  if how == nil then -- (any line it said in the last 5 minutes, not just the last one)
    m.news = m.news or {}
    if t - (m.news[text] or -18000) < 18000 then return end
    if table_size(m.news) > 40 then
      for k, at in pairs(m.news) do if t - at >= 18000 then m.news[k] = nil end end
    end
    m.news[text] = t
    storage.crew_news = storage.crew_news or {} -- (a teammate said just this a minute ago: no need to say it again)
    if t - (storage.crew_news[text] or -3600) < 3600 then return end
    storage.crew_news[text] = t
    if table_size(storage.crew_news) > 60 then
      for k, at in pairs(storage.crew_news) do if t - at >= 3600 then storage.crew_news[k] = nil end end
    end
  end
  local player = m.owner and game.get_player(m.owner) or any_player()
  if how == nil and bank and bank.text == text and t - (storage.voice_at or -180) >= 180 and t - (m.voice_at or -1200) >= 1200
    and player and py() and player_setting(player, "ai-crew-lines-llm") and player_setting(player, "ai-crew-voices")
    and jobs.start(player.index, "aicrew:line", helpers.table_to_json({ llm = llm_settings(player), name = m.name,
      manner = trait(m), event = bank.event, text = text }), { kind = "line", owner = m.owner, who = m.name, text = text,
      pos = at and { x = at.x, y = at.y } }) then
    storage.voice_at, m.voice_at = t, t -- (its turn to speak, kept for when the words come back)
    return
  end
  local tag = at and pings(m.owner) and string.format(" [gps=%.1f,%.1f,%s]", at.x, at.y, e.surface.name) or ""
  game.print(string.format("[color=%g,%g,%g]%s:[/color] %s", c[1], c[2], c[3], m.name, text) .. tag)
  m.lines = (m.lines or 0) + 1 -- (what reached the chat, the last few: for tests)
  m.last_lines = m.last_lines or {}
  table.insert(m.last_lines, t .. ": " .. text .. tag)
  if #m.last_lines > 8 then table.remove(m.last_lines, 1) end
  -- (3 s between any two voiced lines, 20 s between one member's voiced news; worded news had its turn kept)
  if how == nil and (t - (storage.voice_at or -180) < 180 or t - (m.voice_at or -1200) < 1200) then
    return
  end
  storage.voice_at, m.voice_at = t, t
  speak(text, m.voice, m.owner and game.get_player(m.owner))
end

-- -------------------------------------------------------------------------------------------------- AFK chatter

-- chatter waiting its turn: storage.lines {at, owner, who, text} (saved: a joining peer must say the same lines)
local function queued()
  storage.lines = storage.lines or {}
  return storage.lines
end

-- stock chatter: one member's line (an idle thought, or a reaction to ev), sometimes another's answer
local function canned(owner, members, ev)
  local pool = {}
  for _, m in pairs(members) do if not (ev and ev.who == m.name) then pool[#pool + 1] = m end end
  if #pool == 0 then return end
  local a = pick(pool)
  local g = storage.goals and storage.goals[owner]
  local text = ev and line(a, ev.kind, ev.vars) or g and math.random() < 0.3
    and string.format("Still on that goal: %d %s. We'll get there.", g.count, pretty(g.item)) or line(a, "idle")
  table.insert(queued(), { at = game.tick + (ev and 90 or 0), owner = owner, who = a.name, text = text,
    pos = ev and ev.vars and ev.vars.at })
  if #members > 1 and not ev and math.random() < 0.6 then
    local b
    repeat b = pick(members) until b ~= a
    table.insert(queued(), { at = game.tick + 240, owner = owner, who = b.name, text = line(b, "reply", { other = a.name }) })
  end
end

-- the crew talk among themselves: while the player is away (ev nil), or a reaction to something that happened
-- (ev = {kind = a LINES event, text = what happened, vars, who = the one it happened to}). The LLM writes it when
-- there's one, else stock lines
local function chatter(player, ev)
  local members = members_of(player.index)
  if #members == 0 then return end
  local llm = llm_settings(player)
  if py() and llm.provider ~= "off" then
    local ctx = context(player, members)
    ctx.goal = storage.goals and storage.goals[player.index]
    ctx.event = ev and ev.text
    -- (ev's who is a member's name: plain data, as a job keeps it in storage)
    local plain_ev = ev and { kind = ev.kind, text = ev.text, vars = ev.vars, who = type(ev.who) == "table" and ev.who.name or ev.who }
    if jobs.start(player.index, "aicrew:banter", helpers.table_to_json({ llm = llm, context = ctx }),
           { kind = "banter", owner = player.index, ev = plain_ev }) then
      return
    end
  end
  canned(player.index, members, ev)
end

local function progress(owner) storage.progress_at = storage.progress_at or {} storage.progress_at[owner or 0] = game.tick end

-- something worth a word happened: remembered, and someone reacts (at most once a minute per player)
local function react(owner, kind, text, vars, who)
  remember(owner, text)
  local player = owner and game.get_player(owner)
  if not (player and player.connected) then return end
  storage.react_at = storage.react_at or {}
  if game.tick < (storage.react_at[owner] or 0) then return end
  storage.react_at[owner] = game.tick + 3600
  chatter(player, { kind = kind, text = text, vars = vars, who = who })
end

on_answer = function(p, out)
  local player = p.owner and game.get_player(p.owner)
  local a = helpers.json_to_table(out) or { error = "unreadable answer" }
  if p.kind == "ada" then
    local text = type(a.text) == "string" and a.text ~= "" and a.text or p.text
    game.print("[color=" .. ADA_COLOR .. "][ADA][/color] " .. text .. (p.gps or ""))
    return speak(text, "ada")
  end
  if p.kind == "line" then -- (a bank line in the member's own words; the bank's own when the AI can't)
    local m = crew()[p.who]
    if m and m.entity.valid then say(m, type(a.text) == "string" and a.text ~= "" and a.text:sub(1, 200) or p.text, "worded", p.pos) end
    return
  end
  if p.kind == "check" then
    if not (a.provider or a.error) then a.error = "no answer" end
    ai_state()[p.owner] = a
    return
  end
  if p.kind == "banter" then
    local members = members_of(p.owner)
    if #members == 0 then return end
    local at = game.tick
    for _, r in pairs(type(a.replies) == "table" and a.replies or {}) do
      if type(r) == "table" and type(r.text) == "string" and r.text ~= "" then
        local m = find_member(r.who, p.owner) or members[1]
        table.insert(queued(), { at = at, owner = p.owner, who = m.name, text = r.text:sub(1, 200),
          pos = at == game.tick and p.ev and p.ev.vars and p.ev.vars.at or nil })
        at = at + 300
      end
    end
    if at == game.tick then canned(p.owner, members, p.ev) end
    return
  end
  local fallback = find_member(p.to[1], p.owner)
  if a.error then
    if fallback and fallback.bubble and fallback.bubble.valid then fallback.bubble.destroy() end
    return tell(player, "[ai-crew] " .. tostring(a.error))
  end
  for _, r in pairs(a.replies or {}) do
    local m = find_member(r.who, p.owner) or fallback
    if m and type(r.text) == "string" and r.text ~= "" then say(m, r.text:sub(1, 300), "talk") end
  end
  for _, j in pairs(a.jobs or {}) do
    local m = find_member(j.who, p.owner) or fallback
    local job = m and type(j.kind) == "string" and job_for(m, j.kind, j.item, tonumber(j.count), j)
    if job then add_job(m, job) end
  end
end

-- ------------------------------------------------------------------------------------------------------------- shared
-- what the other files use of this one, and its link: control.lua calls it once all files are loaded
return {
  share = { ada = ada, ai_state = ai_state, any_player = any_player, canned = canned, chatter = chatter, face = face,
    jobs = jobs, kept_out = kept_out, line = line, llm_settings = llm_settings, notes = notes,
    player_setting = player_setting, progress = progress, py = py, queued = queued, react = react, remember = remember,
    say = say, bubble = bubble, speak = speak, trait = trait, ZONE = ZONE },
  link = function(A)
    ADA_COLOR, add_job, context, crew, DIRS, dist2 = A.ADA_COLOR, A.add_job, A.context, A.crew, A.DIRS, A.dist2
    find_member, job_for, LINES, members_of, pick = A.find_member, A.job_for, A.LINES, A.members_of, A.pick
    pretty, tell, TRAIT_ORDER, TRAITS = A.pretty, A.tell, A.TRAIT_ORDER, A.TRAITS
  end,
}
