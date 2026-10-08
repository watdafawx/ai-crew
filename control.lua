-- AI Crew: helper characters that build, clear, mine, hand-craft and fetch, run from a panel (the crew button, top left).
-- Idle, each one works like a construction bot near you: clears deconstruction marks, then places ghosts, hand-crafting
-- what it can't take from your pockets or nearby chests. Orders: get / mine / craft an item, build, clear, deliver,
-- follow, stay, stop. The panel's chat box goes to an LLM through the fnative loader (aicrew.py), which answers in
-- character and may queue the same jobs; plain orders typed there ("get 50 iron ore") run without it.
--
-- remote.call("ai-crew", ...): hire(name, surface, position, force?, owner_index?), order(owner_index, text), status(name)

local D = defines.direction
local DIRS = { D.north, D.northeast, D.east, D.southeast, D.south, D.southwest, D.west, D.northwest }
local NAMES = { "Rook", "Mara", "Juno", "Bolt", "Pip", "Sable", "Tess", "Orin" }
local COLORS = { { 1, 0.55, 0.2 }, { 0.3, 0.8, 1 }, { 0.6, 1, 0.4 }, { 1, 0.4, 0.7 }, { 1, 0.9, 0.3 }, { 0.7, 0.5, 1 },
  { 0.4, 1, 0.9 }, { 1, 0.6, 0.5 } }
local ADA_COLOR = "1,0.62,0.2"
local RADIUS = 48 -- the work area around the owner (or home)
local MAX_CREW = 4
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
  attack = { "Locked and loaded.", "Let's clear them out.", "Time to burn some nests." } }

local pending = {} -- native job id -> what to do with the answer (not saved: an answer in flight at save time is dropped)
local source_names = {} -- item -> names of resources/trees/rocks that yield it

-- ---------------------------------------------------------------------------------------------------------------- util

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

local function py()
  if not native then return false end
  local ok, p = pcall(native.plugins)
  return ok and p and p.py ~= nil
end

local function player_setting(player, name)
  local ok, v = pcall(function() return settings.get_player_settings(player)[name].value end)
  if ok then return v end
end

-- the single player, for settings when no one gave the order
local function any_player()
  for _, p in pairs(game.connected_players) do return p end
end

local function speak(text, voice, player)
  player = player or any_player()
  if not (player and py()) then return end
  if not player_setting(player, voice == "ada" and "ai-crew-ada" or "ai-crew-voices") then return end
  native.call("py", "aicrew:speak", helpers.table_to_json({ text = text, voice = voice,
    ada_voice = voice == "ada" and player_setting(player, "ai-crew-ada-voice") or nil }))
end

local function llm_settings(player)
  if not player then return {} end
  return { provider = player_setting(player, "ai-crew-provider"), key = player_setting(player, "ai-crew-api-key"),
    model = player_setting(player, "ai-crew-model") }
end

local function ada(text)
  local p = any_player()
  if p and not player_setting(p, "ai-crew-ada") then return end
  if p and py() and player_setting(p, "ai-crew-ada-llm") then
    local id = native.start("py", "aicrew:ada", helpers.table_to_json({ text = text, llm = llm_settings(p) }))
    if id then
      pending[id] = { kind = "ada", text = text }
      return
    end
  end
  game.print("[color=" .. ADA_COLOR .. "][ADA][/color] " .. text)
  speak(text, "ada")
end

local function say(m, text)
  local e = m.entity
  local c = m.color
  game.print(string.format("[color=%g,%g,%g]%s:[/color] %s", c[1], c[2], c[3], m.name, text))
  if m.bubble and m.bubble.valid then m.bubble.destroy() end
  m.bubble = rendering.draw_text({ text = text, surface = e.surface, target = { entity = e, offset = { 0, -2.9 } },
    color = c, scale = 1.1, alignment = "center", time_to_live = 300 })
  speak(text, m.voice, m.owner and game.get_player(m.owner))
end

-- ------------------------------------------------------------------------------------------------- items and sources

