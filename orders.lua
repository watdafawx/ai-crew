-- AI Crew: the crew (hire, find), orders typed or said in chat, and the jobs they make. One of control.lua's files.

-- (the other files' that this one uses: set by link, at the end)
local ACKS, ada, add_need, any_player, available, claims, COLORS, CREW, crew, dist2, goals, handcraft_recipe, jobs,
  line, llm_settings, MAX_CREW, NAMES, nearest_source, notes, pick, plan, player_setting, pretty, py, RADIUS, remember,
  resolve_item, say, stop_mining, stop_walk, trait, unload, ZONE

-- ---------------------------------------------------------------------------------------------------------- orders

local function members_of(owner)
  local out = {}
  for _, m in pairs(crew()) do if m.owner == owner then out[#out + 1] = m end end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

local function find_member(name, owner)
  if type(name) ~= "string" then return end
  for _, m in pairs(members_of(owner)) do if m.name:lower() == name:lower() then return m end end
end

-- a crew member on the map (chart view): a coloured dot with its name, following it
local function map_marker(e, name, color)
  rendering.draw_circle({ color = color, radius = 1.6, filled = true, target = e, surface = e.surface, render_mode = "chart" })
  rendering.draw_circle({ color = { 0, 0, 0 }, radius = 1.6, width = 2, filled = false, target = e, surface = e.surface,
    render_mode = "chart" })
  rendering.draw_text({ text = name, target = { entity = e, offset = { 0, -3 } }, surface = e.surface, color = color,
    scale = 1.2, alignment = "center", vertical_alignment = "bottom", render_mode = "chart" })
end

-- The owner's character's own bonuses on each of the crew, as a player's: reach, build, mining, drop and pickup
-- distances (far reach sets them per character), crafting, mining and running speed, health, pockets. On hire and
-- every 5 s, so a changed setting, research or respawn follows; from the owner's character, else any connected
-- player's, else as they are. Pockets never shrink (what's in them would spill). The force's research (crafting and
-- mining speed, reach, pockets, health, weapons) reaches the crew by itself: they're characters of the same force
local OWN_BONUSES = { "character_build_distance_bonus", "character_reach_distance_bonus",
  "character_resource_reach_distance_bonus", "character_item_drop_distance_bonus",
  "character_item_pickup_distance_bonus", "character_loot_pickup_distance_bonus",
  "character_crafting_speed_modifier", "character_mining_speed_modifier",
  "character_running_speed_modifier", "character_health_bonus", "character_inventory_slots_bonus" }
local function match_owner(m)
  local e = m.entity
  if not (e and e.valid) then return end
  local p = m.owner and game.get_player(m.owner)
  local c = p and p.valid and p.character or not m.owner and storage.test_owner -- (tests: a stand-in for yours)
  if not (c and c.valid) then
    c = nil
    for _, q in pairs(game.connected_players) do if q.character then c = q.character break end end
  end
  if not c then return end
  for _, k in ipairs(OWN_BONUSES) do
    local v = c[k]
    if e[k] ~= v and (k ~= "character_inventory_slots_bonus" or v > e[k]) then e[k] = v end
  end
end

