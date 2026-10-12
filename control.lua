-- AI Crew: helper characters that build, clear, mine, hand-craft and fetch, run from a panel (the crew button, top left).
-- Idle, each one works like a construction bot near you: clears deconstruction marks, then places ghosts, hand-crafting
-- what it can't take from your pockets or nearby chests. Orders: get / mine / craft an item, build, clear, deliver,
-- follow, stay, stop. The panel's chat box goes to an LLM through the fse loader (aicrew.py), which answers in
-- character and may queue the same jobs; plain orders typed there ("get 50 iron ore") run without it.
--
-- remote.call("ai-crew", ...): hire(name, surface, position, force?, owner_index?, mode?), order(owner_index, text),
-- status(name)

local D = defines.direction
local DIRS = { D.north, D.northeast, D.east, D.southeast, D.south, D.southwest, D.west, D.northwest }
local NAMES = { "Rook", "Mara", "Juno", "Bolt", "Pip", "Sable", "Tess", "Orin" }
local COLORS = { { 1, 0.55, 0.2 }, { 0.3, 0.8, 1 }, { 0.6, 1, 0.4 }, { 1, 0.4, 0.7 }, { 1, 0.9, 0.3 }, { 0.7, 0.5, 1 },
  { 0.4, 1, 0.9 }, { 1, 0.6, 0.5 } }
local ADA_COLOR = "1,0.62,0.2"
local RADIUS = 48 -- the work area around the owner (or home)
local MAX_CREW = 4
-- the crew's own body (data-final-fixes.lua): the same character, half as wide and shorter, so they fit where a
-- player does not
local CREW = "crew-character"
local ALIASES = { gear = "iron-gear-wheel", gears = "iron-gear-wheel", belt = "transport-belt", belts = "transport-belt",
  ["green-circuit"] = "electronic-circuit", ["green-circuits"] = "electronic-circuit", circuit = "electronic-circuit",
  circuits = "electronic-circuit", ["red-circuit"] = "advanced-circuit", ["red-circuits"] = "advanced-circuit",
  ["blue-circuit"] = "processing-unit", ["blue-circuits"] = "processing-unit", pipe = "pipe", pipes = "pipe",
  furnace = "stone-furnace", furnaces = "stone-furnace", drill = "burner-mining-drill", drills = "burner-mining-drill",
  pole = "small-electric-pole", poles = "small-electric-pole", ammo = "firearm-magazine", bricks = "stone-brick" }
local ACKS = { build = { "On it.", "Building.", "Let's get it up." }, deconstruct = { "Clearing it.", "Tearing it down." },
  mine = { "Heading out to mine.", "Pickaxe ready." }, craft = { "Crafting.", "Coming right up." },
  fetch = { "I'll grab it.", "Fetching." }, deliver = { "Bringing it over." }, follow = { "Right behind you." },
  stay = { "Holding here." }, stop = { "Stopping." }, goal = { "New goal. We're on it.", "Got it, working towards that." },
  need = { "None to hand. I'll work for it.", "We'll have to make some. On it." },
  attack = { "Locked and loaded.", "Let's clear them out.", "Time to burn some nests." },
  upgrade = { "Upgrading.", "Swapping them out." } }

-- each one's manner: picks their stock lines, and the AI is told it (aicrew.py has the same names)
local TRAITS = { Rook = "gruff", Mara = "upbeat", Juno = "precise", Bolt = "eager", Pip = "cheerful", Sable = "laconic",
  Tess = "precise", Orin = "gruff" }
local TRAIT_ORDER = { "gruff", "upbeat", "precise", "eager", "cheerful", "laconic" }
-- stock lines by event, then manner (lines.lua)
local LINES = require("lines")
local ROAM = 40 -- roaming: how far from the player (or home) they wander

-- ---------------------------------------------------------------------------------------------------------------- util

local function crew_built(e) -- (machines the crew put down: theirs to use)
  for _, b in pairs(storage.crew_built or {}) do if b == e then return true end end
  return false
end
local delayed = {} -- (tests: path answers held back, as a busy pathfinder in a big base would)
local path_finished -- (with the events)

local function crew()
  storage.crew = storage.crew or {}
  return storage.crew
end