local function resolve_item(s)
  if type(s) ~= "string" then return end
  s = s:lower():gsub("^%s+", ""):gsub("%s+$", ""):gsub("^the%s+", ""):gsub("^some%s+", ""):gsub("[%s_]+", "-")
  if s == "" then return end
  local I = prototypes.item
  if ALIASES[s] and I[ALIASES[s]] then return ALIASES[s] end
  local one = (s:gsub("s$", ""))
  for _, c in ipairs({ s, s .. "-ore", one, (s:gsub("es$", "")), s .. "-plate", one .. "-plate" }) do
    if I[c] then return c end
  end
  if ALIASES[one] and I[ALIASES[one]] then return ALIASES[one] end
  local best
  for name in pairs(I) do
    if name:find(one, 1, true) and (not best or #name < #best) then best = name end
  end
  return best
end

-- names of the resources, trees and rocks a character can mine by hand for this item
local function sources_for(item)
  if source_names[item] then return source_names[item] end
  local names = {}
  for name, proto in pairs(prototypes.get_entity_filtered({ { filter = "type", type = { "resource", "tree", "simple-entity" } } })) do
    local mp = proto.mineable_properties
    if mp and mp.minable and not mp.required_fluid then
      for _, p in pairs(mp.products or {}) do
        if p.type == "item" and p.name == item then names[#names + 1] = name break end
      end
    end
  end
  source_names[item] = names
  return names
end

local HAND
local function hand_categories()
  HAND = HAND or (prototypes.entity["character"] and prototypes.entity["character"].crafting_categories) or { crafting = true }
  return HAND
end

local function handcraft_recipe(force, item)
  local HAND = hand_categories()
  local r = force.recipes[item]
  if r and r.enabled and not r.hidden and HAND[r.category] then return r end
end

local function owner_char(m)
  local p = m.owner and game.get_player(m.owner)
  local c = p and p.valid and p.character
  if c and c.valid and c.surface == m.entity.surface then return c end
end

local function anchor(m)
  local c = owner_char(m)
  return c and c.position or m.home
end

-- chests near the owner (or home); logistic chests only when they're in no network (the network counts those)
local function chests(m)
  local out = {}
  for _, ch in pairs(m.entity.surface.find_entities_filtered({ type = { "container", "logistic-container" },
    force = m.entity.force, position = anchor(m), radius = RADIUS })) do
    local inv = ch.get_inventory(defines.inventory.chest)
    if inv and not (ch.type == "logistic-container" and ch.logistic_network) then out[#out + 1] = inv end
  end
  return out
end

-- the logistic network where the owner (or home) is: its storage and provider chests, wherever they are
local function network(m)
  return m.entity.surface.find_logistic_network_by_position(anchor(m), m.entity.force)
end

-- inventories the crew may take from: the owner's pockets, then chests near the owner (or home)
local function sources(m, chests_only)
  local out = chests(m)
  local c = not chests_only and owner_char(m)
  if c then table.insert(out, 1, c.get_main_inventory()) end
  return out
end

local function available(m, item, quality, chests_only)
  local id = { name = item, quality = quality or "normal" }
  local n = 0
  for _, inv in pairs(sources(m, chests_only)) do n = n + inv.get_item_count(id) end
  local net = network(m)
  return net and n + net.get_item_count(id) or n
end

-- chisle: items move from the owner/chests/network straight into the crew's pockets, no walking to each chest
local function take(m, item, count, quality, chests_only)
  local inv = m.entity.get_main_inventory()
  local id = { name = item, quality = quality or "normal" }
  local got = 0
  for _, src in pairs(sources(m, chests_only)) do
    if got >= count then break end
    local n = math.min(count - got, src.get_item_count(id))
    if n > 0 then
      local ins = inv.insert({ name = item, count = n, quality = id.quality })
      if ins > 0 then src.remove({ name = item, count = ins, quality = id.quality }) end
      got = got + ins
    end
  end
  local net = got < count and network(m)
  if net then
    local n = math.min(count - got, net.get_item_count(id))
    local ins = n > 0 and inv.insert({ name = item, count = n, quality = id.quality }) or 0
    if ins > 0 then
      local out = net.remove_item({ name = item, count = ins, quality = id.quality })
      if out < ins then inv.remove({ name = item, count = ins - out, quality = id.quality }) end
      got = got + out
    end
  end
  return got
end

-- everything in its pockets goes to the owner, else chests near home; what doesn't fit stays
local function unload(m)
  local inv = m.entity.get_main_inventory()
  local dests = {}
  local c = owner_char(m)
  if c then dests[1] = c.get_main_inventory() else dests = chests(m) end
  local moved = 0
  for _, it in pairs(inv.get_contents()) do
    local left = it.count
    for _, d in pairs(dests) do
      if left <= 0 then break end
      local n = d.insert({ name = it.name, count = left, quality = it.quality })
      if n > 0 then
        inv.remove({ name = it.name, count = n, quality = it.quality })
        left, moved = left - n, moved + n
      end
    end
  end
  return moved
end

-- ----------------------------------------------------------------------------------------------------------- moving

local function stop_walk(m)
  m.move = nil
  if m.entity.valid then m.entity.walking_state = { walking = false, direction = D.north } end
end

local function stop_mining(m)
  m.mining = nil
  if m.entity.valid then m.entity.mining_state = { mining = false } end
end

local function request_path(m)
  local e, mv = m.entity, m.move
  local id = e.surface.request_path({ bounding_box = { { -0.2, -0.2 }, { 0.2, 0.2 } },
    collision_mask = e.prototype.collision_mask, start = e.position, goal = mv.goal, force = e.force,
    radius = math.max(mv.radius - 0.5, 0.5), entity_to_ignore = e, pathfind_flags = { cache = false, no_break = true } })
  storage.paths = storage.paths or {}
  storage.paths[id] = m.name
  mv.path, mv.i, mv.final, mv.still = nil, 1, nil, 0
end

-- true when already within radius of pos; else starts walking there
local function go(m, pos, radius)
  if dist2(m.entity.position, pos) <= radius * radius then
    if m.move then stop_walk(m) end
    return true
  end
  if not (m.move and dist2(m.move.goal, pos) < 1) then
    m.move = { goal = { x = pos.x, y = pos.y }, radius = radius, hops = 0 }
    request_path(m)
  end
  return false
end

local function walk(m)
  local mv, e = m.move, m.entity
  if dist2(e.position, mv.goal) <= mv.radius * mv.radius then return stop_walk(m) end
  if not mv.path then
    if mv.retry and game.tick >= mv.retry then mv.retry = nil request_path(m) end
    return
  end
  local wp = mv.path[mv.i]
  if wp and dist2(e.position, wp.position) < 0.25 then
    mv.i = mv.i + 1
    wp = mv.path[mv.i]
  end
  if not wp then
    if mv.final then return stop_walk(m) end
    mv.final = true
    mv.path[mv.i] = { position = mv.goal }
    wp = mv.path[mv.i]
  end
  local dx, dy = wp.position.x - e.position.x, wp.position.y - e.position.y
  e.walking_state = { walking = true, direction = DIRS[math.floor(math.atan2(dx, -dy) / (math.pi / 4) + 0.5) % 8 + 1] }
  -- stuck (hardly moved for 1.5 s): ask for a new path; after three tries hop next to the goal
  if mv.last and dist2(e.position, mv.last) < 0.0004 then mv.still = mv.still + 1 else mv.still = 0 end
  mv.last = { x = e.position.x, y = e.position.y }
  if mv.still > 90 then
    mv.hops = mv.hops + 1
    if mv.hops > 2 then
      local to = e.surface.find_non_colliding_position(e.name, mv.goal, 6, 0.5)
      if to then e.teleport(to) end
      stop_walk(m)
    else
      request_path(m)
    end
  end
end

-- ------------------------------------------------------------------------------------------------------------- jobs

local JOBS = {}
local low_burners -- (defined with the fuel helpers)
local DOING_WORD = { build = "building", deconstruct = "clearing", mine = "mining", craft = "crafting",
  fetch = "fetching", deliver = "delivering", smelt = "making", place = "placing", tend = "refuelling",
  feed = "feeding", collect = "collecting", attack = "attacking nests" }

local function claims()
  storage.claims = storage.claims or {}
  return storage.claims
end

-- what the crew has to work for (ghost items, a craft's ingredients, an order), ahead of the goal: {item, more, reason,
-- after = the job to run once it's there}; count is set when work on it starts (what was had then + more)
local function needs(owner)
  storage.needs = storage.needs or {}
  local k = owner or 0
  storage.needs[k] = storage.needs[k] or {}
  return storage.needs[k]
end

local function add_need(owner, item, more, reason, after)
  local list = needs(owner)
  for _, nd in pairs(list) do if nd.item == item then return false end end
  list[#list + 1] = { item = item, more = more, reason = reason, after = after }
  return true
end

local function place_item(g)
  local items = g.ghost_prototype.items_to_place_this
  local it = items and items[1]
  if not it then return end
  return { name = it.name, count = it.count or 1, quality = g.type == "tile-ghost" and "normal" or g.quality.name }
end

-- takes from the owner/chests what crafting `count` of recipe needs (own pockets first, intermediates hand-crafted);
-- returns {item = short} when it can't. dry: only checks
local function gather(m, recipe, count, dry)
  local e = m.entity
  local inv = e.get_main_inventory()
  local own, pool, need, missing = {}, {}, {}, {}
  local function want(item, n, depth)
    own[item] = own[item] or inv.get_item_count(item)
    local use = math.min(own[item], n)
    own[item], n = own[item] - use, n - use
    if n <= 0 then return end
    pool[item] = pool[item] or available(m, item)
    use = math.min(pool[item], n)
    pool[item], n = pool[item] - use, n - use
    need[item] = (need[item] or 0) + use
    if n <= 0 then return end
    local r = depth < 6 and handcraft_recipe(e.force, item)
    if r then
      local per = 1
      for _, p in pairs(r.products) do if p.name == item then per = p.amount or p.amount_max or 1 end end
      local runs = math.ceil(n / per)
      for _, ing in pairs(r.ingredients) do want(ing.name, ing.amount * runs, depth + 1) end
    else
      missing[item] = (missing[item] or 0) + n
    end
  end
  for _, ing in pairs(recipe.ingredients) do want(ing.name, ing.amount * count, 0) end
  if next(missing) then return missing end
  if dry then return end
  for item, n in pairs(need) do take(m, item, n) end
end

local function key_of(e) return e.unit_number or (e.name .. e.position.x .. "," .. e.position.y) end

local function product_amount(r, item)
  for _, p in pairs(r.products) do if p.name == item then return p.amount or p.amount_max or 1 end end
  return 1
end

-- starts hand-crafting `count` of item (or, if that's too much, `single`); crafting goes on while it walks
local function craft_for(m, item, count, single)
  local r = handcraft_recipe(m.entity.force, item)
  if not r then return 0 end
  local per = product_amount(r, item)
  for _, n in ipairs({ count, single }) do
    local runs = math.ceil(n / per)
    if not gather(m, r, runs) then return m.entity.begin_crafting({ recipe = item, count = runs, silent = true }) * per end
  end
  return 0
end

-- the nearest ghost whose item it has, can take, or can hand-craft; and {item, count, single} to craft first
local function next_ghost(m, job)
  local e = m.entity
  local cache, craftable, demand, best, bd, best_k = {}, {}, {}, nil, nil, nil
  job.short = {}
  local inv = e.get_main_inventory()
  for _, g in pairs(e.surface.find_entities_filtered({ type = { "entity-ghost", "tile-ghost" }, force = e.force,
    position = anchor(m), radius = RADIUS })) do
    local key = key_of(g)
    local claim = claims()[key]
    if not job.skip[key] and (not claim or claim == m.name or not crew()[claim]) then
      local it = place_item(g)
      if it then
        local k = it.name .. "/" .. it.quality
        if cache[k] == nil then
          cache[k] = inv.get_item_count({ name = it.name, quality = it.quality }) + available(m, it.name, it.quality)
        end
        demand[k] = (demand[k] or 0) + it.count
        if cache[k] < it.count and craftable[k] == nil then
          local r = it.quality == "normal" and handcraft_recipe(e.force, it.name)
          craftable[k] = r and not gather(m, r, math.ceil(it.count / product_amount(r, it.name)), true) or false
        end
        if cache[k] >= it.count or craftable[k] then
          local d = dist2(e.position, g.position)
          if not bd or d < bd then best, bd, best_k = g, d, k end
        else
          job.short[k] = it
        end
      end
    end
  end
  for k, it in pairs(job.short) do job.missing[it.name] = demand[k] - cache[k] end
  if not best then return end
  claims()[key_of(best)] = m.name
  local it = place_item(best)
  if cache[best_k] >= it.count then return best end
  return best, { item = it.name, count = math.min(demand[best_k] - cache[best_k], 50), single = it.count }
end

-- what it did and what it's missing; on its own (auto) only news: something done, or a new shortage
local function report(m, job, verb)
  local parts = {}
  if job.n > 0 then parts[#parts + 1] = verb .. " " .. job.n .. "." end
  local miss = {}
  for name, n in pairs(job.missing or {}) do
    miss[#miss + 1] = pretty(name)
    if type(n) == "number" and n > 0 then add_need(m.owner, name, n, "the blueprint") end
  end
  table.sort(miss)
  local short = #miss > 0 and ("Out of " .. table.concat(miss, ", ", 1, math.min(#miss, 4)) .. ". I'll go get some.") or nil
  if short and (not job.auto or short ~= m.said_short) then parts[#parts + 1] = short end
  m.said_short = short
  if #parts > 0 then say(m, table.concat(parts, " "))
  elseif not job.auto then say(m, "Nothing to " .. job.kind .. " here.") end
  if job.auto and job.n == 0 then m.auto_wait = game.tick + 600 end -- nothing doable: look less often
end

JOBS.build = function(m, job)
  local e = m.entity
  local g = job.target
  if not (g and g.valid) then
    job.missing = {}
    local c
    g, c = next_ghost(m, job)
    job.target = g
    if not g then report(m, job, "Built") unload(m) return true end
    if c and e.crafting_queue_size == 0 then craft_for(m, c.item, c.count, c.single) end
  end
  if not go(m, g.position, math.max(e.build_distance - 2, 2)) then return false end
  local key = key_of(g)
  local it = place_item(g)
  local inv = e.get_main_inventory()
  local id = { name = it.name, quality = it.quality }
  local have = inv.get_item_count(id)
  if have < it.count then have = have + take(m, it.name, it.count - have, it.quality) end
  if have < it.count and e.crafting_queue_size > 0 then return false end -- still crafting it
  if have >= it.count then
    g.revive({ raise_revive = true })
    if not g.valid then
      inv.remove({ name = it.name, count = it.count, quality = it.quality })
      job.n = job.n + 1
    end
  end
  if g.valid then job.skip[key] = true end
  claims()[key] = nil
  job.target = nil
  return false
end

JOBS.deconstruct = function(m, job)
  local e = m.entity
  local t = job.target
  if not (t and t.valid and t.to_be_deconstructed()) then
    t = nil
    local bd
    for _, c in pairs(e.surface.find_entities_filtered({ position = anchor(m), radius = RADIUS, to_be_deconstructed = true })) do
      local key = key_of(c)
      local claim = claims()[key]
      if c.type ~= "character" and not job.skip[key] and c.minable and (not claim or claim == m.name or not crew()[claim]) then
        local d = dist2(e.position, c.position)
        if not bd or d < bd then t, bd = c, d end
      end
    end
    job.target = t
    if t then claims()[key_of(t)] = m.name end
    if not t then
      report(m, job, "Cleared")
      if not e.get_main_inventory().is_empty() then table.insert(m.jobs, 2, { kind = "deliver" }) end
      return true
    end
  end
  if not go(m, t.position, math.max(e.reach_distance - 2, 2)) then return false end
  local key = key_of(t)
  claims()[key] = nil
  if e.mine_entity(t, false) then
    job.n = job.n + 1
  elseif e.get_main_inventory().count_empty_stacks() == 0 then
    table.insert(m.jobs, 1, { kind = "deliver" }) -- pockets full: drop off, then carry on
    return false
  else
    job.skip[key] = true
  end
  job.target = nil
  return false
end

local function nearest_source(m, job)
  local names = sources_for(job.item)
  if #names == 0 then return end
  local e = m.entity
  for _, r in ipairs({ 16, 48, 128 }) do
    local best, bd
    for _, s in pairs(e.surface.find_entities_filtered({ name = names, position = e.position, radius = r })) do
      local key = s.position.x .. "," .. s.position.y
      if not job.skip[key] then
        local d = dist2(e.position, s.position)
        if not bd or d < bd then best, bd = s, d end
      end
    end
    if best then return best end
  end
end

JOBS.mine = function(m, job)
  local e = m.entity
  local inv = e.get_main_inventory()
  local cur = inv.get_item_count(job.item)
  if job.last and cur > job.last then
    job.n = job.n + cur - job.last
    job.since = game.tick
  end
  job.last = cur
  job.since = job.since or game.tick
  if job.n >= job.count then
    stop_mining(m)
    say(m, "Got " .. job.n .. " " .. pretty(job.item) .. ".")
    table.insert(m.jobs, 2, { kind = "deliver" })
    return true
  end
  if not inv.can_insert({ name = job.item }) then
    stop_mining(m)
    table.insert(m.jobs, 1, { kind = "deliver" })
    return false
  end
  local t = job.target
  if not (t and t.valid) or game.tick - job.since > 900 then
    if t and t.valid then job.skip[t.position.x .. "," .. t.position.y] = true end
    stop_mining(m)
    t = nearest_source(m, job)
    job.target, job.since = t, game.tick
    if not t then
      say(m, "No " .. pretty(job.item) .. " to mine around here." .. (job.n > 0 and (" Got " .. job.n .. ".") or ""))
      if job.n > 0 then table.insert(m.jobs, 2, { kind = "deliver" }) end
      return true
    end
  end
  local reach = e.resource_reach_distance -- hand mining, trees and rocks too, needs to be this close
  if not go(m, t.position, math.max(reach - 0.6, 1)) then
    m.mining = nil
    return false
  end
  m.mining = t.position
  return false
end

JOBS.craft = function(m, job)
  local e = m.entity
  if not job.started then
    local r = handcraft_recipe(e.force, job.recipe)
    if not r then say(m, "I can't hand-craft " .. pretty(job.recipe) .. ".") return true end
    local per = product_amount(r, job.recipe)
    job.runs = math.ceil(job.count / per)
    local missing = gather(m, r, job.runs)
    if missing then
      local parts = {}
      local last
      for item, n in pairs(missing) do
        parts[#parts + 1] = n .. " " .. pretty(item)
        if add_need(m.owner, item, n, pretty(job.recipe)) then last = item end
      end
      for _, nd in pairs(needs(m.owner)) do -- craft again once the last of it is in
        if nd.item == last then nd.after = { kind = "craft", recipe = job.recipe, count = job.count } end
      end
      say(m, "For " .. job.count .. " " .. pretty(job.recipe) .. " I'm short " .. table.concat(parts, ", ") .. ". I'll go get it.")
      return true
    end
    job.started = e.begin_crafting({ recipe = job.recipe, count = job.runs, silent = true }) * per
    if job.started == 0 then say(m, "Couldn't start on " .. pretty(job.recipe) .. ".") unload(m) return true end
    return false
  end
  if e.crafting_queue_size > 0 then return false end
  job.n = job.started
  say(m, "Made " .. job.started .. " " .. pretty(job.recipe) .. ".")
  table.insert(m.jobs, 2, { kind = "deliver" })
  return true
end

JOBS.fetch = function(m, job)
  local got = take(m, job.item, job.count, nil, true)
  say(m, got > 0 and ("Got " .. got .. " " .. pretty(job.item) .. " from the chests.") or ("No " .. pretty(job.item) .. " in the chests."))
  if got > 0 then table.insert(m.jobs, 2, { kind = "deliver" }) end
  return true
end

JOBS.deliver = function(m, job)
  if m.entity.get_main_inventory().is_empty() then return true end
  if not go(m, anchor(m), 3) then return false end
  unload(m)
  return true
end


-- ---------------------------------------------------------------------------------------------- smelting and goals

local FUELS = { "coal", "solid-fuel", "wood" }
local machine_cache = {} -- item -> names of recipes (item ingredients only) that make it in a machine

-- the recipe to make item in a machine (one hand-crafting can't do), preferring the one named after it
local function machine_recipe(force, item)
  if not machine_cache[item] then
    local list = {}
    local hand = hand_categories()
    for name, r in pairs(prototypes.recipe) do
      local ok = not r.hidden and not hand[r.category] and #r.ingredients > 0
      for _, i in pairs(r.ingredients) do if i.type ~= "item" then ok = false end end
      local makes = false
      for _, p in pairs(r.products) do if p.type == "item" and p.name == item then makes = true end end
      if ok and makes then list[#list + 1] = name end
    end
    table.sort(list, function(a, b)
      if (a == item) ~= (b == item) then return a == item end
      if #a ~= #b then return #a < #b end
      return a < b
    end)
    machine_cache[item] = list
  end
  for _, name in ipairs(machine_cache[item]) do
    local r = force.recipes[name]
    if r and r.enabled then return r end
  end
end

local IN = { furnace = defines.inventory.furnace_source, ["assembling-machine"] = defines.inventory.assembling_machine_input }
local OUT = { furnace = defines.inventory.furnace_result, ["assembling-machine"] = defines.inventory.assembling_machine_output }

-- machines near the owner free for this recipe, nearest first, up to 4: a furnace that's empty or on the same input;
-- an assembler-type machine (overhaul mods' furnaces too) with no recipe and nothing in it, or already on this recipe
local function machines_for(m, r, item)
  local e = m.entity
  local out = {}
  for _, f in pairs(e.surface.find_entities_filtered({ type = { "furnace", "assembling-machine" }, force = e.force,
    position = anchor(m), radius = RADIUS })) do
    local p = f.prototype
    local in_line = false -- (a bpgen line's machines are fed by the line)
    for _, g in pairs(storage.goals or {}) do
      local b = g.line and g.line.box
      if b and f.position.x >= b[1] and f.position.y >= b[2] and f.position.x <= b[1] + b[3] and f.position.y <= b[2] + b[4] then
        in_line = true
      end
    end
    if not in_line and p.crafting_categories[r.category] and f.status ~= defines.entity_status.no_power
      and (not p.fixed_recipe or p.fixed_recipe == r.name) then
      local src, res = f.get_inventory(IN[f.type]), f.get_inventory(OUT[f.type])
      local free
      if f.type == "furnace" then
        free = src.is_empty() or src.get_item_count(r.ingredients[1].name) > 0
      else
        local cur = f.get_recipe()
        free = (not cur and src.is_empty()) or (cur and cur.name == r.name)
      end
      if free and (res.is_empty() or res.get_item_count(item) > 0) then out[#out + 1] = f end
    end
  end
  table.sort(out, function(a, b) return dist2(e.position, a.position) < dist2(e.position, b.position) end)
  for i = #out, 5, -1 do out[i] = nil end
  return out
end

local function fuel_available(m)
  local inv = m.entity.get_main_inventory()
  for _, f in ipairs(FUELS) do
    if prototypes.item[f] and inv.get_item_count(f) + available(m, f) > 0 then return f end
  end
end

local function needs_fuel(f)
  local fuel = f.burner and f.get_fuel_inventory()
  return fuel and fuel.get_item_count() < 3
end

local function refuel(m, f)
  if not needs_fuel(f) then return end
  local inv = m.entity.get_main_inventory()
  local name = fuel_available(m)
  if not name then return end
  if inv.get_item_count(name) < 10 then take(m, name, 10 - inv.get_item_count(name)) end
  local n = math.min(inv.get_item_count(name), 10)
  if n > 0 then
    local put = f.get_fuel_inventory().insert({ name = name, count = n })
    if put > 0 then inv.remove({ name = name, count = put }) end
  end
end

-- loads machines near the owner with the ingredients (and fuel; the recipe when it's an assembler), then collects
-- what they make
JOBS.smelt = function(m, job)
  local e = m.entity
  local inv = e.get_main_inventory()
  local r = e.force.recipes[job.recipe]
  if not job.machines then
    job.machines = machines_for(m, r, job.item)
    if #job.machines == 0 then say(m, "No free machine near you for " .. pretty(job.item) .. ".") return true end
    job.runs = math.ceil(job.count / product_amount(r, job.item))
    for _, ing in pairs(r.ingredients) do
      local need, have = ing.amount * job.runs, inv.get_item_count(ing.name)
      if have < need then take(m, ing.name, need - have) end
    end
    job.i, job.stage, job.left = 1, "load", job.runs
  end
  if job.stage == "load" then
    local f = job.machines[job.i]
    if not f then
      job.stage, job.since = "collect", game.tick
      return false
    end
    if not f.valid then job.i = job.i + 1 return false end
    if not go(m, f.position, math.max(e.reach_distance - 2, 2)) then return false end
    if f.type == "assembling-machine" then
      local cur = f.get_recipe()
      if not (cur and cur.name == r.name) then f.set_recipe(r.name) end
    end
    local runs = math.ceil(job.left / (#job.machines - job.i + 1))
    local src = f.get_inventory(IN[f.type])
    for _, ing in pairs(r.ingredients) do
      local n = math.min(inv.get_item_count(ing.name), ing.amount * runs)
      local put = n > 0 and src.insert({ name = ing.name, count = n }) or 0
      if put > 0 then inv.remove({ name = ing.name, count = put }) end
    end
    job.left = job.left - runs
    refuel(m, f)
    job.i = job.i + 1
    return false
  end
  local best, busy
  for _, f in pairs(job.machines) do
    if f.valid then
      if not best and not f.get_inventory(OUT[f.type]).is_empty() then best = f end
      if not f.get_inventory(IN[f.type]).is_empty() or f.is_crafting() then busy = true end
    end
  end
  if best and (job.n < job.count or not busy) then
    if not go(m, best.position, math.max(e.reach_distance - 2, 2)) then return false end
    local res = best.get_inventory(OUT[best.type])
    for _, it in pairs(res.get_contents()) do -- by-products too: they'd block the machine
      local got = inv.insert({ name = it.name, count = it.count, quality = it.quality })
      if got > 0 then
        res.remove({ name = it.name, count = got, quality = it.quality })
        if it.name == job.item then job.n, job.since = job.n + got, game.tick end
      end
    end
    refuel(m, best)
    return false
  end
  if busy and job.n < job.count and game.tick - job.since < 3600 then return false end
  say(m, "Made " .. job.n .. " " .. pretty(job.item) .. ".")
  table.insert(m.jobs, 2, { kind = "deliver" })
  return true
end

-- burners low on fuel within 150 tiles of the owner, nearest first
low_burners = function(m, limit)
  local e = m.entity
  local out = {}
  for _, f in pairs(e.surface.find_entities_filtered({ type = { "boiler", "furnace", "mining-drill", "assembling-machine",
    "burner-generator", "inserter", "lab" }, force = e.force, position = anchor(m), radius = 150 })) do
    if needs_fuel(f) then out[#out + 1] = f end
  end
  table.sort(out, function(a, b) return dist2(e.position, a.position) < dist2(e.position, b.position) end)
  for i = #out, limit + 1, -1 do out[i] = nil end
  return out
end

JOBS.place = function(m, job)
  local e = m.entity
  local inv = e.get_main_inventory()
  if inv.get_item_count(job.item) == 0 and take(m, job.item, 1) == 0 then say(m, "No " .. pretty(job.item) .. " to place.") return true end
  local proto = prototypes.item[job.item].place_result
  local spec = { name = proto.name, position = job.at, direction = job.direction, force = e.force,
    build_check_type = defines.build_check_type.manual }
  if job.at and not e.surface.can_place_entity(spec) then
    if job.layout and storage.steam then storage.steam[job.layout] = nil end -- something's in the way: plan it again
    if job.fixed then return true end
    job.at = nil
  end
  if not job.at then
    local a = anchor(m)
    local near = e.surface.find_entities_filtered({ type = proto.type, force = e.force, position = a, radius = RADIUS })
    local base = near[1] and { x = near[1].position.x + 2, y = near[1].position.y } or { x = a.x + 4, y = a.y - 3 }
    job.at = e.surface.find_non_colliding_position(proto.name, base, 16, 1)
    if not job.at then say(m, "No room for a " .. pretty(job.item) .. " near you.") return true end
  end
  if not go(m, job.at, math.max(e.build_distance - 2, 2)) then return false end
  spec.position, spec.build_check_type, spec.raise_built = job.at, nil, true
  if e.surface.create_entity(spec) then
    inv.remove({ name = job.item, count = 1 })
    job.n = 1
    if not job.quiet then say(m, "Set up a " .. pretty(job.item) .. ".") end
  end
  return true
end

-- refuels burners (boilers, furnaces, drills...) near the owner that are running low
JOBS.tend = function(m, job)
  local e = m.entity
  job.targets = job.targets or low_burners(m, 6)
  local f = job.targets[1]
  if not f then return true end
  if not (f.valid and needs_fuel(f)) or not fuel_available(m) then table.remove(job.targets, 1) return false end
  if not go(m, f.position, math.max(e.reach_distance - 2, 2)) then return false end
  refuel(m, f)
  job.n = job.n + 1
  table.remove(job.targets, 1)
  return false
end

local function goals()
  storage.goals = storage.goals or {}
  return storage.goals
end

-- how many of item the owner has: pockets, chests near them, and what the crew carries
local function goal_have(owner, item)
  local n, first = 0, nil
  for _, m in pairs(crew()) do
    if m.owner == owner and m.entity.valid then
      first = first or m
      n = n + m.entity.get_main_inventory().get_item_count(item)
    end
  end
  return first and n + available(first, item) or n
end


-- --------------------------------------------------------------------------------------------- machines and power

local plan -- (below)
local GENERATORS = { "generator", "burner-generator", "solar-panel", "electric-energy-interface" }

local function have_count(m, item)
  return m.entity.get_main_inventory().get_item_count(item) + available(m, item)
end

-- is anything generating in this electric network (looked for within 200 tiles)
local function net_has_power(surface, force, id, near)
  if not id then return false end
  for _, g in pairs(surface.find_entities_filtered({ type = GENERATORS, force = force, position = near, radius = 200 })) do
    if g.electric_network_id == id then return true end
  end
  return false
end

-- where water meets land nearest the owner: an offshore pump, a boiler on its output and a steam engine on the boiler's
-- steam, found by trial-placing each piece and keeping it only when its fluidbox connects (modded pieces work too)
local function connects(ent, to)
  for i = 1, #ent.fluidbox do
    for _, fb in pairs(ent.fluidbox.get_connections(i)) do if fb.owner == to then return true end end
  end
  return false
end

local function attach(s, force, name, to, r)
  for _, d in ipairs({ 0, 4, 8, 12 }) do
    for x = -r, r, 0.5 do
      for y = -r, r, 0.5 do
        local spec = { name = name, position = { to.position.x + x, to.position.y + y }, direction = d, force = force,
          build_check_type = defines.build_check_type.manual }
        if s.can_place_entity(spec) then
          spec.build_check_type = nil
          local ent = s.create_entity(spec)
          if ent then
            if connects(ent, to) then return ent end
            ent.destroy()
          end
        end
      end
    end
  end
end

local function steam_layout(m)
  local e = m.entity
  local s, f, a = e.surface, e.force, anchor(m)
  local tiles = s.find_tiles_filtered({ position = a, radius = 150, collision_mask = "water_tile", limit = 20000 })
  table.sort(tiles, function(t1, t2) return dist2(t1.position, a) < dist2(t2.position, a) end)
  local tried = {}
  for i = 1, math.min(#tiles, 400) do
    local tp = tiles[i].position
    for ox = -1, 1 do
      for oy = -1, 1 do
        local pos = { x = tp.x + ox + 0.5, y = tp.y + oy + 0.5 }
        local k = pos.x .. "," .. pos.y
        if not tried[k] then
          tried[k] = true
          for _, d in ipairs({ 0, 4, 8, 12 }) do
            local spec = { name = "offshore-pump", position = pos, direction = d, force = f, build_check_type = defines.build_check_type.manual }
            if s.can_place_entity(spec) then
              spec.build_check_type = nil
              local pump = s.create_entity(spec)
              local boiler = pump and attach(s, f, "boiler", pump, 3)
              local engine = boiler and attach(s, f, "steam-engine", boiler, 5)
              local out
              if engine then
                out = {}
                for _, ent in ipairs({ pump, boiler, engine }) do
                  out[#out + 1] = { name = ent.name, position = { x = ent.position.x, y = ent.position.y }, direction = ent.direction }
                end
              end
              for _, ent in ipairs({ engine, boiler, pump }) do if ent and ent.valid then ent.destroy() end end
              if out then return out end
            end
          end
        end
      end
    end
  end
end

-- the next piece of a steam plant for the owner; nil once it's all standing
local function steam_step(m, depth)
  if not (prototypes.entity["offshore-pump"] and prototypes.entity["boiler"] and prototypes.entity["steam-engine"]) then
    return nil, "I don't know how to build power here."
  end
  local key = m.owner or 0
  storage.steam = storage.steam or {}
  local lay = storage.steam[key]
  if not lay then
    lay = steam_layout(m)
    if not lay then return nil, "There's no water near you to build steam power by." end
    storage.steam[key] = lay
  end
  local s = m.entity.surface
  for _, piece in ipairs(lay) do
    if not s.find_entities_filtered({ name = piece.name, position = piece.position, radius = 0.5, limit = 1 })[1] then
      local item = prototypes.entity[piece.name].items_to_place_this[1].name
      if have_count(m, item) > 0 then
        return { kind = "place", item = item, at = piece.position, direction = piece.direction, layout = key, fixed = true }
      end
      return plan(m, item, 1, depth + 1)
    end
  end
end

local function pole_item(m)
  for _, name in ipairs({ "medium-electric-pole", "small-electric-pole" }) do
    if prototypes.item[name] and have_count(m, name) > 0 then return name end
  end
  return prototypes.item["small-electric-pole"] and "small-electric-pole"
end

-- the next step to power this machine: grow poles from the nearest powered pole (or a generator) towards it, build
-- steam power if there's nothing, fuel the boilers if it's all connected but dark
local function power_to(m, machine, depth)
  local e = m.entity
  local s, force = e.surface, e.force
  local from, fd
  for _, p in pairs(s.find_entities_filtered({ type = "electric-pole", force = force, position = machine.position, radius = 150 })) do
    if net_has_power(s, force, p.electric_network_id, p.position) then
      local d = dist2(p.position, machine.position)
      if not fd or d < fd then from, fd = p, d end
    end
  end
  if not from then
    for _, g in pairs(s.find_entities_filtered({ type = GENERATORS, force = force, position = machine.position, radius = 150 })) do
      local d = dist2(g.position, machine.position)
      if not fd or d < fd then from, fd = g, d end
    end
  end
  if not from then
    local job, why = steam_step(m, depth)
    if job or why then return job, why end
    return nil, "Steam power is up but not connected yet."
  end
  if from.electric_network_id and from.electric_network_id == machine.electric_network_id then
    -- connected, no power: the burners feeding it need fuel
    if #low_burners(m, 1) > 0 then
      if fuel_available(m) then return { kind = "tend" } end
      return plan(m, nearest_source(m, { item = "coal", skip = {} }) and "coal" or "wood", 20, depth + 1)
    end
    return nil, "The power's connected but there isn't enough of it for the " .. pretty(machine.name) .. "."
  end
  local item = pole_item(m)
  if not item then return nil, "I don't know how to make electric poles here." end
  if have_count(m, item) == 0 then return plan(m, item, 5, depth + 1) end
  local pp = prototypes.item[item].place_result
  local reach, supply = pp.get_max_wire_distance() - 0.5, pp.get_supply_area_distance()
  local dx, dy = machine.position.x - from.position.x, machine.position.y - from.position.y
  local d = math.sqrt(dx * dx + dy * dy)
  local is_pole = from.type == "electric-pole"
  for _, step in ipairs(is_pole and { reach, reach - 1.5, reach - 3 } or { 3, 4, 2 }) do
    step = math.min(step, math.max(d - supply - 1, 1))
    local at = s.find_non_colliding_position(pp.name, { x = from.position.x + dx / d * step, y = from.position.y + dy / d * step }, 2, 0.5, true)
    if at and (not is_pole or math.sqrt(dist2(at, from.position)) <= reach) then
      return { kind = "place", item = item, at = at, quiet = true, fixed = true }
    end
  end
  return nil, "No room for poles between the power and the " .. pretty(machine.name) .. "."
end

-- no free machine for recipe r: power one that's standing dark, else make one (burner-powered first) and set it up
local function need_machine(m, r, item, depth)
  local e = m.entity
  for _, f in pairs(e.surface.find_entities_filtered({ type = { "furnace", "assembling-machine" }, force = e.force,
    position = anchor(m), radius = RADIUS })) do
    if f.prototype.crafting_categories[r.category] and f.status == defines.entity_status.no_power then
      return power_to(m, f, depth)
    end
  end
  local options = {}
  for name, p in pairs(prototypes.get_entity_filtered({ { filter = "crafting-category", crafting_category = r.category } })) do
    local it = (p.type == "furnace" or p.type == "assembling-machine") and p.items_to_place_this and p.items_to_place_this[1]
    if it and (not p.fixed_recipe or p.fixed_recipe == r.name) then
      local score = (p.burner_prototype and 0 or 2) + (have_count(m, it.name) > 0 and 0 or 1)
      options[#options + 1] = { item = it.name, score = score }
    end
  end
  table.sort(options, function(a, b) if a.score ~= b.score then return a.score < b.score end return a.item < b.item end)
  local why = "Nothing I can build makes " .. pretty(item) .. "."
  for _, o in ipairs(options) do
    if have_count(m, o.item) > 0 then return { kind = "place", item = o.item } end
    local job, w = plan(m, o.item, 1, depth + 1)
    if job then return job end
    why = w or why
  end
  return nil, why
end

-- the next job towards having n more of item; nil and why when nothing gets there
plan = function(m, item, n, depth)
  depth = depth or 0
  if depth > 10 then return nil, "That's too many steps for me." end
  local e = m.entity
  if nearest_source(m, { item = item, skip = {} }) then return { kind = "mine", item = item, count = math.min(n, 50) } end
  local r = handcraft_recipe(e.force, item)
  if r then
    local batch = math.min(n, 20)
    local missing = gather(m, r, math.ceil(batch / product_amount(r, item)), true)
    if not missing then return { kind = "craft", recipe = item, count = batch } end
    for ing, k in pairs(missing) do return plan(m, ing, k, depth + 1) end
  end
  local mr = machine_recipe(e.force, item)
  if mr then
    local machines = machines_for(m, mr, item)
    if #machines == 0 then return need_machine(m, mr, item, depth) end
    local per = product_amount(mr, item)
    local runs = math.ceil(math.min(n, 50) / per)
    local own = e.get_main_inventory()
    for _, ing in pairs(mr.ingredients) do
      local have = own.get_item_count(ing.name) + available(m, ing.name)
      if have < ing.amount then return plan(m, ing.name, ing.amount * runs - have, depth + 1) end
      runs = math.min(runs, math.floor(have / ing.amount))
    end
    for _, f in pairs(machines) do
      if needs_fuel(f) and not fuel_available(m) then
        return plan(m, nearest_source(m, { item = "coal", skip = {} }) and "coal" or "wood", 20, depth + 1)
      end
    end
    return { kind = "smelt", item = item, recipe = mr.name, count = runs * per }
  end
  local locked = e.force.recipes[item]
  if locked and not locked.enabled then return nil, pretty(item) .. " isn't researched yet." end
  return nil, "I don't know how to make " .. pretty(item) .. "."
end

-- ------------------------------------------------------------------------------------------------ bpgen lines

-- a line from bpgen for a goal: {state = "asked"|"placed", box = {x, y, w, h}, inputs = {{items, position}},
-- outputs = {{item, position}}}. bpgen places its ghosts; the crew build them (auto build), power and fuel it, feed
-- its inputs by hand and empty its output.

local function in_box(box, pos, pad)
  pad = pad or 0
  return pos.x >= box[1] - pad and pos.y >= box[2] - pad and pos.x <= box[1] + box[3] + pad and pos.y <= box[2] + box[4] + pad
end

local function box_area(box) return { { box[1] - 1, box[2] - 1 }, { box[1] + box[3] + 1, box[2] + box[4] + 1 } } end

local function belt_at(s, pos)
  return s.find_entities_filtered({ type = { "transport-belt", "underground-belt", "splitter" }, position = pos, radius = 0.5, limit = 1 })[1]
end

local function on_belt(b, item)
  local n = 0
  for i = 1, 2 do n = n + b.get_transport_line(i).get_item_count(item) end
  return n
end

-- the next job the line needs, or "wait" while its ghosts are still being built, or nil when it's running
local function line_step(m, g, depth)
  local e, ln = m.entity, g.line
  local s = e.surface
  local area = box_area(ln.box)
  if s.count_entities_filtered({ area = area, type = { "entity-ghost", "tile-ghost" }, force = e.force, limit = 1 }) > 0 then
    return "wait"
  end
  for _, f in pairs(s.find_entities_filtered({ area = area, type = { "assembling-machine", "furnace", "inserter", "lab" }, force = e.force })) do
    if f.status == defines.entity_status.no_power then
      local job = power_to(m, f, depth)
      return job or "wait"
    end
  end
  for _, o in pairs(ln.outputs or {}) do
    local n = 0
    for _, b in pairs(s.find_entities_filtered({ type = { "transport-belt", "underground-belt" }, position = o.position, radius = 4 })) do
      n = n + on_belt(b, o.item)
    end
    if n >= 8 then return { kind = "collect", item = o.item, at = o.position } end
  end
  for _, i in pairs(ln.inputs or {}) do
    local b = belt_at(s, i.position)
    if b then
      for k, item in ipairs(i.items) do
        if prototypes.item[item] and on_belt(b, item) < 3 then
          -- (two inputs on one belt: a lane each, as bpgen's lines take them)
          local lane = #i.items == 2 and k or nil
          if have_count(m, item) > 0 then return { kind = "feed", item = item, at = i.position, count = 40, lane = lane } end
          local job = plan(m, item, 40, depth + 1)
          if job then return job end
        end
      end
    end
  end
end

-- puts items on a line's input belt (both lanes) until count is in or it runs out; waits while the belt is full
JOBS.feed = function(m, job)
  local e = m.entity
  local inv = e.get_main_inventory()
  local b = belt_at(e.surface, job.at)
  if not b then return true end
  if not go(m, job.at, math.max(e.reach_distance - 2, 2)) then return false end
  local have = inv.get_item_count(job.item)
  if have < job.count - job.n then have = have + take(m, job.item, job.count - job.n - have) end
  job.since = job.since or game.tick
  for lane = job.lane or 1, job.lane or 2 do
    local tl = b.get_transport_line(lane)
    while have > 0 and job.n < job.count and tl.can_insert_at_back() do
      tl.insert_at_back({ name = job.item, count = 1 })
      inv.remove({ name = job.item, count = 1 })
      have, job.n, job.since = have - 1, job.n + 1, game.tick
    end
  end
  m.fed = (m.fed or 0)
  if job.n >= job.count or have == 0 or game.tick - job.since > 1800 then
    m.fed = m.fed + job.n
    return true
  end
  return false
end

-- takes the product off the belts at a line's output and delivers it
JOBS.collect = function(m, job)
  local e = m.entity
  if not go(m, job.at, math.max(e.reach_distance - 3, 2)) then return false end
  local inv = e.get_main_inventory()
  for _, b in pairs(e.surface.find_entities_filtered({ type = { "transport-belt", "underground-belt" }, position = job.at, radius = 4 })) do
    for lane = 1, 2 do
      local tl = b.get_transport_line(lane)
      local n = tl.get_item_count(job.item)
      local got = n > 0 and inv.insert({ name = job.item, count = n }) or 0
      if got > 0 then
        tl.remove_item({ name = job.item, count = got })
        job.n = job.n + got
      end
    end
  end
  m.collected = (m.collected or 0) + job.n
  if job.n > 0 then table.insert(m.jobs, 2, { kind = "deliver" }) end
  return true
end

local function ask_line(m, g)
  local p = m.owner and game.get_player(m.owner)
  local bp = remote.interfaces["bpgen"]
  if not (bp and bp.plan_line) then
    g.line = false
    return
  end
  g.line = { state = "asked", tick = game.tick }
  remote.call("bpgen", "plan_line", p and p.index or m.owner, g.item, g.rate or 30, "ai-crew")
  say(m, "Asking bpgen for a " .. pretty(g.item) .. " line.")
end

-- ----------------------------------------------------------------------------------------------------------- combat

local GUNS -- hand-held guns, longest range first

local AMMO_OF = {} -- gun -> the ammo items it fires (its ammo categories)

local function gun_ammo(g)
  if not AMMO_OF[g] then
    local ap = prototypes.item[g].attack_parameters
    local cats = {}
    for _, c in pairs(ap.ammo_categories or { ap.ammo_category }) do cats[c] = true end
    local list = {}
    for name, it in pairs(prototypes.get_item_filtered({ { filter = "type", type = "ammo" } })) do
      local ok, cat = pcall(function() return it.ammo_category.name end)
      if ok and cats[cat] and not it.hidden then list[#list + 1] = name end
    end
    table.sort(list)
    AMMO_OF[g] = list
  end
  return AMMO_OF[g]
end

local function gun_range(m)
  local g = m.entity.get_inventory(defines.inventory.character_guns)
  local best = 0
  for i = 1, g and #g or 0 do
    local ammo = m.entity.get_inventory(defines.inventory.character_ammo)
    if g[i].valid_for_read and ammo and ammo[i] and ammo[i].valid_for_read then
      local ap = g[i].prototype.attack_parameters
      best = math.max(best, ap and ap.range or 0)
    end
  end
  return best
end

-- armor if it has none; a gun its ammo exists for and that ammo in the slot beside it (taken from the owner, chests
-- near them, the network; made when there's none)
local function arm(m)
  local e = m.entity
  local guns, ammo, inv = e.get_inventory(defines.inventory.character_guns), e.get_inventory(defines.inventory.character_ammo),
    e.get_main_inventory()
  if not (guns and ammo) then return end
  if not GUNS then
    GUNS = {}
    for name, it in pairs(prototypes.get_item_filtered({ { filter = "type", type = "gun" } })) do
      if not it.hidden and it.attack_parameters then GUNS[#GUNS + 1] = name end
    end
    table.sort(GUNS, function(a, b) return prototypes.item[a].attack_parameters.range > prototypes.item[b].attack_parameters.range end)
  end
  local armor = e.get_inventory(defines.inventory.character_armor)
  if armor and armor.is_empty() then -- the best armor to hand (most resistance)
    local best, bs
    for name, it in pairs(prototypes.get_item_filtered({ { filter = "type", type = "armor" } })) do
      if not it.hidden and (inv.get_item_count(name) > 0 or available(m, name) > 0) then
        local score = 0
        for _, r in pairs(it.resistances or {}) do score = score + (r.percent or 0) * 100 + (r.decrease or 0) end
        if not bs or score > bs then best, bs = name, score end
      end
    end
    if best then
      if inv.get_item_count(best) == 0 then take(m, best, 1) end
      if armor.insert({ name = best, count = 1 }) > 0 then inv.remove({ name = best, count = 1 }) end
    end
  end
  -- ammo sitting beside no gun goes back to its pockets
  for i = 1, #ammo do
    if ammo[i].valid_for_read and not (guns[i] and guns[i].valid_for_read) then
      local n = inv.insert(ammo[i])
      if n >= ammo[i].count then ammo[i].clear() elseif n > 0 then ammo[i].count = ammo[i].count - n end
    end
  end
  local function has(item) return inv.get_item_count(item) > 0 or available(m, item) > 0 end
  local function makes(item) local r = e.force.recipes[item] return r and r.enabled end
  -- for gun g: 2 and the ammo when some is in stock, 1 when some can be made, 0 when neither
  local function ammo_for(g)
    local can = 0
    for _, a in ipairs(gun_ammo(g)) do
      if has(a) then return 2, a end
      if makes(a) then can = 1 end
    end
    return can
  end
  local cur = guns[1].valid_for_read and guns[1].name or nil
  if not (cur and (ammo[1].valid_for_read or ammo_for(cur) == 2)) then
    -- the gun to use: one to hand with ammo in stock, else one to hand whose ammo it can make, else one to make
    -- whose ammo is in stock, else one to make with ammo to make; longest range first among equals
    local pick, ps
    for _, g in ipairs(GUNS) do
      local a = ammo_for(g)
      local held = g == cur or has(g)
      local score = a == 0 and 0 or (held and (a == 2 and 6 or 5)) or (makes(g) and (a == 2 and 4 or 3)) or 0
      if score > 0 and (not ps or score > ps) then pick, ps = g, score end
    end
    if pick and pick ~= cur then
      if cur then
        if inv.insert(guns[1]) > 0 then guns[1].clear() end
      end
      if has(pick) then
        if inv.get_item_count(pick) == 0 then take(m, pick, 1) end
        if inv.get_item_count(pick) > 0 and guns[1].set_stack({ name = pick, count = 1 }) then inv.remove({ name = pick, count = 1 }) end
      else
        if add_need(m.owner, pick, 1, "a gun for " .. m.name) then say(m, "No gun to hand. I'll make a " .. pretty(pick) .. ".") end
        return
      end
    end
  end
  local gun = guns[1].valid_for_read and guns[1].name
  if not gun then return end
  if ammo[1].valid_for_read and ammo[1].count >= 10 then return end
  local state, a = ammo_for(gun)
  if state == 2 then
    local stack = prototypes.item[a].stack_size
    if inv.get_item_count(a) < stack then take(m, a, stack - inv.get_item_count(a)) end
    local cnt = inv.get_item_count(a)
    if not ammo[1].valid_for_read then
      if cnt > 0 and ammo[1].set_stack({ name = a, count = math.min(cnt, stack) }) then inv.remove({ name = a, count = math.min(cnt, stack) }) end
    elseif ammo[1].name == a then
      local add = math.min(cnt, stack - ammo[1].count)
      if add > 0 then
        ammo[1].count = ammo[1].count + add
        inv.remove({ name = a, count = add })
      end
    end
  elseif state == 1 and not ammo[1].valid_for_read then
    for _, am in ipairs(gun_ammo(gun)) do
      if makes(am) then
        if add_need(m.owner, am, 20, "ammo for the " .. pretty(gun)) then say(m, "Out of ammo. Making " .. pretty(am) .. ".") end
        break
      end
    end
  end
end

-- every half second: shoot what's in range, fall back to the owner when hurt, come back when healed
local function fight(m)
  local e = m.entity
  local hp = e.health / e.max_health
  if hp < 0.7 and prototypes.item["raw-fish"] then -- a fish heals, as a player's would
    local inv = e.get_main_inventory()
    if inv.get_item_count("raw-fish") == 0 and available(m, "raw-fish") > 0 then take(m, "raw-fish", 5) end
    if inv.get_item_count("raw-fish") > 0 and game.tick >= (m.fish_at or 0) then
      inv.remove({ name = "raw-fish", count = 1 })
      e.health = e.health + 80
      m.fish_at = game.tick + 30
      hp = e.health / e.max_health
    end
  end
  if m.retreat then
    if hp > 0.8 then m.retreat = nil end
  elseif hp < 0.5 then
    m.retreat, m.target = true, nil
    e.shooting_state = { state = defines.shooting.not_shooting, position = e.position }
    stop_mining(m)
    go(m, anchor(m), 4)
    say(m, pick({ "I'm hurt, falling back!", "Taking a beating, pulling back!", "Need a breather!" }))
    return
  end
  if m.defend == false and not (m.jobs[1] and m.jobs[1].kind == "attack") then m.target = nil return end
  local range = gun_range(m)
  if range == 0 then
    arm(m)
    range = gun_range(m)
  end
  local enemy = range > 0 and not m.retreat and e.surface.find_nearest_enemy({ position = e.position, max_distance = range, force = e.force })
  if enemy and not m.target then
    if not m.said_fight or game.tick - m.said_fight > 1800 then
      m.said_fight = game.tick
      say(m, pick({ "Contact!", "Hostiles!", "Biters, here we go.", "Weapons free." }))
    end
  end
  m.target = enemy
  if enemy and enemy.valid then
    local ammo = e.get_inventory(defines.inventory.character_ammo)
    if ammo and ammo.get_item_count() < 5 then arm(m) end
  end
end

-- destroys enemy spawners and worms near the owner, nearest first; the shooting is fight()'s
JOBS.attack = function(m, job)
  local e = m.entity
  if m.retreat then return false end
  if gun_range(m) == 0 then
    arm(m)
    if gun_range(m) == 0 then say(m, "I need a gun and ammo for that.") return true end
  end
  local t = job.target
  if not (t and t.valid) then
    if job.target then job.n = job.n + 1 end
    t = nil
    local bd
    for _, c in pairs(e.surface.find_entities_filtered({ type = { "unit-spawner", "turret" }, position = anchor(m), radius = job.radius or 96 })) do
      if e.force.is_enemy(c.force) then
        local d = dist2(e.position, c.position)
        if not bd or d < bd then t, bd = c, d end
      end
    end
    job.target = t
    if not t then
      say(m, job.n > 0 and ("Cleared " .. job.n .. " nest" .. (job.n > 1 and "s" or "") .. ".") or "No nests around here.")
      return true
    end
  end
  go(m, t.position, math.max(gun_range(m) - 3, 4))
  return false
end

-- with nothing else to do, one step towards what the crew needs, else the owner's goal
local function goal_step(m)
  if game.tick < (m.goal_wait or 0) then return end
  local key = m.owner or 0
  local list = needs(m.owner)
  local g, is_need = list[1], true
  if not g then g, is_need = goals()[key], false end
  if not g then return end
  local have = goal_have(m.owner, g.item)
  g.count = g.count or (have + g.more)
  if have >= g.count then
    if not is_need then
      goals()[key] = nil
      ada("Goal reached: " .. g.count .. " " .. pretty(g.item) .. ". Well done, pioneer.")
      return
    end
    table.remove(list, 1)
    for _, o in pairs(crew()) do if o.owner == m.owner then o.auto_wait = nil end end -- the blueprint can go on
    say(m, "Got the " .. pretty(g.item) .. (g.reason and (" for " .. g.reason) or "") .. ".")
    if g.after then
      g.after.n, g.after.skip = 0, {}
      m.jobs[#m.jobs + 1] = g.after
      return true
    end
    return
  end
  if not is_need and g.use_line then
    if g.line == nil then return ask_line(m, g) end
    if g.line and g.line.state == "asked" then
      if game.tick - g.line.tick > 18000 then g.line = false else return end -- (bpgen may measure inserters first)
    end
    if g.line and g.line.state == "placed" then
      local lj = line_step(m, g, 0)
      if lj == "wait" then
        g.step = "building the line"
        m.goal_wait = game.tick + 300
        return
      end
      if lj then
        g.why, g.step = nil, m.name .. ": " .. (DOING_WORD[lj.kind] or lj.kind) .. " " .. pretty(lj.item or lj.recipe or "") .. " (line)"
        lj.n, lj.skip, lj.goal = 0, {}, true
        m.jobs[#m.jobs + 1] = lj
        return true
      end
    end
  end
  local job, why = plan(m, g.item, g.count - have)
  if not job then
    if is_need then
      table.remove(list, 1)
      say(m, why)
      return
    end
    if g.why ~= why then say(m, why) end
    g.why, g.step = why, "stuck"
    m.goal_wait = game.tick + 600
    return
  end
  g.why = nil
  g.step = m.name .. ": " .. (DOING_WORD[job.kind] or job.kind) .. " " .. pretty(job.item or job.recipe)
  job.n, job.skip, job.goal = 0, {}, true
  m.jobs[#m.jobs + 1] = job
  return true
end

-- with nothing queued: like a construction bot (marks, then ghosts near the owner), then the goal, then follow
local function idle(m)
  if game.tick >= (m.next_scan or 0) then
    m.next_scan = game.tick + 120
    if m.auto ~= false and game.tick >= (m.auto_wait or 0) then
      local e = m.entity
      local area = { position = anchor(m), radius = RADIUS, limit = 1, to_be_deconstructed = true }
      local kind
      if e.surface.count_entities_filtered(area) > 0 then kind = "deconstruct" end
      area.to_be_deconstructed, area.type, area.force = nil, { "entity-ghost", "tile-ghost" }, e.force
      if not kind and e.surface.count_entities_filtered(area) > 0 then kind = "build" end
      if kind then
        m.jobs[1] = { kind = kind, auto = true, n = 0, skip = {} }
        return
      end
    end
    if game.tick >= (m.tend_at or 0) then
      m.tend_at = game.tick + 600
      if fuel_available(m) and #low_burners(m, 1) > 0 then
        m.jobs[1] = { kind = "tend", auto = true, n = 0, skip = {} }
        return
      end
    end
    if goal_step(m) then return end
  end
  if not m.follow then return end
  local c = owner_char(m)
  if c and dist2(m.entity.position, c.position) > 100 then go(m, c.position, 4) end
end

local function think(m)
  local job = m.jobs[1]
  if not job then return idle(m) end
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

local function hire(name, surface, position, force, owner)
  local taken = {}
  for n in pairs(crew()) do taken[n:lower()] = true end
  if not name then
    for _, n in ipairs(NAMES) do if not taken[n:lower()] then name = n break end end
    name = name or ("Crew" .. (table_size(crew()) + 1))
  end
  if taken[name:lower()] then return nil, name .. " is already on the crew." end
  local at = surface.find_non_colliding_position("character", position, 10, 0.5) or position
  local e = surface.create_entity({ name = "character", position = at, force = force })
  if not e then return nil, "No room to spawn a crew member." end
  local i = table_size(crew())
  local color = COLORS[i % #COLORS + 1]
  e.color = { r = color[1], g = color[2], b = color[3] }
  rendering.draw_text({ text = name, surface = surface, target = { entity = e, offset = { 0, -2.3 } }, color = color,
    scale = 0.9, alignment = "center" })
  local m = { name = name, entity = e, owner = owner, home = { x = at.x, y = at.y }, jobs = {}, color = color,
    voice = i, follow = true, phase = i * 3 }
  crew()[name] = m
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
      elseif plan(m, it, count) then return { kind = "need", item = it, count = count }
      else kind = "fetch" end
    end
    return { kind = kind, item = it, count = count }
  elseif kind == "goal" then
    local use_line = extra and extra.line
    if type(item) == "string" and item:find("%f[%a]line%s*$") then item, use_line = item:gsub("%s*line%s*$", ""), true end
    local it = resolve_item(item)
    if not it then return end
    return { kind = "goal", item = it, count = math.min(math.max(count or 100, 1), 100000), use_line = use_line and true or nil,
      rate = extra and tonumber(extra.rate) }
  elseif kind == "build" or kind == "deconstruct" or kind == "deliver" then
    return { kind = kind }
  elseif kind == "attack" then
    return { kind = "attack" }
  elseif kind == "follow" or kind == "stay" or kind == "stop" then
    return { kind = kind }
  end
end

local VERBS = { build = "build", construct = "build", clear = "deconstruct", deconstruct = "deconstruct",
  demolish = "deconstruct", remove = "deconstruct", mine = "mine", gather = "get", collect = "get", get = "get",
  fetch = "get", bring = "get", grab = "get", craft = "craft", make = "craft", follow = "follow", come = "follow",
  stay = "stay", wait = "stay", stop = "stop", goal = "goal", aim = "goal", attack = "attack", fight = "attack",
  kill = "attack", halt = "stop", cancel = "stop", deliver = "deliver", unload = "deliver" }

-- a plain command ("get 50 iron ore", "build") -> kind, item words, count; nil for anything else
local function parse(text)
  local words = {}
  for w in text:lower():gsub("[%.,!%?]", " "):gmatch("%S+") do words[#words + 1] = w end
  while words[1] == "please" or words[1] == "can" or words[1] == "you" do table.remove(words, 1) end
  local kind = VERBS[words[1] or ""]
  if not kind then return end
  table.remove(words, 1)
  if kind == "build" or kind == "deconstruct" or kind == "stop" or kind == "stay" or kind == "deliver" or kind == "attack" then
    return #words <= 2 and kind or nil -- "build" / "clear it" / "stop now", nothing longer
  end
  if kind == "follow" then return (#words <= 2) and kind or nil end
  local count
  for i, w in ipairs(words) do
    if tonumber(w) then count = tonumber(w) table.remove(words, i) break end
  end
  if words[1] == "me" then table.remove(words, 1) end
  if #words == 0 or #words > 5 then return end
  return kind, table.concat(words, " "), count
end

local function add_job(m, job)
  if job.kind == "stop" then
    for _, j in pairs(m.jobs) do if j.target and j.target.valid and j.target.unit_number then claims()[j.target.unit_number] = nil end end
    m.jobs = {}
    stop_walk(m)
    stop_mining(m)
  elseif job.kind == "follow" then
    m.follow = true
  elseif job.kind == "need" then
    add_need(m.owner, job.item, job.count, "you")
  elseif job.kind == "goal" then
    goals()[m.owner or 0] = { item = job.item, count = job.count, use_line = job.use_line, rate = job.rate }
    m.goal_wait = nil
  elseif job.kind == "stay" then
    m.follow = false
    stop_walk(m)
  else
    job.n, job.skip = 0, {}
    m.jobs[#m.jobs + 1] = job
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
    ctx.crew[#ctx.crew + 1] = { name = m.name, doing = m.jobs[1] and m.jobs[1].kind or (m.follow and "following" or "waiting"),
      queued = #m.jobs, carrying = inv }
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
  -- management
  local verb, arg = cmd:match("^(%S+)%s*(%S*)")
  if all and (verb == "hire" or verb == "recruit") then
    if #members >= MAX_CREW then return tell(player, "The crew is full (" .. MAX_CREW .. ").") end
    local c = player and player.character
    if not c then return tell(player, "Stand somewhere first: crew members spawn next to your character.") end
    local name = rest:match("^%S+%s+(%S+)")
    local m, err = hire(name and (name:sub(1, 1):upper() .. name:sub(2)), c.surface, c.position, c.force, owner)
    if not m then return tell(player, err) end
    ada("New crew member registered: " .. m.name .. ".")
    return say(m, pick({ "Reporting for duty.", "Ready to work.", "Where do you need me?" }))
  elseif all and (verb == "fire" or verb == "dismiss") then
    local m = find_member(arg, owner)
    if not m then return tell(player, "No crew member called " .. arg .. ".") end
    say(m, "See you around.")
    unload(m)
    if m.entity.valid then m.entity.destroy() end
    crew()[m.name] = nil
    return
  elseif all and (verb == "list" or verb == "status") or verb == "status" then
    if #members == 0 then return tell(player, "No crew yet: press Hire in the crew window.") end
    for _, m in pairs(members) do
      tell(player, m.name .. ": " .. (m.jobs[1] and m.jobs[1].kind or (m.follow and "following" or "waiting")) ..
        (#m.jobs > 1 and (" (+" .. (#m.jobs - 1) .. " queued)") or ""))
    end
    return
  elseif verb == "auto" then
    for _, m in pairs(members) do m.auto = arg ~= "off" end
    return tell(player, (arg ~= "off" and "Auto build and clear on" or "Auto build and clear off: only on orders") ..
      " for " .. (all and "the crew" or members[1].name) .. ".")
  elseif verb == "help" or cmd == "" then
    return help(player)
  end
  if #members == 0 then return tell(player, "No crew yet: press Hire in the crew window.") end
  -- plain commands run without the LLM
  local kind, item, count = parse(rest)
  if kind then
    local targets = members
    if not (kind == "build" or kind == "deconstruct" or kind == "stop" or kind == "follow" or kind == "stay" or kind == "deliver" or kind == "attack") then
      targets = { busiest_last(members) }
    end
    for i, m in ipairs(targets) do
      local job = job_for(m, kind, item, count)
      if not job then return tell(player, "I don't know an item called \"" .. tostring(item) .. "\".") end
      add_job(m, job)
      if i == 1 then say(m, pick(ACKS[job.kind] or ACKS.build)) end
    end
    return
  end
  -- anything else: the LLM
  local llm = llm_settings(player)
  if not py() or llm.provider == "off" then
    tell(player, "I only understand simple orders without the fnative loader and an AI provider.")
    return help(player)
  end
  local names = {}
  for _, m in pairs(members) do names[#names + 1] = m.name end
  local id, err = native.start("py", "aicrew:ask", helpers.table_to_json({ message = rest, to = names, llm = llm,
    context = context(player, members_of(owner)) }))
  if not id then return tell(player, "AI call failed: " .. tostring(err)) end
  pending[id] = { kind = "ask", owner = owner, to = names }
  for _, m in pairs(members) do
    if m.bubble and m.bubble.valid then m.bubble.destroy() end
    m.bubble = rendering.draw_text({ text = "...", surface = m.entity.surface, target = { entity = m.entity, offset = { 0, -2.9 } },
      color = m.color, scale = 1.4, alignment = "center", time_to_live = 600 })
  end
end

-- -------------------------------------------------------------------------------------------------- AFK chatter

local IDLE_LINES = {
  "Quiet out here. You can hear the belts humming.",
  "Do you think the pioneer knows we talk when they're away?",
  "I counted the trees again. Still too many.",
  "One more hand-crafted gear wheel and I'm asking for a transfer.",
  "Biters have been quiet. I don't like it.",
  "I've been thinking about spaghetti. The belt kind.",
  "One day robots will do all this. Then what do we do?",
  "I named that iron chest Gerald. Don't tell anyone.",
  "Smelting is just cooking for rocks, if you think about it.",
  "If the pioneer asks, I was working the whole time.",
}
local REPLIES = { "Don't jinx it.", "Hah. Fair.", "Back to work, %s.", "I was about to say the same.", "Mm-hm.",
  "You worry too much, %s.", "Shh, they might hear you.", "Sure, %s. Sure." }
local lines = {} -- chatter waiting its turn: {at, owner, who, text} (not saved)

local function canned(owner, members)
  local a = pick(members)
  local g = storage.goals and storage.goals[owner]
  local text = g and math.random() < 0.4 and string.format("Still on that goal: %d %s. We'll get there.", g.count, pretty(g.item))
    or pick(IDLE_LINES)
  lines[#lines + 1] = { at = game.tick, owner = owner, who = a.name, text = text }
  if #members > 1 then
    local b
    repeat b = pick(members) until b ~= a
    lines[#lines + 1] = { at = game.tick + 240, owner = owner, who = b.name, text = string.format(pick(REPLIES), a.name) }
  end
end

-- while the player is away: the crew talk among themselves (the LLM writes it when there's one, else canned lines)
local function chatter(player)
  local members = members_of(player.index)
  if #members == 0 then return end
  local llm = llm_settings(player)
  if py() and llm.provider ~= "off" then
    local ctx = context(player, members)
    ctx.goal = storage.goals and storage.goals[player.index]
    local id = native.start("py", "aicrew:banter", helpers.table_to_json({ llm = llm, context = ctx }))
    if id then
      pending[id] = { kind = "banter", owner = player.index }
      return
    end
  end
  canned(player.index, members)
end

local function on_answer(p, out)
  local player = p.owner and game.get_player(p.owner)
  local a = helpers.json_to_table(out) or { error = "unreadable answer" }
  if p.kind == "ada" then
    local text = type(a.text) == "string" and a.text ~= "" and a.text or p.text
    game.print("[color=" .. ADA_COLOR .. "][ADA][/color] " .. text)
    return speak(text, "ada")
  end
  if p.kind == "check" then
    storage.ai = storage.ai or {}
    if not (a.provider or a.error) then a.error = "no answer" end
    storage.ai[p.owner] = a
    return
  end
  if p.kind == "banter" then
    local members = members_of(p.owner)
    if #members == 0 then return end
    local at = game.tick
    for _, r in pairs(type(a.replies) == "table" and a.replies or {}) do
      if type(r) == "table" and type(r.text) == "string" and r.text ~= "" then
        local m = find_member(r.who, p.owner) or members[1]
        lines[#lines + 1] = { at = at, owner = p.owner, who = m.name, text = r.text:sub(1, 200) }
        at = at + 300
      end
    end
    if at == game.tick then canned(p.owner, members) end
    return
  end
  local fallback = find_member(p.to[1], p.owner)
  if a.error then
    if fallback and fallback.bubble and fallback.bubble.valid then fallback.bubble.destroy() end
    return tell(player, "[ai-crew] " .. tostring(a.error))
  end
  for _, r in pairs(a.replies or {}) do
    local m = find_member(r.who, p.owner) or fallback
    if m and type(r.text) == "string" and r.text ~= "" then say(m, r.text:sub(1, 300)) end
  end
  for _, j in pairs(a.jobs or {}) do
    local m = find_member(j.who, p.owner) or fallback
    local job = m and type(j.kind) == "string" and job_for(m, j.kind, j.item, tonumber(j.count), j)
    if job then add_job(m, job) end
  end
end

-- ------------------------------------------------------------------------------------------------------------ panel
-- The crew button (top left) opens a window: movable and resizable with the fnative-std library, a plain movable one
-- without. The chat box, then tabs: Crew, Orders, Goal, AI.

local mod_gui = require("mod-gui")
local fstd = script.active_mods["fnative-std"] and require("__fnative-std__/window") or nil
local WIN = "aic_window"
local PROVIDER_CHOICES, TOGGLES
local ADA_VOICES = { "ava", "jenny", "aria", "emma", "michelle" }
local DOING = DOING_WORD

local function goal_text(owner)
  local nd = needs(owner)[1]
  if nd then
    return string.format("Working for: %s %s%s%s%s", nd.count and (goal_have(owner, nd.item) .. " / " .. nd.count) or nd.more,
      pretty(nd.item), nd.reason and (" (for " .. nd.reason .. ")") or "", nd.step and (" - " .. nd.step) or "",
      #needs(owner) > 1 and (", then " .. (#needs(owner) - 1) .. " more") or "")
  end
  local g = storage.goals and storage.goals[owner]
  if not g then return "No goal. Pick an item and how many you want to have: the crew mine, smelt, craft and build towards it." end
  return string.format("Goal: %d / %d %s%s%s", goal_have(owner, g.item), g.count, pretty(g.item),
    g.line and (g.line.state == "asked" and " - bpgen is planning a line" or " (line)") or "",
    g.why and (" - " .. g.why) or (g.step and (" - " .. g.step) or ""))
end

local function status_text(m)
  if m.retreat then return "falling back, hurt" end
  if m.target and m.target.valid then return "fighting " .. pretty(m.target.name) end
  local j = m.jobs[1]
  if not j then return m.follow and "following you" or "waiting here" end
  local s = DOING[j.kind] or j.kind
  if j.kind == "mine" then s = s .. " " .. pretty(j.item) .. " " .. (j.n or 0) .. "/" .. j.count
  elseif j.kind == "craft" or j.kind == "fetch" then s = s .. " " .. j.count .. " " .. pretty(j.recipe or j.item)
  elseif j.kind == "smelt" or j.kind == "feed" or j.kind == "place" then s = s .. " " .. pretty(j.item or j.recipe or "")
  elseif j.auto then s = s .. " (auto)" end
  if #m.jobs > 1 then s = s .. " +" .. (#m.jobs - 1) end
  return s
end

local function ui(player)
  storage.ui = storage.ui or {}
  storage.ui[player.index] = storage.ui[player.index] or { count = "50", who = 1 }
  return storage.ui[player.index]
end

-- the AI tab's lines: loader, provider and key, the last test, voices
local function ai_lines(player)
  local a = storage.ai and storage.ai[player.index]
  local llm = llm_settings(player)
  local out = {}
  if not py() then
    out[1] = "[color=1,0.4,0.4]Not started through the fnative loader:[/color] chat, voices and bpgen lines are off. Orders, goals and building work."
    return out
  end
  if llm.provider == "off" then out[1] = "Chat AI is off (provider above). Plain orders still work." return out end
  if not a then out[1] = "Not tested yet: press Test." return out end
  if a.provider then
    out[#out + 1] = "Provider: " .. a.provider .. (a.key and ("   key " .. a.key) or "") .. (a.source and ("  (from " .. a.source .. ")") or "")
  end
  if a.model then out[#out + 1] = "Model: " .. a.model end
  out[#out + 1] = a.ok and string.format("[color=0.4,1,0.4]Connected[/color]: answered in %.1f s.", a.seconds or 0)
    or ("[color=1,0.4,0.4]Not working[/color]: " .. tostring(a.error))
  out[#out + 1] = "Voices: " .. tostring(a.tts or "-")
  return out
end

PROVIDER_CHOICES = { "auto", "openrouter", "groq", "gemini", "cerebras", "mistral", "pollinations", "ollama", "off" }
TOGGLES = {
  { "voices", "Crew speak out loud", "Text to speech for the crew's lines (edge-tts voices if installed, else Windows')" },
  { "ada", "ADA announces milestones", "Research done, first science, rocket launches, deaths" },
  { "ada-llm", "ADA words her lines with the AI", "One AI request per announcement" },
  { "chatter", "Crew chatter while you're away", "After 2 minutes without input, every minute or so" },
}

local function ai_short(player)
  local a = storage.ai and storage.ai[player.index]
  if not py() then return "[color=0.7,0.7,0.7]AI chat off (no fnative loader)[/color]" end
  if not a then return "[color=0.7,0.7,0.7]AI chat not tested (Settings tab)[/color]" end
  return a.ok and ("[color=0.4,1,0.4]AI chat: " .. tostring(a.provider) .. "[/color]") or "[color=1,0.4,0.4]AI chat not working (Settings tab)[/color]"
end

local function check_ai(player)
  if not py() then return end
  local id = native.start("py", "aicrew:check", helpers.table_to_json({ llm = llm_settings(player) }))
  if id then
    pending[id] = { kind = "check", owner = player.index }
    storage.ai = storage.ai or {}
    storage.ai[player.index] = storage.ai[player.index] or {}
    storage.ai[player.index].testing = true
  end
end

local function add_button(player)
  local flow = mod_gui.get_button_flow(player)
  if not flow.aic_toggle then
    flow.add({ type = "sprite-button", name = "aic_toggle", sprite = "entity/character", style = mod_gui.button_style,
      tooltip = "AI Crew" })
  end
end

local function btn(parent, caption, action, who, tooltip, width)
  local b = parent.add({ type = "button", caption = caption, tags = { aic = action, who = who }, tooltip = tooltip })
  b.style.minimal_width = 0
  b.style.width = width or 72
  return b
end

local function find_el(root, name)
  if root.name == name then return root end
  for _, c in pairs(root.children) do
    local r = find_el(c, name)
    if r then return r end
  end
end

local function new_window(player)
  if fstd then
    return fstd.create(player, { name = WIN, title = "AI Crew", width = 640, height = 470, min_width = 520, min_height = 300 })
  end
  local screen = player.gui.screen
  if screen[WIN] then screen[WIN].destroy() end
  local frame = screen.add({ type = "frame", name = WIN, direction = "vertical" })
  local bar = frame.add({ type = "flow", direction = "horizontal" })
  bar.drag_target = frame
  bar.add({ type = "label", caption = "AI Crew", style = "frame_title", ignored_by_interaction = true })
  local filler = bar.add({ type = "empty-widget", style = "draggable_space_header", ignored_by_interaction = true })
  filler.style.height = 24
  filler.style.horizontally_stretchable = true
  bar.add({ type = "sprite-button", style = "frame_action_button", sprite = "utility/close", tags = { aic = "close" } })
  frame.style.width = 640
  frame.style.height = 470
  if ui(player).loc then frame.location = ui(player).loc else frame.force_auto_center() end
  local content = frame.add({ type = "frame", style = "inside_shallow_frame_with_padding", direction = "vertical" })
  content.style.horizontally_stretchable = true
  content.style.vertically_stretchable = true
  return frame, content
end

local function row(parent)
  local r = parent.add({ type = "flow", direction = "horizontal" })
  r.style.vertical_align = "center"
  r.style.horizontal_spacing = 6
  return r
end

local function note(parent, text, name)
  local l = parent.add({ type = "label", caption = text, name = name })
  l.style.single_line = false
  l.style.horizontally_stretchable = true
  return l
end

local function build_panel(player)
  local frame, c = new_window(player)
  local st = ui(player)
  local members = members_of(player.index)
  if #members > 0 then -- the chat box, always in sight
    local r = row(c)
    r.style.bottom_margin = 6
    local chat = r.add({ type = "textfield", name = "aic_chat",
      tooltip = "Talk to the crew (to whoever the Orders tab picks). Plain orders run as is; the rest goes to the AI. Enter sends." })
    chat.style.horizontally_stretchable = true
    chat.style.maximal_width = 1000
    btn(r, "Send", "send", nil, "Enter also sends", 60)
  end
  local tabs = c.add({ type = "tabbed-pane", name = "aic_tabs" })
  tabs.style.horizontally_stretchable = true
  tabs.style.vertically_stretchable = true
  local function tab(caption)
    local t = tabs.add({ type = "tab", caption = caption })
    local scroll = tabs.add({ type = "scroll-pane", horizontal_scroll_policy = "never", vertical_scroll_policy = "auto" })
    scroll.style.vertically_stretchable = true
    scroll.style.horizontally_stretchable = true
    tabs.add_tab(t, scroll)
    local body = scroll.add({ type = "flow", direction = "vertical" })
    body.style.vertical_spacing = 8
    body.style.horizontally_stretchable = true
    return body
  end

  -- Crew
  local crew_tab = tab("Crew")
  note(crew_tab, ai_short(player), "aic_ai_short")
  local t = crew_tab.add({ type = "table", name = "aic_crew", column_count = 7 })
  t.style.vertical_align = "center"
  t.style.horizontal_spacing = 6
  for _, m in pairs(members) do
    local col = m.color
    local n = t.add({ type = "label", caption = string.format("[font=default-bold][color=%g,%g,%g]%s[/color][/font]", col[1], col[2], col[3], m.name) })
    n.style.width = 56
    local l = t.add({ type = "label", name = "aic_status_" .. m.name, caption = status_text(m) })
    l.style.width = 190
    t.add({ type = "checkbox", caption = "Fight", state = m.defend ~= false, tags = { aic = "defend", who = m.name },
      tooltip = "Arms itself (best armor and gun from your stock, or makes them), shoots enemies in range, falls back to you when hurt" })
    t.add({ type = "checkbox", caption = "Auto", state = m.auto ~= false, tags = { aic = "auto", who = m.name },
      tooltip = "Clears deconstruction marks and builds ghosts near you on its own, making what's missing" })
    if m.follow then btn(t, "Stay", "stay", m.name, "Hold position", 64) else btn(t, "Follow", "follow", m.name, "Follow you", 64) end
    btn(t, "Stop", "stop", m.name, "Drop all its jobs", 56)
    btn(t, "Fire", "fire", m.name, "Dismiss (it hands over what it carries)", 52)
  end
  if #members == 0 then note(crew_tab, "No crew yet. Hire someone: they spawn next to you.") end
  local r = row(crew_tab)
  btn(r, "Hire", "hire", nil, "Up to " .. MAX_CREW, 64).enabled = #members < MAX_CREW
  r.add({ type = "textfield", name = "aic_name", tooltip = "Name (optional)" }).style.width = 120
  if #members > 0 then
    crew_tab.add({ type = "line" })
    r = row(crew_tab)
    r.add({ type = "label", caption = "Everyone:" })
    btn(r, "Build", "build", nil, "Place the ghosts near you now (making what's missing)", 64)
    btn(r, "Clear", "deconstruct", nil, "Remove what's marked for deconstruction near you", 64)
    btn(r, "Deliver", "deliver", nil, "Bring you everything they carry", 72)
    btn(r, "Come", "follow", nil, "Follow you", 64)
    btn(r, "Stop", "stop", nil, "Drop all jobs", 56)
    btn(r, "Clear nests", "attack", nil, "Destroy the enemy spawners and worms within 96 tiles of you", 100)
  end

  -- Orders
  local orders = tab("Orders")
  local names = { "Anyone" }
  for _, m in pairs(members) do names[#names + 1] = m.name end
  st.who = math.min(st.who or 1, #names)
  r = row(orders)
  r.add({ type = "drop-down", name = "aic_who", items = names, selected_index = st.who, tooltip = "Who gets the order or the message" })
  r.add({ type = "choose-elem-button", name = "aic_item", elem_type = "item", item = st.item, tooltip = "Item" })
  r.add({ type = "textfield", name = "aic_count", text = st.count, numeric = true, allow_decimal = false,
    allow_negative = false, tooltip = "How many" }).style.width = 60
  btn(r, "Get", "get", nil, "From chests or the network if there; else mined, crafted or made in a machine; brought to you", 56)
  btn(r, "Mine", "mine", nil, "Mine it by hand (ore, stone, coal, wood...)", 56)
  btn(r, "Craft", "craft", nil, "Hand-craft it", 60)
  note(orders, "Get works for anything: what isn't around they mine, craft or make in a machine (building the machine and its power if need be). Or type it in the box above: \"get 50 iron plate\", \"craft 10 gears\", \"attack\".")

  -- Goal
  local goal = tab("Goal")
  r = row(goal)
  r.add({ type = "choose-elem-button", name = "aic_goal_item", elem_type = "item", item = st.goal_item,
    tooltip = "What to have: the crew work towards it whenever there's nothing to build or clear" })
  r.add({ type = "textfield", name = "aic_goal_count", text = st.goal_count or "100", numeric = true,
    allow_decimal = false, allow_negative = false, tooltip = "How many to have (your pockets, chests near you, the network, the crew)" }).style.width = 60
  local bp = remote.interfaces["bpgen"] and remote.interfaces["bpgen"].plan_line
  r.add({ type = "checkbox", name = "aic_goal_line", caption = "Production line", state = bp and st.goal_line ~= false or false,
    enabled = bp ~= nil, tooltip = bp and "bpgen plans a line next to your base for it; the crew build, power, feed and empty it"
      or "Needs bpgen (zzz-bpgen) and the fnative loader" })
  r.add({ type = "textfield", name = "aic_goal_rate", text = st.goal_rate or "30", numeric = true,
    allow_decimal = false, allow_negative = false, tooltip = "The line's rate, per minute" }).style.width = 45
  r.add({ type = "label", caption = "/min" })
  btn(r, "Set", "goal_set", nil, "Start on it", 56)
  btn(r, "Clear", "goal_clear", nil, "Drop the goal and what they're working for", 60)
  note(goal, goal_text(player.index), "aic_goal_status")

  -- Settings (the mod's per-player settings, written here)
  local ai = tab("Settings")
  local set = ai.add({ type = "table", column_count = 2 })
  set.style.vertical_align = "center"
  set.style.horizontal_spacing = 12
  set.style.vertical_spacing = 6
  set.add({ type = "label", caption = "AI provider" })
  local cur = player_setting(player, "ai-crew-provider") or "auto"
  local sel = 1
  for i, v in ipairs(PROVIDER_CHOICES) do if v == cur then sel = i end end
  set.add({ type = "drop-down", name = "aic_set_provider", items = PROVIDER_CHOICES, selected_index = sel,
    tooltip = "auto: picked from the key (sk-or- OpenRouter, gsk_ Groq, AIza Gemini, csk- Cerebras, sk_ Pollinations). off: plain orders only." })
  set.add({ type = "label", caption = "API key" })
  local key = set.add({ type = "textfield", name = "aic_set_key", text = player_setting(player, "ai-crew-api-key") or "",
    tooltip = "Free keys: openrouter.ai/keys, console.groq.com/keys, aistudio.google.com/apikey, cloud.cerebras.ai. Saved in your mod settings." })
  key.style.width = 360
  key.is_password = true
  set.add({ type = "label", caption = "Model" })
  local model = set.add({ type = "textfield", name = "aic_set_model", text = player_setting(player, "ai-crew-model") or "",
    tooltip = "Blank: picked for you (on OpenRouter, a current free model)" })
  model.style.width = 360
  r = row(ai)
  btn(r, "Save & test", "set_save", nil, "Save the provider, key and model, then ask the AI one short question", 110).enabled = py()
  btn(r, "Test", "ai_test", nil, "Ask the AI one short question now", 64).enabled = py()
  for i, line in ipairs(ai_lines(player)) do note(ai, line, "aic_ai_" .. i) end
  ai.add({ type = "line" })
  r = row(ai)
  r.add({ type = "label", caption = "ADA voice" })
  local cur_v = player_setting(player, "ai-crew-ada-voice") or "ava"
  local vi = 1
  for i, v in ipairs(ADA_VOICES) do if v == cur_v then vi = i end end
  r.add({ type = "drop-down", name = "aic_set_ada_voice", items = ADA_VOICES, selected_index = vi,
    tooltip = "A neural voice under ADA's effects (chorus and a detuned echo). Needs edge-tts; the effects need ffmpeg." })
  btn(r, "Hear", "ada_hear", nil, "ADA says a line in this voice", 60).enabled = py()
  for _, c in ipairs(TOGGLES) do
    ai.add({ type = "checkbox", name = "aic_set_" .. c[1], caption = c[2], state = player_setting(player, "ai-crew-" .. c[1]) and true or false,
      tooltip = c[3] })
  end
  tabs.selected_tab_index = math.min(st.tab or 1, 4)

  if py() and not (storage.ai and storage.ai[player.index]) then check_ai(player) end
end

local function open_frame(player) return player.gui.screen[WIN] end

local function refresh(player)
  local f = open_frame(player)
  if not f then return end
  local members = members_of(player.index)
  local t = find_el(f, "aic_crew")
  if not t or #t.children ~= #members * 7 then return build_panel(player) end
  for _, m in pairs(members) do
    local l = find_el(t, "aic_status_" .. m.name)
    if not l then return build_panel(player) end
    l.caption = status_text(m)
  end
  local g = find_el(f, "aic_goal_status")
  if g then g.caption = goal_text(player.index) end
  local s = find_el(f, "aic_ai_short")
  if s then s.caption = ai_short(player) end
  local lines = ai_lines(player)
  for i = 1, 6 do
    local l = find_el(f, "aic_ai_" .. i)
    if l then l.caption = lines[i] or "" end
  end
  if #lines > 0 and not find_el(f, "aic_ai_" .. #lines) then return build_panel(player) end
end

-- the drop-down's pick: a member's name, or "crew" for anyone
local function who_of(f)
  local dd = f and find_el(f, "aic_who")
  local i = dd and dd.selected_index or 1
  return i > 1 and dd.items[i] or "crew"
end

local function act(player, action, who)
  local f = open_frame(player)
  local st = ui(player)
  if action == "close" then
    if f then f.destroy() end
    return
  elseif action == "set_save" then
    local function val(name) local e = f and find_el(f, name) return e and e.text end
    local dd = f and find_el(f, "aic_set_provider")
    if dd then player.mod_settings["ai-crew-provider"] = { value = PROVIDER_CHOICES[dd.selected_index] or "auto" } end
    if val("aic_set_key") then player.mod_settings["ai-crew-api-key"] = { value = val("aic_set_key"):gsub("%s", "") } end
    if val("aic_set_model") then player.mod_settings["ai-crew-model"] = { value = val("aic_set_model"):gsub("%s", "") } end
    check_ai(player)
    local l = f and find_el(f, "aic_ai_1")
    if l then l.caption = "Saved. Testing..." end
    return
  elseif action == "ada_hear" then
    return speak("Research complete. Please return to the HUB to select your next milestone, pioneer.", "ada", player)
  elseif action == "ai_test" then
    check_ai(player)
    local l = f and find_el(f, "aic_ai_1")
    if l then l.caption = "Testing..." end
    return
  elseif action == "hire" then
    local name = f and find_el(f, "aic_name")
    order(player.index, "crew hire " .. (name and name.text:match("^%s*(%S+)") or ""))
  elseif action == "fire" then
    order(player.index, "crew fire " .. who)
  elseif action == "get" or action == "mine" or action == "craft" then
    if not st.item then return player.print("Pick an item first.") end
    order(player.index, who_of(f) .. " " .. action .. " " .. (tonumber(st.count) or 50) .. " " .. st.item)
  elseif action == "goal_set" then
    if not st.goal_item then return player.print("Pick the goal's item first.") end
    order(player.index, "crew goal " .. (tonumber(st.goal_count) or 100) .. " " .. st.goal_item)
    local g = storage.goals and storage.goals[player.index]
    local bp = remote.interfaces["bpgen"]
    if g and bp and bp.plan_line and st.goal_line ~= false then g.use_line, g.rate = true, tonumber(st.goal_rate) or 30 end
  elseif action == "goal_clear" then
    if storage.goals then storage.goals[player.index] = nil end
    if storage.needs then storage.needs[player.index] = nil end
  elseif action == "send" then
    local box = f and find_el(f, "aic_chat")
    local text = box and box.text:gsub("^%s+", ""):gsub("%s+$", "")
    if not text or text == "" then return end
    box.text = ""
    order(player.index, who_of(f) .. " " .. text)
    return
  else
    order(player.index, (who or "crew") .. " " .. action)
  end
  if open_frame(player) then build_panel(player) end
end

script.on_event(defines.events.on_gui_click, function(ev)
  local el, player = ev.element, game.get_player(ev.player_index)
  if not (el.valid and player) then return end
  if el.name == "aic_toggle" then
    if open_frame(player) then open_frame(player).destroy() else build_panel(player) end
  elseif el.tags and el.tags.aic and (el.type == "button" or el.type == "sprite-button") then
    act(player, el.tags.aic, el.tags.who)
  end
end)

script.on_event(defines.events.on_gui_checked_state_changed, function(ev)
  local el = ev.element
  if el.name == "aic_goal_line" then ui(game.get_player(ev.player_index)).goal_line = el.state return end
  local setting = el.name:match("^aic_set_(.+)$")
  if setting then
    game.get_player(ev.player_index).mod_settings["ai-crew-" .. setting] = { value = el.state }
    return
  end
  local m = el.tags and find_member(el.tags.who, ev.player_index)
  if not m then return end
  if el.tags.aic == "auto" then m.auto = el.state end
  if el.tags.aic == "defend" then m.defend = el.state end
end)

script.on_event(defines.events.on_gui_confirmed, function(ev)
  local player = game.get_player(ev.player_index)
  if ev.element.name == "aic_chat" then act(player, "send")
  elseif ev.element.name == "aic_set_key" or ev.element.name == "aic_set_model" then act(player, "set_save")
  elseif ev.element.name == "aic_name" then act(player, "hire") end
end)

script.on_event(defines.events.on_gui_elem_changed, function(ev)
  if ev.element.name == "aic_item" then ui(game.get_player(ev.player_index)).item = ev.element.elem_value end
  if ev.element.name == "aic_goal_item" then ui(game.get_player(ev.player_index)).goal_item = ev.element.elem_value end
end)

script.on_event(defines.events.on_gui_text_changed, function(ev)
  if ev.element.name == "aic_count" then ui(game.get_player(ev.player_index)).count = ev.element.text end
  if ev.element.name == "aic_goal_count" then ui(game.get_player(ev.player_index)).goal_count = ev.element.text end
  if ev.element.name == "aic_goal_rate" then ui(game.get_player(ev.player_index)).goal_rate = ev.element.text end
end)

script.on_event(defines.events.on_gui_selection_state_changed, function(ev)
  if ev.element.name == "aic_set_ada_voice" then
    game.get_player(ev.player_index).mod_settings["ai-crew-ada-voice"] = { value = ADA_VOICES[ev.element.selected_index] or "ava" }
  end
  if ev.element.name == "aic_who" then ui(game.get_player(ev.player_index)).who = ev.element.selected_index end
end)

script.on_event(defines.events.on_gui_selected_tab_changed, function(ev)
  if ev.element.name == "aic_tabs" then ui(game.get_player(ev.player_index)).tab = ev.element.selected_tab_index end
end)

script.on_event(defines.events.on_gui_location_changed, function(ev)
  if ev.element.name == WIN then ui(game.get_player(ev.player_index)).loc = ev.element.location end
end)

script.on_event(defines.events.on_player_created, function(ev) add_button(game.get_player(ev.player_index)) end)

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
        if not silent then ada("Production milestone: first " .. pretty(name) .. " produced. Well done, pioneer.") end
      end
    end
  end
end

-- ----------------------------------------------------------------------------------------------------------- events

local function init()
  crew()
  storage.paths, storage.claims = storage.paths or {}, storage.claims or {}
  if not storage.seen then science_check(true) end
  for _, p in pairs(game.players) do
    add_button(p)
    local old = mod_gui.get_frame_flow(p).aic_panel -- (0.1's panel)
    if old then old.destroy() end
  end
end
script.on_init(init)
script.on_configuration_changed(function() source_names, machine_cache = {}, {} init() end)

script.on_event(defines.events.on_tick, function(ev)
  local t = ev.tick
  for name, m in pairs(crew()) do
    local e = m.entity
    if not (e and e.valid) then
      crew()[name] = nil
    else
      if m.move then walk(m) end
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
      if (t + m.phase) % (m.jobs[1] and m.jobs[1].kind == "attack" and 15 or 30) == 0 then fight(m) end
      if (t + m.phase) % 10 == 0 and (not m.move or (m.jobs[1] and m.jobs[1].kind == "attack" and (t + m.phase) % 60 == 0)) and not m.retreat then think(m) end
      if m.retreat and not m.move and (t + m.phase) % 60 == 0 then go(m, anchor(m), 4) end
    end
  end
  if t % 5 == 0 and next(pending) then
    for id, p in pairs(pending) do
      local st, out = native.poll(id)
      if st ~= "pending" then
        pending[id] = nil
        if st == "done" then on_answer(p, out)
        elseif p.kind ~= "ask" then on_answer(p, "{}")
        else tell(p.owner and game.get_player(p.owner), "[ai-crew] AI error: " .. tostring(out):sub(1, 300)) end
      end
    end
  end
  if t % 30 == 0 then
    for _, p in pairs(game.connected_players) do refresh(p) end
    for i = #lines, 1, -1 do
      local l = lines[i]
      if t >= l.at then
        table.remove(lines, i)
        local m = find_member(l.who, l.owner)
        if m then say(m, l.text) end
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
  if t % 300 == 0 and storage.fallen then
    for name, f in pairs(storage.fallen) do
      if t >= f.at and game.get_surface(f.surface) then
        storage.fallen[name] = nil
        local m = hire(name, game.get_surface(f.surface), f.home, f.force, f.owner)
        if m then
          m.auto, m.defend, m.follow = f.auto, f.defend, f.follow
          say(m, pick({ "I'm back. What did I miss?", "Reconstructed and ready.", "Round two." }))
        end
      end
    end
  end
  if storage.queue_check and t >= storage.queue_check then
    storage.queue_check = nil
    local f = game.forces.player
    if f and not f.current_research and #f.research_queue == 0 then ada("Research queue empty. Awaiting your input, pioneer.") end
  end
end)

script.on_event(defines.events.on_script_path_request_finished, function(ev)
  local name = storage.paths and storage.paths[ev.id]
  if not name then return end
  storage.paths[ev.id] = nil
  local m = crew()[name]
  if not (m and m.move) then return end
  if ev.path then
    m.move.path, m.move.i = ev.path, 1
  elseif ev.try_again_later then
    m.move.retry = ev.tick + 30
  else
    m.move.path, m.move.i = { { position = m.move.goal } }, 1 -- no path: straight at it, the stuck check hops it
  end
end)

script.on_event(defines.events.on_research_finished, function(ev)
  if ev.by_script then return end
  ada("Research complete: " .. pretty(ev.research.name) .. ".")
  storage.queue_check = ev.tick + 60
end)

script.on_event(defines.events.on_rocket_launched, function()
  ada("Rocket launch confirmed. Excellent work, pioneer.")
end)

script.on_event(defines.events.on_player_died, function()
  ada("Pioneer vital signs lost. Initiating respawn protocol.")
end)

script.on_event(defines.events.on_entity_died, function(ev)
  for name, m in pairs(crew()) do
    if m.entity == ev.entity then
      crew()[name] = nil
      storage.fallen = storage.fallen or {}
      storage.fallen[name] = { at = ev.tick + 3600, owner = m.owner, home = m.home, surface = m.entity.surface.name,
        force = m.entity.force.name, auto = m.auto, defend = m.defend, follow = m.follow }
      ada("Crew member " .. name .. " is down. Reconstruction in sixty seconds.")
    end
  end
end, { { filter = "type", type = "character" } })

remote.add_interface("ai-crew", {
  hire = function(name, surface, position, force, owner)
    local m, err = hire(name, game.get_surface(surface) or surface, position, force or "player", owner)
    if not m then error(err) end
    return m.name
  end,
  order = function(owner, text) order(owner, text) end,
  -- (tests) a button of the window pressed
  press = function(player_index, action) act(game.get_player(player_index), action) end,
  ai_status = function(player_index) return storage.ai and storage.ai[player_index] end,
  -- (tests) the window opened on a tab
  panel = function(player_index, tab)
    local player = game.get_player(player_index)
    ui(player).tab = tab or 1
    build_panel(player)
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
    return { position = m.entity.position, jobs = #m.jobs, health = m.entity.health, retreat = m.retreat, armed = gun_range(m) > 0,
      fighting = m.target and m.target.valid and m.target.name or nil, unit = m.entity.unit_number, doing = j and (j.kind .. ((j.item or j.recipe) and (" " .. (j.item or j.recipe) .. " " .. (j.n or 0) .. "/" .. (j.count or "")) or "")),
      inventory = inv, fed = m.fed, collected = m.collected, need = storage.needs and storage.needs[m.owner or 0] and storage.needs[m.owner or 0][1] and storage.needs[m.owner or 0][1].item }
  end,
})

-- the fnative-std window's own handlers (title bar close, remembered place, resize grip), after ours
if fstd then
  require("__fnative-std__/safe").chain("ai-crew", { require("__fnative-std__/input").handlers, fstd.handlers })
end