-- mode: "roam", "follow" or "stay"; nil: the owner's setting "ai-crew-new-mode" (roam), with no player follow
local function hire(name, surface, position, force, owner, mode)
  local pl = owner and game.get_player(owner) or not owner and any_player()
  mode = mode or pl and player_setting(pl, "ai-crew-new-mode") or "follow"
  local taken = {}
  for n in pairs(crew()) do taken[n:lower()] = true end
  if not name then
    for _, n in ipairs(NAMES) do if not taken[n:lower()] then name = n break end end
    name = name or ("Crew" .. (table_size(crew()) + 1))
  end
  if taken[name:lower()] then return nil, name .. " is already on the crew." end
  local at = surface.find_non_colliding_position(CREW, position, 10, 0.5) or position
  local e = surface.create_entity({ name = CREW, position = at, force = force })
  if not e then return nil, "No room to spawn a crew member." end
  local i = table_size(crew())
  local color = COLORS[i % #COLORS + 1]
  e.color = { r = color[1], g = color[2], b = color[3] }
  rendering.draw_text({ text = name, surface = surface, target = { entity = e, offset = { 0, -2.3 } }, color = color,
    scale = 0.9, alignment = "center" })
  map_marker(e, name, color)
  local m = { name = name, entity = e, owner = owner, home = { x = at.x, y = at.y }, jobs = {}, color = color,
    voice = i, follow = mode == "follow", roam = mode == "roam" or nil, phase = i * 3, mapped = true }
  crew()[name] = m
  match_owner(m)
  return m
end

local function job_for(m, kind, item, count, extra)
  if kind == "craft" then
    local r = resolve_item(item)
    if not r then return end
    return { kind = "craft", recipe = r, count = math.min(math.max(count or 10, 1), 200) }
  elseif kind == "mine" or kind == "get" or kind == "fetch" then
    local it = resolve_item(item)
    if not it then return end
    count = math.min(math.max(count or 50, 1), 1000)
    if kind == "get" then
      if available(m, it, nil, true) >= count then kind = "fetch"
      elseif nearest_source(m, { item = it, skip = {} }) then kind = "mine"
      elseif handcraft_recipe(m.entity.force, it) then return { kind = "craft", recipe = it, count = math.min(count, 200) }
      else
        local job, why = plan(m, it, count)
        if job then return { kind = "need", item = it, count = count } end
        return { kind = "fetch", item = it, count = count, why = why } -- (what there is; why it can't make more)
      end
    end
    return { kind = kind, item = it, count = count }
  elseif kind == "goal" then
    local use_line = extra and extra.line
    if type(item) == "string" and item:find("%f[%a]line%s*$") then item, use_line = item:gsub("%s*line%s*$", ""), true end
    local it = resolve_item(item)
    if not it then return end
    return { kind = "goal", item = it, count = math.min(math.max(count or 100, 1), 100000), use_line = use_line and true or nil,
      rate = extra and tonumber(extra.rate) }
  elseif kind == "build" or kind == "deconstruct" or kind == "deliver" or kind == "upgrade" then
    return { kind = kind }
  elseif kind == "attack" then
    return { kind = "attack" }
  elseif kind == "follow" or kind == "stay" or kind == "stop" or kind == "roam" then
    return { kind = kind }
  elseif kind == "remember" then
    local text = extra and type(extra.text) == "string" and extra.text or type(item) == "string" and item
    return text and text ~= "" and { kind = "remember", text = text:sub(1, 200), keep_out = extra and extra.keep_out and true } or nil
  end
end

local VERBS = { build = "build", construct = "build", clear = "deconstruct", deconstruct = "deconstruct", upgrade = "upgrade",
  demolish = "deconstruct", remove = "deconstruct", mine = "mine", gather = "get", collect = "get", get = "get",
  fetch = "get", bring = "get", grab = "get", craft = "craft", make = "craft", follow = "follow", come = "follow",
  stay = "stay", wait = "stay", stop = "stop", roam = "roam", wander = "roam", explore = "roam", patrol = "roam", goal = "goal", aim = "goal", attack = "attack", fight = "attack",
  kill = "attack", halt = "stop", cancel = "stop", deliver = "deliver", unload = "deliver" }

-- a plain command ("get 50 iron ore", "build") -> kind, item words, count; nil for anything else
local function parse(text)
  local words = {}
  for w in text:lower():gsub("[%.,!%?]", " "):gmatch("%S+") do words[#words + 1] = w end
  while words[1] == "please" or words[1] == "can" or words[1] == "you" do table.remove(words, 1) end
  local kind = VERBS[words[1] or ""]
  if not kind then return end
  table.remove(words, 1)
  if kind == "build" or kind == "deconstruct" or kind == "stop" or kind == "stay" or kind == "deliver" or kind == "attack" or kind == "upgrade" then
    return #words <= 2 and kind or nil -- "build" / "clear it" / "stop now", nothing longer
  end
  if kind == "follow" or kind == "roam" then return (#words <= 2) and kind or nil end
  local count
  for i, w in ipairs(words) do
    if tonumber(w) then count = tonumber(w) table.remove(words, i) break end
  end
  if words[1] == "me" then table.remove(words, 1) end
  if #words == 0 or #words > 5 then return end
  return kind, table.concat(words, " "), count
end

local add_note -- (with the notes, below)
local function add_job(m, job)
  if job.kind == "attack" then -- (clearing nests: a trip, back where it stood after)
    m.trip_from = { x = m.entity.position.x, y = m.entity.position.y }
  elseif job.kind == "follow" or job.kind == "stay" or job.kind == "stop" or job.kind == "roam" then
    m.trip_from = nil
  elseif not (job.kind == "remember" or job.kind == "need" or job.kind == "goal") then
    -- work (get, mine, craft, build...): back where it stood after, when the player wants that, else stays there
    local back = storage.test_back_after_orders -- (the player's "Back where they stood after orders"; tests set it)
    if back == nil then
      local pl = m.owner and game.get_player(m.owner) or any_player()
      back = pl and player_setting(pl, "ai-crew-back-after-orders") or false
    end
    m.trip_from = back and (m.trip_from or { x = m.entity.position.x, y = m.entity.position.y }) or nil
  end
  if job.kind == "stop" then
    for _, j in pairs(m.jobs) do if j.target and j.target.valid and j.target.unit_number then claims()[j.target.unit_number] = nil end end
    m.jobs, m.visits = {}, nil
    stop_walk(m)
    stop_mining(m)
  elseif job.kind == "follow" then
    m.follow, m.roam = true, nil
  elseif job.kind == "roam" then
    m.follow, m.roam, m.roam_at = false, true, nil
    remember(m.owner, m.name .. " went roaming")
  elseif job.kind == "remember" then
    add_note(m.owner, m, job.text, job.keep_out)
  elseif job.kind == "need" then
    add_need(m.owner, job.item, job.count, "you")
  elseif job.kind == "goal" then
    goals()[m.owner or 0] = { item = job.item, count = job.count, use_line = job.use_line, rate = job.rate }
    m.goal_wait = nil
  elseif job.kind == "stay" then
    m.follow, m.roam = false, nil
    stop_walk(m)
  else
    job.n, job.skip = 0, {}
    -- an order comes before what they took on themselves (auto work, goal steps, fishing): after earlier orders
    local i = 1
    while m.jobs[i] and not (m.jobs[i].auto or m.jobs[i].goal) do i = i + 1 end
    table.insert(m.jobs, i, job)
    if i == 1 and m.jobs[2] then -- (dropping what it was on: stop walking there)
      stop_walk(m)
      stop_mining(m)
    end
  end
end

local function busiest_last(list)
  table.sort(list, function(a, b) return #a.jobs < #b.jobs end)
  return list[1]
end

local function context(player, members)
  local ctx = { crew = {} }
  for _, m in pairs(members) do
    local inv = {}
    for _, it in pairs(m.entity.get_main_inventory().get_contents()) do inv[it.name] = (inv[it.name] or 0) + it.count end
    ctx.crew[#ctx.crew + 1] = { name = m.name, manner = trait(m), queued = #m.jobs, carrying = inv,
      doing = m.jobs[1] and m.jobs[1].kind or (m.roam and "roaming" or m.follow and "following" or "waiting") }
  end
  local recent = {}
  for _, ev in ipairs(storage.events and player and storage.events[player.index] or {}) do
    recent[#recent + 1] = math.floor((game.tick - ev.tick) / 3600) .. " min ago: " .. ev.text
  end
  ctx.recent = recent
  local offer = storage.proposals and player and storage.proposals[player.index]
  ctx.open_offer = offer and ("the crew offered to " .. (offer.use_line and "build a production line for " or ("make " .. offer.count .. " "))
    .. offer.item .. "; if the player agrees, give a goal job for it") or nil
  local c0 = player and player.character
  ctx.notes = {}
  for _, n in ipairs(player and notes(player.index) or {}) do
    ctx.notes[#ctx.notes + 1] = (n.keep_out and "keep out of here: " or "") .. n.text .. string.format(" (at %d, %d%s)", n.pos.x, n.pos.y,
      c0 and string.format("; %d tiles from the player", math.sqrt(dist2(n.pos, c0.position))) or "")
  end
  local c = player and player.character
  if c then
    local inv, n = {}, 0
    for _, it in pairs(c.get_main_inventory().get_contents()) do
      if n < 30 then inv[it.name] = (inv[it.name] or 0) + it.count n = n + 1 end
    end
    ctx.player_inventory = inv
    local s = c.surface
    ctx.ghosts_nearby = s.count_entities_filtered({ type = { "entity-ghost", "tile-ghost" }, force = c.force, position = c.position, radius = RADIUS })
    ctx.marked_for_deconstruction = s.count_entities_filtered({ position = c.position, radius = RADIUS, to_be_deconstructed = true })
    local res = {}
    for _, r in pairs(s.find_entities_filtered({ type = "resource", position = c.position, radius = 64, limit = 400 })) do res[r.name] = true end
    ctx.resources_nearby = {}
    for name in pairs(res) do ctx.resources_nearby[#ctx.resources_nearby + 1] = name end
    local r = c.force.current_research
    ctx.researching = r and r.name
  end
  return ctx
end

local function help(player)
  local msg = "Try: get 50 iron ore, craft 10 gears, mine 20 stone, build, clear, deliver, come, stay, stop."
  if player then player.print(msg) else log(msg) end
end

local function tell(player, text) if player then player.print(text) else log("[ai-crew] " .. text) end end

-- a note where the player stands (home without one); keep: a keep-out zone, drawn on their map
add_note = function(owner, m, text, keep)
  local player = owner and game.get_player(owner)
  local c = player and player.character
  local pos, surface = c and c.position or m.home, c and c.surface or m.entity.surface
  local list = notes(owner)
  local n = { text = text, pos = { x = math.floor(pos.x), y = math.floor(pos.y) }, surface = surface.name, keep_out = keep or nil }
  if keep then
    n.mark = rendering.draw_circle({ color = { 1, 0.3, 0.2, 0.6 }, radius = ZONE, width = 3, filled = false, target = pos,
      surface = surface, render_mode = "chart", players = player and { player } or nil })
  end
  list[#list + 1] = n
  if #list > 30 then
    local old = table.remove(list, 1)
    if old.mark and old.mark.valid then old.mark.destroy() end
  end
end

local KEEP_OUT = { "^keep out", "^stay out", "^don'?t touch", "^hands off", "^leave .*alone" }
local function keep_out_cmd(cmd)
  for _, p in ipairs(KEEP_OUT) do if cmd:find(p) then return true end end
end

-- "remember <anything>", "keep out" (and the like), "forget" (all, a number, here), "notes"
local function note_order(owner, player, m, cmd, rest)
  local list = notes(owner)
  local verb = cmd:match("^(%S+)")
  if verb == "notes" then
    if #list == 0 then return tell(player, "No notes. Try \"remember the north is for iron\", \"keep out\" (here), \"forget\".") end
    for i, n in ipairs(list) do tell(player, string.format("%d. %s%s (at %d, %d)", i, n.keep_out and "[keep out] " or "", n.text, n.pos.x, n.pos.y)) end
    return
  end
  if verb == "forget" then
    local what = cmd:match("^forget%s*(.-)%s*$")
    local c = player and player.character
    local pos = c and c.position or m.home
    local before = #list
    for i = #list, 1, -1 do
      local n = list[i]
      if what == "" or what == "all" or what == "everything" or tonumber(what) == i
        or (what == "here" or what == "this") and dist2(n.pos, pos) <= ZONE * ZONE then
        if n.mark and n.mark.valid then n.mark.destroy() end
        table.remove(list, i)
      end
    end
    return say(m, before > #list and line(m, "noted") or "Nothing to forget.", "talk")
  end
  local keep = keep_out_cmd(cmd)
  local text = keep and rest or rest:gsub("^%S+%s*", "")
  if text == "" then return end
  add_note(owner, m, text, keep)
  say(m, line(m, keep and "keep_out" or "noted"), "talk")
end

-- answers to the crew's offer (proposals, below)
local YES = { yes = true, yeah = true, yep = true, y = true, sure = true, ok = true, okay = true, ["do it"] = true, please = true,
  ["go ahead"] = true, ["go for it"] = true, ["yes please"] = true, ["sounds good"] = true }
local NO = { no = true, nope = true, nah = true, n = true, ["no thanks"] = true, ["not now"] = true, later = true }
local function answer_of(cmd) return (cmd:lower():gsub("[%.!,]", ""):gsub("^%s+", ""):gsub("%s+$", "")) end

-- one order: "crew <what>" for everyone, "<Name> <what>" for one member
local function order(owner, text)
  local player = owner and game.get_player(owner)
  local who, rest = text:match("^(%S+)%s*(.*)$")
  if not who then return end
  local lw, cmd = who:lower(), rest:lower()
  local all = lw == "crew" or lw == "all" or lw == "everyone"
  local members
  if all then members = members_of(owner) else
    local m = find_member(who, owner)
    if not m then return tell(player, "No crew member called " .. who .. ".") end
    members = { m }
  end
  local offer = storage.proposals and storage.proposals[owner or 0]
  local ans = answer_of(cmd)
  if offer and #members > 0 and (YES[ans] or NO[ans]) then
    storage.proposals[owner or 0] = nil
    local m = members[1]
    if YES[ans] then
      goals()[owner or 0] = { item = offer.item, count = offer.count, use_line = offer.use_line, rate = offer.rate }
      for _, o in pairs(members_of(owner)) do o.goal_wait = nil end
      remember(owner, "the player agreed: goal " .. offer.count .. " " .. pretty(offer.item) .. (offer.use_line and " with a line" or ""))
      return say(m, line(m, "ack"), "talk")
    end
    storage.declined = storage.declined or {}
    storage.declined[owner or 0] = storage.declined[owner or 0] or {}
    storage.declined[owner or 0][offer.item] = game.tick
    remember(owner, "the player said no to doing something about " .. pretty(offer.item))
    return say(m, line(m, "declined"), "talk")
  end
  -- management
  local verb, arg = cmd:match("^(%S+)%s*(%S*)")
  if all and (verb == "hire" or verb == "recruit") then
    if #members >= MAX_CREW then return tell(player, "The crew is full (" .. MAX_CREW .. ").") end
    local c = player and player.character
    if not c then return tell(player, "Stand somewhere first: crew members spawn next to your character.") end
    local name = rest:match("^%S+%s+(%S+)")
    local m, err = hire(name and (name:sub(1, 1):upper() .. name:sub(2)), c.surface, c.position, c.force, owner)
    if not m then return tell(player, err) end
    ada("hired", { name = m.name })
    remember(owner, m.name .. " joined the crew")
    return say(m, line(m, "hello"), "talk")
  elseif all and (verb == "fire" or verb == "dismiss") then
    local m = find_member(arg, owner)
    if not m then return tell(player, "No crew member called " .. arg .. ".") end
    say(m, line(m, "bye"), "talk")
    unload(m)
    if m.entity.valid then m.entity.destroy() end
    crew()[m.name] = nil
    return
  elseif all and (verb == "list" or verb == "status") or verb == "status" then
    if #members == 0 then return tell(player, "No crew yet: press Hire in the crew window.") end
    for _, m in pairs(members) do
      tell(player, m.name .. ": " .. (m.jobs[1] and m.jobs[1].kind or (m.roam and "roaming" or m.follow and "following" or "waiting")) ..
        (#m.jobs > 1 and (" (+" .. (#m.jobs - 1) .. " queued)") or ""))
    end
    return
  elseif verb == "auto" then
    for _, m in pairs(members) do m.auto = arg ~= "off" end
    return tell(player, (arg ~= "off" and "Auto build and clear on" or "Auto build and clear off: only on orders") ..
      " for " .. (all and "the crew" or members[1].name) .. ".")
  elseif verb == "help" or cmd == "" then
    return help(player)
  elseif #members > 0 and (verb == "remember" or verb == "note" or verb == "notes" or verb == "forget" or keep_out_cmd(cmd)) then
    return note_order(owner, player, members[1], cmd, rest)
  end
  if #members == 0 then return tell(player, "No crew yet: press Hire in the crew window.") end
  -- plain commands run without the LLM
  local kind, item, count = parse(rest)
  if kind then
    local targets = members
    if not (kind == "build" or kind == "deconstruct" or kind == "stop" or kind == "follow" or kind == "roam" or kind == "stay" or kind == "deliver" or kind == "attack" or kind == "upgrade") then
      targets = { busiest_last(members) }
    end
    for i, m in ipairs(targets) do
      local job = job_for(m, kind, item, count)
      if not job then return tell(player, "I don't know an item called \"" .. tostring(item) .. "\".") end
      add_job(m, job)
      m.wait_until = game.tick + math.random(20, 60) -- (a moment to take it in, as anyone would)
      if i == 1 then say(m, ACKS[job.kind] and math.random() < 0.5 and pick(ACKS[job.kind]) or line(m, job.kind == "roam" and "roam" or "ack")) end
    end
    return
  end
  -- anything else: the LLM
  local llm = llm_settings(player)
  if not py() or llm.provider == "off" then
    tell(player, "I only understand simple orders without the fse loader and an AI provider.")
    return help(player)
  end
  local names = {}
  for _, m in pairs(members) do names[#names + 1] = m.name end
  jobs.start(owner, "aicrew:ask", helpers.table_to_json({ message = rest, to = names, llm = llm,
    context = context(player, members_of(owner)) }), { kind = "ask", owner = owner, to = names })
  for _, m in pairs(members) do
    if m.bubble and m.bubble.valid then m.bubble.destroy() end
    m.bubble = rendering.draw_text({ text = "...", surface = m.entity.surface, target = { entity = m.entity, offset = { 0, -2.9 } },
      color = m.color, scale = 1.4, alignment = "center", time_to_live = 600 })
  end
end

-- normal chat (T), as you'd talk to another player: a message starting with a crew member's name ("Rook, get coal")
-- goes to them, "crew ..." (all, everyone, guys, team) to everyone, a name later on ("thanks Rook") to that one. With
-- nobody else in the game, anything else goes to whoever is nearest (when it's an order, or there's an AI to answer)
local CALL_ALL = { crew = true, all = true, everyone = true, guys = true, team = true }
local function hear(owner, text)
  local members = members_of(owner)
  if #members == 0 or text:sub(1, 1) == "/" then return end
  local first, rest = text:match("^%s*([%w]+)[,:!]?%s*(.*)$")
  if not first then return end
  if rest == "" then rest = text end
  if CALL_ALL[first:lower()] then return order(owner, "crew " .. rest) end
  if find_member(first, owner) then return order(owner, first .. " " .. rest) end
  local low = text:lower()
  for _, m in pairs(members) do
    if low:find("%f[%a]" .. m.name:lower() .. "%f[%A]") then return order(owner, m.name .. " " .. text) end
  end
  if #game.connected_players > 1 then return end
  local player = owner and game.get_player(owner)
  local llm = llm_settings(player)
  local word = low:match("^%s*(%S+)")
  local meant = parse(text) or keep_out_cmd(low) or word == "remember" or word == "forget" or word == "notes"
    or storage.proposals and storage.proposals[owner or 0] and (YES[answer_of(text)] or NO[answer_of(text)])
  if not (meant or py() and llm.provider ~= "off") then return end
  local c = player and player.character
  if c then table.sort(members, function(a, b) return dist2(a.entity.position, c.position) < dist2(b.entity.position, c.position) end) end
  order(owner, members[1].name .. " " .. text)
end

-- ------------------------------------------------------------------------------------------------------------- shared
-- what the other files use of this one, and its link: control.lua calls it once all files are loaded
return {
  share = { add_job = add_job, context = context, find_member = find_member, hear = hear, hire = hire,
    job_for = job_for, map_marker = map_marker, match_owner = match_owner, members_of = members_of, order = order,
    tell = tell },
  link = function(A)
    ACKS, ada, add_need, any_player, available, claims = A.ACKS, A.ada, A.add_need, A.any_player, A.available, A.claims
    COLORS, CREW, crew, dist2, goals, handcraft_recipe = A.COLORS, A.CREW, A.crew, A.dist2, A.goals, A.handcraft_recipe
    jobs, line, llm_settings, MAX_CREW, NAMES = A.jobs, A.line, A.llm_settings, A.MAX_CREW, A.NAMES
    nearest_source, notes, pick, plan, player_setting = A.nearest_source, A.notes, A.pick, A.plan, A.player_setting
    pretty, py, RADIUS, remember, resolve_item, say = A.pretty, A.py, A.RADIUS, A.remember, A.resolve_item, A.say
    stop_mining, stop_walk, trait, unload, ZONE = A.stop_mining, A.stop_walk, A.trait, A.unload, A.ZONE
  end,
}
