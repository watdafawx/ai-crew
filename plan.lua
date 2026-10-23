-- AI Crew: items and where to get them (pockets, chests, belts, the network), machines, fuel and power, and the
-- plans: what it takes to make an item, bpgen lines, the next step towards a goal. One of control.lua's files.

-- (the other files' that this one uses: set by link, at the end)
local ada, ALIASES, any_player, base_chunks, CREW, crew, crew_built, dist2, DOING_WORD, gather, go, kept_out, low_burners,
  nearest_source, needs, player_setting, pretty, product_amount, RADIUS, react, say

local JOBS = {} -- (this file's jobs: feed, collect; control.lua's JOBS gets them)
local source_names = {} -- item -> names of resources/trees/rocks that yield it

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
  HAND = HAND or (prototypes.entity[CREW] and prototypes.entity[CREW].crafting_categories) or { crafting = true }
  return HAND
end

-- 2.1: a recipe has several categories; the first of them `set` (a machine's crafting_categories) has, or nil
local function cat_in(r, set)
  for _, c in pairs(r.categories) do if set[c] then return c end end
end

local function handcraft_recipe(force, item)
  local HAND = hand_categories()
  local r = force.recipes[item]
  if r and r.enabled and not r.hidden and cat_in(r, HAND) then return r end
end

local function owner_char(m)
  local p = m.owner and game.get_player(m.owner)
  local c = p and p.valid and p.character or not m.owner and storage.test_owner -- (tests: a stand-in for yours)
  if c and c.valid and c.surface == m.entity.surface then return c end
end

local function anchor(m)
  local c = owner_char(m)
  return c and c.position or m.home
end

-- chests near the owner (or home); logistic chests only when they're in no network (the network counts those).
-- One search per member a tick (available() runs dozens of times a tick when arming): a copy of the list each call
local chests
do local chest_cache = {} function chests(m)
  local c = chest_cache[m.name]
  if not (c and c.tick == game.tick) then
    c = { tick = game.tick, invs = {} }
    for _, ch in pairs(m.entity.surface.find_entities_filtered({ type = { "container", "logistic-container" },
      force = m.entity.force, position = anchor(m), radius = RADIUS })) do
      local inv = ch.get_inventory(defines.inventory.chest)
      if inv and not (ch.type == "logistic-container" and ch.logistic_network)
        and not kept_out(ch.surface, ch.position) then
        c.invs[#c.invs + 1] = inv
      end
    end
    chest_cache[m.name] = c
  end
  local out = {}
  for _, inv in ipairs(c.invs) do if inv.valid then out[#out + 1] = inv end end
  return out
end end

-- the logistic network where the owner (or home) is: its storage and provider chests, wherever they are
local function network(m)
  return m.entity.surface.find_logistic_network_by_position(anchor(m), m.entity.force)
end

local function in_box(box, pos, pad)
  pad = pad or 0
  return pos.x >= box[1] - pad and pos.y >= box[2] - pad and pos.x <= box[1] + box[3] + pad and pos.y <= box[2] + box[4] + pad
end

-- belt lanes near the owner (or home): items going by are fair game before hand-crafting them, as a player grabs
-- plates off the bus. Not a bpgen line's belts (the crew feed and empty those) or a keep-out zone.
-- chisle: one search per member a tick, the lanes kept in a plain local (rebuilt each tick, never saved). m.belts_at:
-- round there instead (a roamer's own batch, crafted from what goes by where it stands)
local belt_lanes
do local belt_cache = {} function belt_lanes(m)
  local c = belt_cache[m.name]
  local at = m.belts_at
  if c and c.tick == game.tick and c.at == at then return c.lanes end
  local lanes, boxes = {}, {}
  for _, g in pairs(storage.goals or {}) do
    if g.line and g.line.box then boxes[#boxes + 1] = g.line.box end
  end
  for _, b in pairs(m.entity.surface.find_entities_filtered({ type = { "transport-belt", "underground-belt", "splitter" },
    force = m.entity.force, position = at or anchor(m), radius = 24 })) do
    local mine = not kept_out(b.surface, b.position)
    for _, box in ipairs(boxes) do if mine and in_box(box, b.position, 1) then mine = false end end
    if mine then
      for i = 1, b.get_max_transport_line_index() do lanes[#lanes + 1] = b.get_transport_line(i) end
    end
  end
  belt_cache[m.name] = { tick = game.tick, lanes = lanes, at = at }
  return lanes
end end

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
  for _, l in pairs(belt_lanes(m)) do n = n + l.get_item_count(id) end
  local net = network(m)
  return net and n + net.get_item_count(id) or n
end

-- what it took from out of reach (a chest, your pockets) it walks over to, as a player would:
-- the items move at once and the walk comes before its next step (think). Once a minute a place and item: the
-- next few of the same it took along on the first trip.
-- chisle: the logistic network still hands items over directly, as if bots brought them
local function note_visit(m, ent, item)
  if not (ent and ent.valid) or ent == m.entity then return end
  local e = m.entity
  if dist2(ent.position, e.position) <= e.reach_distance * e.reach_distance then return end
  for _, v in ipairs(m.visits or {}) do if v == ent then return end end -- (going there already: one trip)
  if not m.visited or table_size(m.visited) > 200 then m.visited = {} end
  local k = (ent.unit_number or 0) .. item
  if game.tick - (m.visited[k] or -3600) < 3600 then return end
  m.visited[k] = game.tick
  m.visits = m.visits or {}
  m.visits[#m.visits + 1] = ent
end

local function take(m, item, count, quality, chests_only)
  local inv = m.entity.get_main_inventory()
  local id = { name = item, quality = quality or "normal" }
  local got = 0
  for _, src in pairs(sources(m, chests_only)) do
    if got >= count then break end
    local n = math.min(count - got, src.get_item_count(id))
    if n > 0 then
      local ins = inv.insert({ name = item, count = n, quality = id.quality })
      if ins > 0 then
        src.remove({ name = item, count = ins, quality = id.quality })
        note_visit(m, src.entity_owner, item)
      end
      got = got + ins
    end
  end
  for _, l in pairs(got < count and belt_lanes(m) or {}) do
    if got >= count then break end
    if l.valid then
      local n = math.min(count - got, l.get_item_count(id))
      local ins = n > 0 and inv.insert({ name = item, count = n, quality = id.quality }) or 0
      if ins > 0 then
        local out = l.remove_item({ name = item, count = ins, quality = id.quality })
        if out < ins then inv.remove({ name = item, count = ins - out, quality = id.quality }) end
        if out > 0 then note_visit(m, l.owner, item) end
        got = got + out
      end
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

-- ---------------------------------------------------------------------------------------------- smelting and goals

local FUELS = { "coal", "solid-fuel", "wood" }
local machine_cache = {} -- item -> names of recipes (item ingredients only) that make it in a machine
-- (the mods changed: so may the recipes and what yields what)
local function forget_caches() source_names, machine_cache = {}, {} end

-- the recipe to make item in a machine (one hand-crafting can't do), preferring the one named after it
local function machine_recipe(force, item)
  if not machine_cache[item] then
    local list = {}
    local hand = hand_categories()
    for name, r in pairs(prototypes.recipe) do
      local ok = not r.hidden and not cat_in(r, hand) and #r.ingredients > 0
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

local IN = { furnace = defines.inventory.crafter_input, ["assembling-machine"] = defines.inventory.crafter_input }
local OUT = { furnace = defines.inventory.crafter_output, ["assembling-machine"] = defines.inventory.crafter_output }

-- machines near the owner free for this recipe, up to 4: a furnace that's empty or on the same input; an
-- assembler-type machine (overhaul mods' furnaces too) already on this recipe, or standing idle with nothing in it (no
-- recipe, or another one: switched for the job and back after, see JOBS.smelt). Yours first (those on this recipe
-- before idle ones), then the crew's own, nearest first: what's there is used before anything is built (need_machine)
local function machines_for(m, r, item)
  local e = m.entity
  local out, rank = {}, {}
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
    if not in_line and not crew_built(f) then -- (a machine of yours that inserters or loaders feed or empty, or with
      local b = f.bounding_box                 -- pipes on it, is part of a line: not theirs, its recipe never switched)
      for _, i in pairs(e.surface.find_entities_filtered({ type = { "inserter", "loader", "loader-1x1" }, force = e.force,
        area = { { b.left_top.x - 3, b.left_top.y - 3 }, { b.right_bottom.x + 3, b.right_bottom.y + 3 } } })) do
        if i.type == "inserter" and (i.drop_target == f or i.pickup_target == f)
          or i.type ~= "inserter" and i.loader_container == f then in_line = true break end
      end
      for _, list in pairs(in_line and {} or f.fluidbox_neighbours) do
        if #list > 0 then in_line = true break end
      end
    end
    if not in_line and cat_in(r, p.crafting_categories) and f.status ~= defines.entity_status.no_power
      and not kept_out(f.surface, f.position)
      and (not p.fixed_recipe or p.fixed_recipe.name == r.name) then
      local src, res = f.get_inventory(IN[f.type]), f.get_inventory(OUT[f.type])
      local free
      if f.type == "furnace" then
        free = src.is_empty() or src.get_item_count(r.ingredients[1].name) > 0
      else
        local cur = f.get_recipe()
        free = (cur and cur.name == r.name) or src.is_empty() and res.is_empty() and not f.is_crafting()
      end
      if free and (res.is_empty() or res.get_item_count(item) > 0) then
        local cur = f.type == "assembling-machine" and f.get_recipe()
        rank[f] = (crew_built(f) and 2 or 0) + ((f.type == "furnace" or cur and cur.name == r.name) and 0 or 1)
        out[#out + 1] = f
      end
    end
  end
  table.sort(out, function(a, b)
    if rank[a] ~= rank[b] then return rank[a] < rank[b] end
    return dist2(e.position, a.position) < dist2(e.position, b.position)
  end)
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


local function goals()
  storage.goals = storage.goals or {}
  return storage.goals
end

-- how many of item the owner has: pockets, chests near them, and what the crew carries. Counted at most every 2 s
-- (a big base's chests and belts add up); kept in storage (the same on every peer), forgotten for an owner whenever
-- one of its crew finishes a job (think), so a step just done is never counted stale
local function goal_have(owner, item)
  storage.have_cache = storage.have_cache or {}
  local k = owner or 0
  local c = storage.have_cache[k]
  if not c then c = {} storage.have_cache[k] = c end
  local hit = c[item]
  if hit and game.tick - hit.tick < 120 then return hit.n end
  local n, first = 0, nil
  for _, m in pairs(crew()) do
    if m.owner == owner and m.entity.valid then
      first = first or m
      n = n + m.entity.get_item_count(item) -- (all its inventories: a crafted gun goes straight to the gun slot)
    end
  end
  n = first and n + available(first, item) or n
  c[item] = { tick = game.tick, n = n }
  return n
end


-- --------------------------------------------------------------------------------------------- machines and power

local plan -- (below)
local GENERATORS = { "generator", "burner-generator", "solar-panel", "electric-energy-interface" }

local function have_count(m, item)
  return m.entity.get_main_inventory().get_item_count(item) + available(m, item)
end

-- is anything generating in this electric network (looked for within 200 tiles)
--- is the pole's network fed by a generator? Its statistics know any generator that has fed it, however far off (a
--- big base's power plant can be hundreds of tiles away); else (nothing drawing from it yet) a look round the pole.
--- `seen`: networks already known to be fed
local function net_has_power(pole, seen)
  local id = pole.electric_network_id
  if not id then return false end
  if seen[id] then return true end
  if next(pole.electric_network_statistics.output_counts) == nil then
    local found = false
    for _, g in pairs(pole.surface.find_entities_filtered({ type = GENERATORS, force = pole.force, position = pole.position, radius = 200 })) do
      if g.electric_network_id == id then found = true break end
    end
    if not found then return false end
  end
  seen[id] = true
  return true
end

-- where water meets land nearest the owner: an offshore pump, a boiler on its output and a steam engine on the boiler's
-- steam, found by trial-placing each piece and keeping it only when its fluidbox connects (modded pieces work too)
local function connects(ent, to)
  for _, list in pairs(ent.fluidbox_neighbours) do
    for _, n in pairs(list) do if n == to then return true end end
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
  local from, fd, seen = nil, nil, {}
  for _, p in pairs(s.find_entities_filtered({ type = "electric-pole", force = force, position = machine.position, radius = 150 })) do
    -- (not a building's own hidden pole, as Power Propagation adds: its wires reach 1 tile)
    if p.prototype.get_max_wire_distance(p.quality) >= 3 and net_has_power(p, seen) then
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
  local is_pole = from.type == "electric-pole"
  -- (a wire spans the shorter reach of its two poles: from a small pole, a medium one goes 7.5 out, not 9)
  local reach = math.min(pp.get_max_wire_distance(), is_pole and from.prototype.get_max_wire_distance(from.quality) or math.huge) - 0.5
  local supply = pp.get_supply_area_distance()
  local dx, dy = machine.position.x - from.position.x, machine.position.y - from.position.y
  local d = math.sqrt(dx * dx + dy * dy)
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
  local allowed = storage.test_machines -- (the player's "Crew build machines"; tests set it here)
  if allowed == nil then
    local pl = m.owner and game.get_player(m.owner) or any_player()
    allowed = not pl or player_setting(pl, "ai-crew-machines") ~= false
  end
  if not allowed then
    return nil, "I'd need a machine for " .. pretty(item) .. ", and building machines is off. Some in a chest or on a belt would do."
  end
  for _, f in pairs(e.surface.find_entities_filtered({ type = { "furnace", "assembling-machine" }, force = e.force,
    position = anchor(m), radius = RADIUS })) do
    if cat_in(r, f.prototype.crafting_categories) and f.status == defines.entity_status.no_power then
      return power_to(m, f, depth)
    end
  end
  -- (the base made some this last hour: it's fetched from belts, chests and machines (far_find), never a machine
  -- built for it here; only an item nothing has made yet gets one, as a new game's first plates)
  local made = e.force.get_item_production_statistics(e.surface).get_flow_count({ name = item, category = "input",
    precision_index = defines.flow_precision_index.one_hour, count = true })
  if made > 0 then
    return nil, "The base makes " .. pretty(item) .. ", but there's none on a belt, in a chest or a machine I can get to. I won't build another machine for it."
  end
  -- (never a row of them: three of the crew's own for this already and none usable means something else is wrong)
  local own = 0
  for _, b in pairs(storage.crew_built or {}) do
    if b.valid and b.prototype.crafting_categories and cat_in(r, b.prototype.crafting_categories)
      and dist2(b.position, anchor(m)) < RADIUS * RADIUS then own = own + 1 end
  end
  if own >= 3 then return nil, "I've set up " .. own .. " machines for " .. pretty(item) .. " and can't use them; something's in the way." end
  local options = {}
  local cat_filters = {}
  for _, c in pairs(r.categories) do cat_filters[#cat_filters + 1] = { filter = "crafting-category", crafting_category = c } end
  for name, p in pairs(prototypes.get_entity_filtered(cat_filters)) do
    local it = (p.type == "furnace" or p.type == "assembling-machine") and p.items_to_place_this and p.items_to_place_this[1]
    if it and (not p.fixed_recipe or p.fixed_recipe.name == r.name) then
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

-- what's made beyond reach for plan(): chests within 160 tiles, else belts within 120 (not those near you or home:
-- those count as had), else machines' outputs within 160 (furnaces, assemblers: near ones too); never in a keep-out
-- zone or a bpgen line; the nearest, from where the search began. With your base marked (base.lua): the same three, in
-- all of the base and nowhere else, its chunks nearest first (done once no chunk left can hold a nearer one). A big base
-- has thousands of each: searched in bands 8 tiles high (or a chunk at a time), ~300 entities a call, kept in storage
-- between calls (the answer picks the job: the same on every peer, and a load mid-search goes on). "scan" till done,
-- then where or nil
local FAR = { { types = { "container", "logistic-container" }, r = 160 },
  { types = { "transport-belt", "underground-belt", "splitter" }, r = 120, near = 25 },
  { types = { "furnace", "assembling-machine" }, r = 160, near = 0 } }

-- one entity found, nearer than the best yet (at p, d away) and not near home: does it hold some of item?
local function far_seen(sc, ent, p, d, item, s)
  local n -- (counted only when it'd be the nearest yet)
  if sc.phase ~= 2 then
    local inv = ent.get_inventory(sc.phase == 1 and defines.inventory.chest or OUT[ent.type])
    n = inv and inv.get_item_count(item) or 0
  else
    n = ent.get_item_count(item)
  end
  if n > 0 and not kept_out(s, p) then
    for _, g in pairs(storage.goals or {}) do
      if g.line and g.line.box and in_box(g.line.box, p, 1) then return end
    end
    sc.best, sc.bd = { x = p.x, y = p.y }, d
  end
end

local function far_find(m, item)
  local e = m.entity
  m.far_scan = m.far_scan or {}
  local sc = m.far_scan[item]
  if not sc or game.tick - sc.tick > 300 or sc.surface ~= e.surface.index then -- (new, or left off a while: afresh)
    local h, p = anchor(m), e.position
    sc = { surface = e.surface.index, at = { x = p.x, y = p.y }, home = { x = h.x, y = h.y }, phase = 1 }
    local chunks = base_chunks(m)
    if chunks then -- (each chunk with how near its nearest corner or edge is)
      sc.list, sc.i = {}, 1
      for _, c in ipairs(chunks) do
        local x0, y0 = c[1] * 32, c[2] * 32
        local dx = math.max(x0 - p.x, 0, p.x - x0 - 32)
        local dy = math.max(y0 - p.y, 0, p.y - y0 - 32)
        sc.list[#sc.list + 1] = { x0, y0, dx * dx + dy * dy }
      end
      table.sort(sc.list, function(a, b) return a[3] < b[3] end)
    end
    m.far_scan[item] = sc
  end
  sc.tick = game.tick
  local s, seen = e.surface, 0
  while seen < 300 do
    local ph = FAR[sc.phase]
    local r, near = ph.r, ph.near or RADIUS
    local c = sc.list and sc.list[sc.i]
    local done
    if sc.list then
      done = not c or (sc.bd and c[3] >= sc.bd)
    else
      sc.y = sc.y or math.floor(sc.at.y - r)
      done = sc.y > sc.at.y + r
    end
    if done then -- (this kind all looked at: the next kind only when none of this one has any)
      if sc.best or sc.phase == #FAR then
        m.far_scan[item] = nil
        return sc.best
      end
      sc.phase, sc.y, sc.i = sc.phase + 1, nil, sc.list and 1
    elseif sc.list then
      sc.i = sc.i + 1
      local list = s.find_entities_filtered({ type = ph.types, force = e.force,
        area = { { c[1], c[2] }, { c[1] + 32, c[2] + 32 } } })
      seen = seen + #list + 1
      local at, home, bd, n2 = sc.at, sc.home, sc.bd, near * near
      for _, ent in pairs(list) do
        local p = ent.position
        local dx, dy = p.x - at.x, p.y - at.y
        local d = dx * dx + dy * dy
        if not (bd and d >= bd) and dist2(p, home) > n2 then far_seen(sc, ent, p, d, item, s) bd = sc.bd end
      end
    else
      local y0, y1, x = sc.y, sc.y + 8, sc.at.x
      sc.y = y1
      local dy = (sc.at.y < y0 and y0 - sc.at.y) or (sc.at.y > y1 and sc.at.y - y1) or 0
      local w = math.sqrt(math.max(r * r - dy * dy, 0)) + 1 -- (the circle's width across the band)
      local list = s.find_entities_filtered({ type = ph.types, force = e.force,
        area = { { x - w, y0 }, { x + w, y1 } } })
      seen = seen + #list
      local at, home, bd, n2, r2 = sc.at, sc.home, sc.bd, near * near, r * r
      for _, ent in pairs(list) do
        local p = ent.position -- (each once: by its centre, in the band and the circle, as a radius search counts)
        local dx, dy = p.x - at.x, p.y - at.y
        local d = dx * dx + dy * dy
        if p.y >= y0 and p.y < y1 and d <= r2 and not (bd and d >= bd) and dist2(p, home) > n2 then
          far_seen(sc, ent, p, d, item, s)
          bd = sc.bd
        end
      end
    end
  end
  return "scan"
end

-- the next job towards having n more of item; nil and why when nothing gets there; "scan" while it's still looking
-- for what's made already (callers wait a moment and ask again; a "get" takes it as a need)
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
    -- made in a machine: first what's already made, in chests (160 tiles), else on belts (120), else in machines'
    -- outputs (160) beyond the usual reach
    -- (not in a keep-out zone or a bpgen line, nor at hand already: chests and belts near you or home count as had),
    -- fetched and brought home. None anywhere: not looked for again for 10 s; a place that gave nothing: a minute
    m.far_skip = m.far_skip or {}
    if game.tick >= (m.far_skip[item] or 0) then
      local best = far_find(m, item)
      if best == "scan" then return "scan" end
      if best then return { kind = "collect", item = item, at = best, count = math.min(n, 200), far = true } end
      for _, o in pairs(crew()) do -- (none for the crew close by either: they'd search the same chests and belts)
        local oe = o.entity
        if o.owner == m.owner and oe.valid and oe.surface == e.surface and dist2(oe.position, e.position) < 32 * 32 then
          o.far_skip = o.far_skip or {}
          o.far_skip[item] = game.tick + 600
        end
      end
    end
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
-- what's on the belts (and, fetching from further out, in the chests and machines' outputs) round job.at, up to
-- job.count when it has one
JOBS.collect = function(m, job)
  local e = m.entity
  if not go(m, job.at, math.max(e.reach_distance - 3, 2)) then return false end
  local inv = e.get_main_inventory()
  local function want() return job.count and job.count - job.n or math.huge end
  for _, b in pairs(e.surface.find_entities_filtered({ type = { "transport-belt", "underground-belt", "splitter" }, position = job.at, radius = 4 })) do
    for lane = 1, b.get_max_transport_line_index() do
      local tl = b.get_transport_line(lane)
      local n = math.min(tl.get_item_count(job.item), want())
      local got = n > 0 and inv.insert({ name = job.item, count = n }) or 0
      if got > 0 then
        local out = tl.remove_item({ name = job.item, count = got })
        if out < got then inv.remove({ name = job.item, count = got - out }) end
        job.n = job.n + out
      end
    end
  end
  for _, c in pairs(job.far and e.surface.find_entities_filtered({ type = { "container", "logistic-container", "furnace",
    "assembling-machine" }, force = e.force, position = job.at, radius = 2 }) or {}) do
    local src = c.get_inventory(OUT[c.type] or defines.inventory.chest)
    local n = src and math.min(src.get_item_count(job.item), want()) or 0
    local got = n > 0 and inv.insert({ name = job.item, count = n }) or 0
    if got > 0 then
      src.remove({ name = job.item, count = got })
      job.n = job.n + got
    end
  end
  m.collected = (m.collected or 0) + job.n
  if job.n > 0 then
    table.insert(m.jobs, 2, { kind = "deliver" })
    if job.far then say(m, "Got " .. job.n .. " " .. pretty(job.item) .. " from over there.", "quiet") end
  elseif job.far then
    m.far_skip = m.far_skip or {}
    m.far_skip[job.item] = game.tick + 3600
  end
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
  say(m, "Asking bpgen for a " .. pretty(g.item) .. " line.", "quiet")
end

-- with nothing else to do, one step towards what the crew needs, else the owner's goal
local function goal_step(m)
  if game.tick < (m.goal_wait or 0) then return end
  local key = m.owner or 0
  local list = needs(m.owner)
  local g, is_need = list[1], true
  if not g then g, is_need = goals()[key], false end
  if not g then return end
  if is_need and g.after and g.after.kind == "tend" and #low_burners(m, 1) == 0 then -- (the burners it was for are gone or fed)
    table.remove(list, 1)
    return
  end
  local have = goal_have(m.owner, g.item)
  g.count = g.count or (have + g.more)
  if have >= g.count then
    if not is_need then
      goals()[key] = nil
      ada("goal", { n = g.count, item = pretty(g.item) })
      react(m.owner, "goal", "goal reached: " .. g.count .. " " .. pretty(g.item), { item = pretty(g.item) })
      return
    end
    table.remove(list, 1)
    for _, o in pairs(crew()) do if o.owner == m.owner then o.auto_wait = nil end end -- the blueprint can go on
    say(m, "Got the " .. pretty(g.item) .. (g.reason and (" for " .. g.reason) or "") .. ".", "quiet")
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
      if lj == "scan" then m.next_scan = game.tick return end -- (still looking for what's made: on at the next think)
      if lj then
        g.why, g.step = nil, m.name .. ": " .. (DOING_WORD[lj.kind] or lj.kind) .. " " .. pretty(lj.item or lj.recipe or "") .. " (line)"
        lj.n, lj.skip, lj.goal = 0, {}, true
        m.jobs[#m.jobs + 1] = lj
        return true
      end
    end
  end
  local job, why = plan(m, g.item, g.count - have)
  if job == "scan" then m.next_scan = game.tick return end -- (idle looks for work every 2 s: this, at the next think)
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
  local what = job.item or job.recipe -- (tend has neither: it refuels the burners)
  g.step = m.name .. ": " .. (DOING_WORD[job.kind] or job.kind) .. (what and " " .. pretty(what) or "")
  job.n, job.skip, job.goal = 0, {}, true
  m.jobs[#m.jobs + 1] = job
  return true
end

-- ------------------------------------------------------------------------------------------------------------- shared
-- what the other files use of this one, and its link: control.lua calls it once all files are loaded
return {
  share = { anchor = anchor, available = available, belt_lanes = belt_lanes, forget_caches = forget_caches,
    fuel_available = fuel_available, goal_have = goal_have, goal_step = goal_step, goals = goals,
    handcraft_recipe = handcraft_recipe, IN = IN, in_box = in_box, machines_for = machines_for, needs_fuel = needs_fuel,
    network = network, OUT = OUT, owner_char = owner_char, plan = plan, power_to = power_to, refuel = refuel,
    resolve_item = resolve_item, sources = sources, sources_for = sources_for, take = take, unload = unload },
  link = function(A)
    ada, ALIASES, any_player, CREW, crew, crew_built = A.ada, A.ALIASES, A.any_player, A.CREW, A.crew, A.crew_built
    base_chunks = A.base_chunks
    dist2, DOING_WORD, gather, go, kept_out = A.dist2, A.DOING_WORD, A.gather, A.go, A.kept_out
    low_burners, nearest_source, needs, player_setting = A.low_burners, A.nearest_source, A.needs, A.player_setting
    pretty, product_amount, RADIUS, react, say = A.pretty, A.product_amount, A.RADIUS, A.react, A.say
  end,
  JOBS = JOBS,
}