local function dist2(a, b)
  local dx, dy = a.x - b.x, a.y - b.y
  return dx * dx + dy * dy
end

local function pick(list) return list[math.random(#list)] end

local function pretty(name) return (name:gsub("-", " ")) end
local function a_an(name) return (pretty(name):match("^[aeiou]") and "an " or "a ") .. pretty(name) end

-- -------------------------------------------------------------------------------------------------------------- files
-- The rest is in files of their own (voice, plan, move, work, fight, roam, orders, window: .lua). Each keeps its
-- functions local and gets what it uses of the others' as locals too, set by its link once all are loaded: a call
-- across files costs what one within a file does, and no file depends on the order they load in. A: all that's
-- shared, by name (control.lua's own, then each file's share); JOBS: every file's jobs.
local A = { a_an = a_an, ACKS = ACKS, ADA_COLOR = ADA_COLOR, ALIASES = ALIASES, COLORS = COLORS, CREW = CREW,
  crew = crew, crew_built = crew_built, D = D, DIRS = DIRS, dist2 = dist2, LINES = LINES, MAX_CREW = MAX_CREW,
  NAMES = NAMES, pick = pick, pretty = pretty, RADIUS = RADIUS, ROAM = ROAM, TRAIT_ORDER = TRAIT_ORDER,
  TRAITS = TRAITS }
local JOBS = {} -- kind -> function(m, job): true when done (work.lua's, plan.lua's, fight.lua's)
local FILES = { require("voice"), require("plan"), require("move"), require("work"), require("fight"), require("roam"),
  require("orders"), require("window") }
for _, f in ipairs(FILES) do
  for k, v in pairs(f.share) do A[k] = v end
  for k, v in pairs(f.JOBS or {}) do JOBS[k] = v end
end
for _, f in ipairs(FILES) do f.link(A) end
local act, ada, add_button, add_need, ai_state, alarm = A.act, A.ada, A.add_button, A.add_need, A.ai_state, A.alarm
local anchor, any_player, available, build_panel = A.anchor, A.any_player, A.available, A.build_panel
local chatter, check_ai, face, fight, find_member = A.chatter, A.check_ai, A.face, A.fight, A.find_member
local flight, fly, forget_caches, fstd, fuel_available = A.flight, A.fly, A.forget_caches, A.fstd, A.fuel_available
local go, goal_step, goals, gun_range, hear, hint = A.go, A.goal_step, A.goals, A.gun_range, A.hear, A.hint
local hire, hover, JET, jobs, line, llm_settings = A.hire, A.hover, A.JET, A.jobs, A.line, A.llm_settings
local low_burners, map_marker, members_of, mod_gui = A.low_burners, A.map_marker, A.members_of, A.mod_gui
local nearest_source, open_frame, order, owner_char = A.nearest_source, A.open_frame, A.order, A.owner_char
local plan, player_setting, players_stuff, progress = A.plan, A.player_setting, A.players_stuff, A.progress
local propose, py, queued, react, refresh, riding = A.propose, A.py, A.queued, A.react, A.refresh, A.riding
local roam, say, spot, stop_mining, theme, ui, walk = A.roam, A.say, A.spot, A.stop_mining, A.theme, A.ui, A.walk

-- -------------------------------------------------------------------------------------------------------------- think

-- with nothing queued: like a construction bot (marks, then ghosts near the owner), then the goal, then follow
local function idle(m)
  if game.tick >= (m.next_scan or 0) then
    m.next_scan = game.tick + 120
    if m.auto ~= false and game.tick >= (m.auto_wait or 0) then
      local e = m.entity
      local area = { position = anchor(m), radius = RADIUS, limit = 1, to_be_deconstructed = true }
      local kind
      if e.surface.count_entities_filtered(area) > 0 then kind = "deconstruct" end
      area.to_be_deconstructed, area.to_be_upgraded, area.force = nil, true, e.force
      if not kind and e.surface.count_entities_filtered(area) > 0 then kind = "upgrade" end
      local at
      if not kind and m.roam then -- (roaming: the marks round where it is too, out past the work area)
        area.position = e.position
        if e.surface.count_entities_filtered(area) > 0 then
          kind, at = "upgrade", { x = e.position.x, y = e.position.y }
        end
        area.position = anchor(m)
      end
      area.to_be_upgraded, area.type = nil, { "entity-ghost", "tile-ghost" }
      if not kind and e.surface.count_entities_filtered(area) > 0 then kind = "build" end
      if kind then
        m.jobs[1] = { kind = kind, auto = true, n = 0, skip = {}, at = at }
        return
      end
    end
    if game.tick >= (m.tend_at or 0) then
      m.tend_at = game.tick + 600
      if #low_burners(m, 1) > 0 then
        if fuel_available(m) then
          m.jobs[1] = { kind = "tend", auto = true, n = 0, skip = {} }
          return
        end
        -- burners running dry and no fuel anywhere: go and get some (coal, else wood), then fuel them
        local item = game.tick >= (m.fuel_hunt or 0) and (nearest_source(m, { item = "coal", skip = {} }) and "coal" or "wood")
        m.fuel_hunt = item and game.tick + 18000 or m.fuel_hunt -- (one try every 5 minutes)
        if item and add_need(m.owner, item, 20, "the burners", { kind = "tend", auto = true }) then
          say(m, "The burners are running dry and we're out of fuel. Getting some " .. pretty(item) .. ".")
        end
      end
    end
    -- no fish to heal with: go fishing (fighters only, every 30 s at most)
    if m.defend ~= false and prototypes.item["raw-fish"] and game.tick >= (m.fish_wait or 0) then
      m.fish_wait = game.tick + 1800
      local e = m.entity
      if e.get_main_inventory().get_item_count("raw-fish") + available(m, "raw-fish") < 5
        and e.surface.count_entities_filtered({ type = "fish", position = e.position, radius = 250, limit = 1 }) > 0 then
        say(m, line(m, "fishing"))
        m.jobs[1] = { kind = "fish", count = 20, auto = true, n = 0, skip = {} }
        return
      end
    end
    if goal_step(m) then return end
    local at = m.trip_from -- (nothing more to do: back from a trip)
    m.trip_from = nil
    if at and not (m.roam or m.follow and owner_char(m)) and dist2(m.entity.position, at) > 16 * 16 then
      m.jobs[1] = { kind = "back", at = at }
      return
    end
  end
  if not m.move and game.tick >= (m.glance_at or 0) then -- standing about: look round now and then, mostly at you
    m.glance_at = game.tick + math.random(240, 600)
    local c, p = owner_char(m), m.entity.position
    face(m, c and math.random() < 0.6 and c.position or { x = p.x + math.random(-5, 5), y = p.y + math.random(-5, 5) })
  end
  if m.roam then return roam(m) end
  if not m.follow then return end
  local c = owner_char(m)
  if c and dist2(m.entity.position, spot(m, c.position)) > 16 and dist2(m.entity.position, c.position) > 25 then
    go(m, spot(m, c.position), 1.5)
  end
end

local function think(m)
  if game.tick < (m.wait_until or 0) then return end -- (a moment's pause: reacting, putting something down)
  local v = m.visits and m.visits[1] -- a place it took something from: over there first, a moment at it
  if v then
    if not v.valid or go(m, v.position, math.max(m.entity.reach_distance - 2, 2)) then
      table.remove(m.visits, 1)
      if v.valid then
        face(m, v.position)
        m.wait_until = game.tick + math.random(10, 20)
      end
    end
    return
  end
  local job = m.jobs[1]
  if not job then
    idle(m)
    local j = m.jobs[1]
    if j and (j.auto or j.goal) and not m.trip_from then m.trip_from = { x = m.entity.position.x, y = m.entity.position.y } end
    return
  end
  if job.kind ~= "mine" and m.mining then stop_mining(m) end
  local ok, done = pcall(JOBS[job.kind], m, job)
  if not ok then
    log("[ai-crew] " .. m.name .. " " .. job.kind .. ": " .. tostring(done))
    done = true
  end
  if done then
    for i, j in ipairs(m.jobs) do if j == job then table.remove(m.jobs, i) break end end
    if job.goal and (job.n or 0) == 0 then m.goal_wait = game.tick + 600 end -- a goal step that got nowhere: wait
  end
end

-- ------------------------------------------------------------------------------------------------------- milestones

local SCIENCE
local function science_check(silent)
  local f = game.forces.player
  if not f then return end
  if not SCIENCE then
    SCIENCE = {}
    for name in pairs(prototypes.get_item_filtered({ { filter = "type", type = "tool" } })) do SCIENCE[#SCIENCE + 1] = name end
  end
  storage.seen = storage.seen or {}
  for _, s in pairs(game.surfaces) do
    local stats = f.get_item_production_statistics(s).input_counts
    for _, name in ipairs(SCIENCE) do
      if not storage.seen[name] and (stats[name] or 0) > 0 then
        storage.seen[name] = true
        if not silent then ada("first", { item = pretty(name) }) end
      end
    end
  end
end

-- ----------------------------------------------------------------------------------------------------------- events

local function init()
  crew()
  storage.paths, storage.claims = storage.paths or {}, storage.claims or {}
  if not storage.seen then science_check(true) end
  -- (0.3.1 could crowd the player's base with the crew's machines: empty ones too close to it get taken down)
  for _, b in pairs(storage.crew_built or {}) do
    if b.valid and not b.to_be_deconstructed() then
      local bb = b.bounding_box
      local area = { { bb.left_top.x - 3, bb.left_top.y - 3 }, { bb.right_bottom.x + 3, bb.right_bottom.y + 3 } }
      local empty = true
      for _, i in ipairs({ 1, 2, 3, 4 }) do
        local inv = b.get_inventory(i)
        if inv and not inv.is_empty() then empty = false end
      end
      if empty and players_stuff(b.surface, b.force, area) then b.order_deconstruction(b.force) end
    end
  end
  if storage.map_v ~= 2 then -- (map markers drawn again: the first ones' names grew huge when zoomed out)
    for _, o in pairs(rendering.get_all_objects(script.mod_name)) do
      if o.valid and o.render_mode == "chart" then o.destroy() end
    end
    for _, m in pairs(crew()) do m.mapped = nil end
    storage.map_v = 2
  end
  for _, m in pairs(crew()) do
    if m.entity and m.entity.valid and not m.mapped then map_marker(m.entity, m.name, m.color) end
    m.mapped = true
  end
  for _, p in pairs(game.players) do
    add_button(p)
    local old = mod_gui.get_frame_flow(p).aic_panel -- (0.1's panel)
    if old then old.destroy() end
  end
end
script.on_init(init)

-- standing still on a ghost that construction robots can reach (their body would block it): step off it
local function yield_to_bots(m)
  local e = m.entity
  local s, pos = e.surface, e.position
  local function on_ghost(p)
    for _, g in pairs(s.find_entities_filtered({ type = "entity-ghost", force = e.force, position = p, radius = 4 })) do
      local b = g.bounding_box
      if p.x > b.left_top.x - 0.3 and p.x < b.right_bottom.x + 0.3 and p.y > b.left_top.y - 0.3 and p.y < b.right_bottom.y + 0.3 then
        return g
      end
    end
  end
  local g = on_ghost(pos)
  if not g or #s.find_logistic_networks_by_construction_area(pos, e.force) == 0 then return end
  for r = 1, 6 do
    for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
      local to = s.find_non_colliding_position(CREW, { x = pos.x + d[1] * r, y = pos.y + d[2] * r }, 0.5, 0.25)
      if to and not on_ghost(to) then e.teleport(to) return end
    end
  end
end

-- you put something down where a crew member stands (their body would block it): they step aside first
script.on_event(defines.events.on_pre_build, function(ev)
  local player = game.get_player(ev.player_index)
  if not player then return end
  for _, m in pairs(crew()) do
    local e = m.entity
    if e.valid and e.surface == player.surface and dist2(e.position, ev.position) < 9 then
      local to = e.surface.find_non_colliding_position(CREW, { x = e.position.x + (e.position.x >= ev.position.x and 3 or -3),
        y = e.position.y }, 6, 0.5)
      if to and dist2(to, ev.position) >= 6 then e.teleport(to) end
    end
  end
end)
script.on_configuration_changed(function() forget_caches() init() end)

-- normal chat (T): to the crew (orders.lua's hear)
script.on_event(defines.events.on_console_chat, function(ev)
  if ev.player_index and ev.message then hear(ev.player_index, ev.message) end
end)

-- an AI job's answer, from the peer that ran it (multiplayer)
if script.active_mods["fse-std"] then
  script.on_event("fse-sync", function(e)
    if e.key ~= "ai-crew:answer" then return end
    local d = helpers.json_to_table(e.data)
    if d and d.n then jobs.answered(d.n, d.st, d.out) end
  end)
end

script.on_event(defines.events.on_tick, function(ev)
  local t = ev.tick
  if not jobs.checked and t % 60 == 0 and not game.is_multiplayer() then -- (once a session, a second in: the
    jobs.checked = true                                                    -- AI tested for whoever is playing)
    storage.ai = nil -- (before 0.8.0)
    storage.ai_tests = {} -- (the last session's results say nothing about now)
    for _, p in pairs(game.connected_players) do if py() and llm_settings(p).provider ~= "off" then check_ai(p) end end
  end
  if not jobs.warmed then -- (once a session, on this peer: Kokoro loaded now, not on the first line; no game state)
    jobs.warmed = true
    local p = py() and (game.is_multiplayer() and native.local_player and native.local_player()
      and game.get_player(native.local_player()) or not game.is_multiplayer() and any_player())
    if p and (player_setting(p, "ai-crew-voices") or player_setting(p, "ai-crew-ada")) then
      pcall(native.call, "py", "aicrew:warm", "{}")
    end
  end
  for name, m in pairs(crew()) do
    local e = m.entity
    if not (e and e.valid) then
      crew()[name] = nil
    else
      if m.drop_at then
        if not e.vehicle then e.teleport(m.drop_at) end
        m.drop_at = nil
      end
      if m.ride then riding(m) end
      if m.ride and e.vehicle then -- (driving or riding: nothing else moves them)
      elseif m.fly then flight(m) elseif m.move then walk(m) end
      if m.mining then
        e.update_selected_entity(m.mining)
        e.mining_state = { mining = true, position = m.mining }
      end
      if m.target then
        if m.target.valid then
          e.shooting_state = { state = defines.shooting.shooting_enemies, position = m.target.position }
        else
          m.target = nil
          e.shooting_state = { state = defines.shooting.not_shooting, position = e.position }
        end
      end
      local war = m.jobs[1] and (m.jobs[1].kind == "attack" or m.jobs[1].kind == "defend")
      if (t + m.phase) % (war and 15 or 30) == 0 then fight(m) end
      if (t + m.phase) % 10 == 0 and not m.fly and (not m.move or (war and (t + m.phase) % 60 == 0)) and not m.retreat then think(m) end
      if m.retreat and not m.move and (t + m.phase) % 60 == 0 then go(m, anchor(m), 4) end
      if (t + m.phase) % 30 == 7 and not m.move and not e.vehicle then yield_to_bots(m) end
    end
  end
  if t % 5 == 0 and next(jobs.running) then
    for id, n in pairs(jobs.running) do
      local st, out = native.poll(id)
      if st ~= "pending" then
        jobs.running[id] = nil
        jobs.deliver(n, st, out)
      end
    end
  end
  if t % 600 == 0 and storage.jobs then -- (a job whose peer left, or never answered)
    for n, p in pairs(storage.jobs) do if t - p.at > 18000 then storage.jobs[n] = nil end end
  end
  if t % 30 == 0 then
    for _, p in pairs(game.connected_players) do
      refresh(p)
      if p.gui.screen.aic_card or hover.shown[p.index] then hover.show(p, hover.member_of(p.selected)) end -- (kept current)
    end
    local lines = queued()
    for i = #lines, 1, -1 do
      local l = lines[i]
      if t >= l.at then
        table.remove(lines, i)
        local m = find_member(l.who, l.owner)
        if m then say(m, l.text, "talk", l.pos) end
      end
    end
  end
  if t % 60 == 0 then -- back at the keyboard after a while away: someone says hello
    storage.away = storage.away or {}
    for _, p in pairs(game.connected_players) do
      if p.afk_time > 7200 then storage.away[p.index] = true
      elseif storage.away[p.index] and p.afk_time < 120 then
        storage.away[p.index] = nil
        local members = members_of(p.index)
        if #members > 0 then
          local m = pick(members)
          say(m, line(m, "welcome"), "talk")
        end
      end
    end
  end
  if t % 600 == 300 then -- hints, for players at the keyboard who want them
    for _, p in pairs(game.connected_players) do
      if p.afk_time < 3600 and player_setting(p, "ai-crew-hints") ~= false then hint(p.index) end
    end
  end
  if t % 600 == 0 then -- offers: a new one every 10 minutes you're at the keyboard, an old one lapsing after 5
    storage.propose_at = storage.propose_at or {}
    for k, o in pairs(storage.proposals or {}) do if t - o.at > 18000 then storage.proposals[k] = nil end end
    for _, p in pairs(game.connected_players) do
      if p.afk_time < 3600 and t >= (storage.propose_at[p.index] or 36000) then
        storage.propose_at[p.index] = t + 36000
        propose(p.index)
      end
    end
  end
  if t % 600 == 0 then
    storage.chat_at = storage.chat_at or {}
    for _, p in pairs(game.connected_players) do
      if p.afk_time > 7200 and t >= (storage.chat_at[p.index] or 0) and player_setting(p, "ai-crew-chatter") then
        storage.chat_at[p.index] = t + math.random(3600, 7200)
        chatter(p)
      end
    end
  end
  if t % 600 == 0 then science_check(false) end
  for k = #delayed, 1, -1 do
    if t >= delayed[k].at then path_finished(table.remove(delayed, k).ev) end
  end
  if t % 300 == 0 and storage.fallen then
    for name, f in pairs(storage.fallen) do
      if t >= f.at and game.get_surface(f.surface) then
        storage.fallen[name] = nil
        local m = hire(name, game.get_surface(f.surface), f.home, f.force, f.owner)
        if m then
          m.auto, m.defend, m.follow = f.auto, f.defend, f.follow
          m.roam = f.roam
          for k, v in pairs(f.stats or {}) do m[k] = v end
          say(m, line(m, "back"))
        end
      end
    end
  end
  if storage.queue_check and t >= storage.queue_check then
    storage.queue_check = nil
    local f = game.forces.player
    if f and not f.current_research and #f.research_queue == 0 then ada("queue_empty") end
  end
end)


path_finished = function(ev)
  if storage.path_delay and not ev.delayed then
    delayed[#delayed + 1] = { at = game.tick + storage.path_delay, ev = { id = ev.id, path = ev.path, try_again_later = ev.try_again_later,
      tick = ev.tick, delayed = true } }
    return
  end
  local name = storage.paths and storage.paths[ev.id]
  if not name then return end
  storage.paths[ev.id] = nil
  local m = crew()[name]
  if m and m.ride and m.ride.path_id == ev.id then -- (a route for the car)
    if ev.path then m.ride.path, m.ride.i = ev.path, 1
    elseif ev.try_again_later then m.ride.repath = true
    else m.ride.failed = true end
    return
  end
  if not (m and m.move) then return end
  if ev.path then
    m.move.path, m.move.i, m.move.straight, m.move.closest, m.move.closest_at = ev.path, 1, nil, nil, nil
    -- a long way round something they could fly over: fly
    local len, prev = 0, m.entity.position
    for _, wp in ipairs(ev.path) do len, prev = len + math.sqrt(dist2(prev, wp.position)), wp.position end
    local straight = math.sqrt(dist2(m.entity.position, m.move.goal))
    if straight <= JET and len > straight * 2.5 + 8 then fly(m, m.move.goal) end
  elseif ev.try_again_later then
    m.move.retry = ev.tick + 30
  else
    -- no path: fly over, else straight at it, and walk()'s step-through covers whatever that runs into
    m.move.path, m.move.i, m.move.straight = { { position = m.move.goal } }, 1, true
    fly(m, m.move.goal)
  end
end
script.on_event(defines.events.on_script_path_request_finished, path_finished)

-- your buildings hit by an enemy: the crew nearby come to defend them (once every 2 s per place); you hit: they come
-- to you (a crew member hit is its own fight)
script.on_event(defines.events.on_entity_damaged, function(ev)
  local ent, by = ev.entity, ev.force
  if not (by and ent.valid and ent.force.is_enemy(by)) then return end
  local who = ent.type == "character" and ent
  if who and not (ent.name ~= CREW and (ent.player or storage.test_char == ent)) then return end
  storage.attacks = storage.attacks or {}
  local k = ent.surface.index
  local a = storage.attacks[k]
  if a and game.tick - a.tick < 120 and dist2(a.pos, ent.position) < 32 * 32 then return end
  storage.attacks[k] = { pos = ent.position, tick = game.tick }
  alarm(ent.surface, ent.force, ent, who or nil)
end, (function()
  local f = {}
  for _, t in ipairs({ "unit", "unit-spawner", "turret", "tree", "simple-entity", "fish" }) do
    f[#f + 1] = { filter = "type", type = t, invert = true, mode = "and" }
  end
  return f
end)())

-- what counts as progress (no "nothing done" hint while there's some): building, crafting, research
script.on_event({ defines.events.on_built_entity, defines.events.on_player_crafted_item }, function(ev) progress(ev.player_index) end)

script.on_event(defines.events.on_research_finished, function(ev)
  for _, p in pairs(ev.research.force.players) do progress(p.index) end
  if ev.by_script then return end
  ada("research", { item = pretty(ev.research.name) })
  for _, p in pairs(ev.research.force.connected_players) do
    react(p.index, "research", "research done: " .. pretty(ev.research.name), { item = pretty(ev.research.name) })
  end
  storage.queue_check = ev.tick + 60
end)

script.on_event(defines.events.on_rocket_launched, function()
  ada("rocket")
end)

script.on_event(defines.events.on_player_died, function()
  ada("died")
end)

script.on_event(defines.events.on_entity_died, function(ev)
  local cause = ev.cause
  if cause and cause.valid and cause.name == CREW and ev.entity.type ~= "character" then -- (an enemy one of them killed)
    for _, m in pairs(crew()) do if m.entity == cause then m.kills = (m.kills or 0) + 1 end end
    return
  end
  if ev.entity.type ~= "character" then return end
  for name, m in pairs(crew()) do
    if m.entity == ev.entity then
      crew()[name] = nil
      storage.fallen = storage.fallen or {}
      storage.fallen[name] = { at = ev.tick + 3600, owner = m.owner, home = m.home, surface = m.entity.surface.name,
        force = m.entity.force.name, auto = m.auto, defend = m.defend, follow = m.follow, roam = m.roam,
        stats = { kills = m.kills, built = m.built, deaths = (m.deaths or 0) + 1, rides = m.rides, flights = m.flights } }
      ada("crew_down", { name = name, at = m.entity.position, surface = m.entity.surface.name })
      react(m.owner, "down", name .. " was killed" .. (ev.cause and ev.cause.valid and (" by a " .. pretty(ev.cause.name)) or ""),
        { other = name }, name)
    end
  end
end, { { filter = "type", type = "character" }, { filter = "type", type = "unit" }, { filter = "type", type = "unit-spawner" },
  { filter = "type", type = "turret" } })

remote.add_interface("ai-crew", {
  hire = function(name, surface, position, force, owner, mode) -- (mode: follow unless given, as before the setting)
    local m, err = hire(name, game.get_surface(surface) or surface, position, force or "player", owner, mode or "follow")
    if not m then error(err) end
    return m.name
  end,
  order = function(owner, text) order(owner, text) end,
  -- (tests) a line typed in normal chat
  hear = function(owner, text) hear(owner, text) end,
  -- (tests) path answers held back n ticks, as a busy pathfinder would
  test_path_delay = function(n) storage.path_delay = n end,
  test_machines = function(on) storage.test_machines = on end, -- (tests: "Crew build machines", for want of a player)
  test_back_after_orders = function(on) storage.test_back_after_orders = on end, -- (tests: "Back where they stood...")
  test_tiers = function(on) storage.test_tiers = on end, -- (tests: "Crew upgrade to better tiers")
  test_char = function(c) storage.test_char = c end, -- (tests: a character standing in for the player's, when hit)
  -- (tests) plan()'s next job for n of item, no far search skipped; its kind, or why none
  test_plan = function(name, item, n)
    local m = crew()[name]
    m.far_skip = nil
    local job, why = plan(m, item, n)
    return job and job.kind or why
  end,
  -- (tests) a button of the window pressed
  -- (tests) a button's action; as_player: as the player's own click (Fire asks first)
  press = function(player_index, action, who, as_player) act(game.get_player(player_index), action, who, not as_player) end,
  ai_status = function(player_index) return ai_state()[player_index] end,
  -- what the crew remember lately (the AI gets it): {tick, text}, oldest first
  memory = function(owner) return storage.events and storage.events[owner or 0] end,
  notes = function(owner) return storage.notes and storage.notes[owner or 0] end,
  -- (tests) an offer made now; the goal
  propose = function(owner) propose(owner) return storage.proposals and storage.proposals[owner or 0] end,
  goal = function(owner) return storage.goals and storage.goals[owner or 0] end,
  -- (tests) a hint now (the 5-minute gap skipped); its key
  hint = function(owner) return hint(owner, true) end,
  -- (tests) "Docked" (the window's settings) on or off
  docked = function(player_index, on)
    local player = game.get_player(player_index)
    ui(player).inside = (not on) or nil
    build_panel(player)
  end,
  -- (tests) the window opened on a tab
  panel = function(player_index, tab)
    local player = game.get_player(player_index)
    ui(player).tab = tab or 1
    build_panel(player)
    if tab == 4 then act(player, "settings") end  -- (the settings: behind the gear by the close button)
  end,
  -- bpgen's answer to plan_line: its ghosts are placed (the crew build them), or why not (they make it by hand)
  line_placed = function(owner, item, ghosts, err, abs)
    local key = owner or 0
    local g = goals()[key]
    if not (g and g.item == item and g.line and g.line.state == "asked") then return end
    local m = members_of(owner)[1]
    if err or not (abs and abs.box) then
      g.line = false
      if m then say(m, "No line from bpgen (" .. tostring(err) .. "). We'll make it by hand.") end
      return
    end
    g.line = { state = "placed", box = abs.box, inputs = abs.inputs or {}, outputs = abs.outputs or {} }
    for _, o in pairs(crew()) do if o.owner == owner then o.auto_wait, o.goal_wait = nil, nil end end
    if m then say(m, "bpgen laid out a " .. pretty(item) .. " line: " .. tostring(ghosts) .. " pieces. Let's build it.") end
  end,
  status = function(name)
    local m = crew()[name]
    if not m then return end
    local inv = {}
    for _, it in pairs(m.entity.get_main_inventory().get_contents()) do inv[it.name] = (inv[it.name] or 0) + it.count end
    local j = m.jobs[1]
    return { lines = m.lines or 0, last_lines = m.last_lines, rides = m.rides or 0, riding = m.ride and m.entity.vehicle and m.entity.vehicle.name or nil, flights = m.flights or 0, flying = m.fly ~= nil, mode = m.roam and "roam" or m.follow and "follow" or "stay", position = m.entity.position, jobs = #m.jobs, health = m.entity.health, retreat = m.retreat, armed = gun_range(m) > 0,
      fighting = m.target and m.target.valid and m.target.name or nil, unit = m.entity.unit_number, doing = j and (j.kind .. ((j.item or j.recipe) and (" " .. (j.item or j.recipe) .. " " .. (j.n or 0) .. "/" .. (j.count or "")) or "")),
      inventory = inv, fed = m.fed, collected = m.collected, need = storage.needs and storage.needs[m.owner or 0] and storage.needs[m.owner or 0][1] and storage.needs[m.owner or 0][1].item }
  end,
})

-- the fse-std window's own handlers (title bar close, remembered place, resize grip), after ours
if fstd then
  require("__fse-std__/safe").chain("ai-crew", { require("__fse-std__/input").handlers, fstd.handlers,
    theme and theme.handlers or {} })
  if theme and theme.on_confirm then  -- (Fire, after its question)
    theme.on_confirm(function(player, name, yes, data)
      if name ~= "aic_fire" or not (yes and data and data.who) then return end
      order(player.index, "crew fire " .. data.who)
      if open_frame(player) then build_panel(player) end
    end)
  end
end
