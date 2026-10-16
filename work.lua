-- AI Crew: the jobs (JOBS[kind](m, job): true when done): build, upgrade, clear, mine, craft, fetch, deliver, smelt,
-- place, tend. One of control.lua's files.

-- (the other files' that this one uses: set by link, at the end)
local anchor, available, crew, crew_built, dist2, fuel_available, go, handcraft_recipe, IN, kept_out, machines_for,
  goals, needs_fuel, OUT, pretty, RADIUS, refuel, remember, say, sources_for, spot, stop_mining, take, unload

-- ------------------------------------------------------------------------------------------------------------- jobs

local JOBS = {} -- (this file's jobs; control.lua's JOBS gets them, and plan.lua's and fight.lua's)
local low_burners -- (defined with the fuel helpers)
local DOING_WORD = { drive = "driving", defend = "defending the base", fish = "fishing", build = "building", deconstruct = "clearing", mine = "mining", craft = "crafting",
  fetch = "fetching", deliver = "delivering", smelt = "making", place = "placing", tend = "refuelling",
  feed = "feeding", back = "heading back", collect = "collecting", attack = "attacking nests", upgrade = "upgrading" }

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
-- the item an entity marked for upgrade needs: {name, count, quality}
local function upgrade_item(ent)
  local proto, q = ent.get_upgrade_target()
  local it = proto and proto.items_to_place_this and proto.items_to_place_this[1]
  if not it then return end
  return { name = it.name, count = it.count or 1, quality = q and q.name or "normal" }
end

-- the nearest of `targets` whose item (item_of) it has, can take, or can hand-craft; and {item, count, single} to
-- craft first. What none of them can get is noted in job.missing ("item/quality" -> {name, quality, n}: how many short)
local function next_target(m, job, targets, item_of)
  local e = m.entity
  local cache, craftable, demand, best, bd, best_k = {}, {}, {}, nil, nil, nil
  job.short, job.want = {}, {}
  local inv = e.get_main_inventory()
  for _, g in pairs(targets) do
    local key = key_of(g)
    local claim = claims()[key]
    if not job.skip[key] and (not claim or claim == m.name or not crew()[claim]) then
      local it = item_of(g)
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
        if cache[k] >= it.count then
          job.want[k] = { name = it.name, quality = it.quality, count = math.min(demand[k], cache[k]) }
        end
      end
    end
  end
  for k, it in pairs(job.short) do job.missing[k] = { name = it.name, quality = it.quality, n = demand[k] - cache[k] } end
  if not best then return end
  claims()[key_of(best)] = m.name
  local it = item_of(best)
  if cache[best_k] >= it.count then return best end
  return best, { item = it.name, count = math.min(demand[best_k] - cache[best_k], 50), single = it.count }
end

-- where a build, upgrade or clearing job works: round the owner (or home) as it starts, kept while it lasts. You
-- walking off don't drag the work along, nor them back and forth with it
local function job_area(m, job)
  if not job.at then
    local a = anchor(m)
    job.at = { x = a.x, y = a.y }
  end
  return job.at
end

-- a build's (or upgrade's) first pick: what its marks want that's to be had (your pockets, chests) taken in one go, a
-- share of it when more of the crew are round there (a stack at most): one trip over for it, not one per mark
local function stock(m, job)
  if job.stocked then return end
  job.stocked = true
  local e = m.entity
  local inv, share = e.get_main_inventory(), 0
  for _, o in pairs(crew()) do
    local oe = o.entity
    local near = oe.valid and oe.surface == e.surface and dist2(oe.position, job.at) < 4 * RADIUS * RADIUS
    if o.owner == m.owner and near then share = share + 1 end
  end
  for _, w in pairs(job.want or {}) do
    local more = math.min(math.ceil(w.count / math.max(share, 1)), prototypes.item[w.name].stack_size)
      - inv.get_item_count({ name = w.name, quality = w.quality })
    if more > 0 then take(m, w.name, more, w.quality) end
  end
end

local function next_ghost(m, job)
  local e = m.entity
  return next_target(m, job, e.surface.find_entities_filtered({ type = { "entity-ghost", "tile-ghost" }, force = e.force,
    position = job_area(m, job), radius = RADIUS }), place_item)
end

-- (job.at: round where a roaming member found them.) A better tier they marked themselves (storage.tier_marks, see
-- roam.lua's tier_up) only with the item to hand, never made for it: else the mark is taken back
local function next_upgrade(m, job)
  local e = m.entity
  local list = e.surface.find_entities_filtered({ to_be_upgraded = true, force = e.force, position = job_area(m, job),
    radius = RADIUS })
  local tm, have = storage.tier_marks, {}
  for i = #list, 1, -1 do
    local t = list[i]
    local claim = tm and tm[t.unit_number or 0] and claims()[key_of(t)]
    if tm and tm[t.unit_number or 0] and not (claim and claim ~= m.name and crew()[claim]) then
      local it = upgrade_item(t)
      local k = it and it.name .. "/" .. it.quality
      if k and have[k] == nil then
        have[k] = e.get_main_inventory().get_item_count({ name = it.name, quality = it.quality })
          + available(m, it.name, it.quality)
      end
      if k and have[k] >= it.count then
        have[k] = have[k] - it.count
      else
        tm[t.unit_number] = nil
        t.cancel_upgrade(t.force)
        table.remove(list, i)
      end
    end
  end
  return next_target(m, job, list, upgrade_item)
end

-- what it did and what it's missing; on its own (auto) only news: something done, or a new shortage. A need only for
-- normal quality: the hand makes nothing better, so a rare machine's ghost can't be worked for (a need for the item by
-- name made a normal one, handed it over and found the ghost still wanting a rare one: again and again)
local function report(m, job, verb, reason)
  local parts = {}
  if job.n > 0 then parts[#parts + 1] = verb .. " " .. job.n .. "." end
  local miss, better = {}, false
  for name, it in pairs(job.missing or {}) do
    if type(it) == "number" then it = { name = name, quality = "normal", n = it } end -- (a job from before 0.25.2)
    local normal = it.quality == "normal"
    miss[#miss + 1] = (normal and "" or it.quality .. " ") .. pretty(it.name)
    if normal and it.n > 0 then add_need(m.owner, it.name, it.n, reason or "the blueprint") end
    better = better or not normal
  end
  table.sort(miss)
  local short = #miss > 0 and ("Out of " .. table.concat(miss, ", ", 1, math.min(#miss, 4)) .. "."
    .. (better and " I can only make normal ones." or " I'll go get some.")) or nil
  local news = short and (not job.auto or short ~= m.said_short)
  if news then parts[#parts + 1] = short end
  m.said_short = short
  -- on its own (auto, a goal step) what got done is routine: only a new shortage is news
  if #parts > 0 then say(m, table.concat(parts, " "), (job.auto or job.goal) and not news and "quiet" or nil)
  elseif not job.auto then say(m, "Nothing to " .. job.kind .. " here.") end
  if job.n > 0 and not job.auto then remember(m.owner, m.name .. ": " .. verb:lower() .. " " .. job.n) end
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
    if not g then
      report(m, job, "Built")
      if not e.get_main_inventory().is_empty() then table.insert(m.jobs, 2, { kind = "deliver" }) end
      return true
    end
    if c and e.crafting_queue_size == 0 then craft_for(m, c.item, c.count, c.single) end
    stock(m, job)
    local it = place_item(g) -- (taken now: a trip to the chest comes before the walk to the ghost)
    local have = e.get_main_inventory().get_item_count({ name = it.name, quality = it.quality })
    if have < it.count then take(m, it.name, it.count - have, it.quality) end
    if m.visits and m.visits[1] then return false end -- (the trip first)
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
      m.built = (m.built or 0) + 1
      m.wait_until = game.tick + math.random(8, 20) -- (a hand's pace, not a robot's)
    end
  end
  if g.valid then job.skip[key] = true end
  claims()[key] = nil
  job.target = nil
  return false
end

JOBS.upgrade = function(m, job)
  local e = m.entity
  local t = job.target
  if not (t and t.valid and t.to_be_upgraded()) then
    job.missing = {}
    local c
    t, c = next_upgrade(m, job)
    job.target = t
    if not t then
      report(m, job, "Upgraded", "the upgrades")
      if not e.get_main_inventory().is_empty() then table.insert(m.jobs, 2, { kind = "deliver" }) end
      return true
    end
    if c and e.crafting_queue_size == 0 then craft_for(m, c.item, c.count, c.single) end
    stock(m, job)
    local it = upgrade_item(t)
    local have = e.get_main_inventory().get_item_count({ name = it.name, quality = it.quality })
    if have < it.count then take(m, it.name, it.count - have, it.quality) end
    if m.visits and m.visits[1] then return false end -- (the trip first)
  end
  if not go(m, t.position, math.max(e.build_distance - 2, 2)) then return false end
  local key = key_of(t)
  local it = upgrade_item(t)
  local inv = e.get_main_inventory()
  local have = inv.get_item_count({ name = it.name, quality = it.quality })
  if have < it.count then have = have + take(m, it.name, it.count - have, it.quality) end
  if have < it.count and e.crafting_queue_size > 0 then return false end -- still crafting it
  local tm = storage.tier_marks
  local own = tm and t.unit_number and tm[t.unit_number]
  if own then tm[t.unit_number] = nil end
  if have >= it.count then
    local proto, q = t.get_upgrade_target()
    -- (a belt's items: what the swap drops in their pockets goes back onto the new piece, not home with them)
    local belt = t.type == "transport-belt" or t.type == "underground-belt" or t.type == "splitter"
    local before = {}
    if belt then
      for _, c in pairs(inv.get_contents()) do before[c.name .. "/" .. c.quality] = (before[c.name .. "/" .. c.quality] or 0) + c.count end
    end
    local old_item = belt and t.prototype.items_to_place_this and t.prototype.items_to_place_this[1]
    local new = e.surface.create_entity({ name = proto.name, quality = q, position = t.position, direction = t.direction,
      force = t.force, fast_replace = true, character = e, raise_built = true,
      type = t.type == "underground-belt" and t.belt_to_ground_type or nil })
    if belt and new and new.valid then
      for _, c in pairs(inv.get_contents()) do
        local extra = c.count - (before[c.name .. "/" .. c.quality] or 0)
        if old_item and c.name == old_item.name then extra = extra - (old_item.count or 1) end
        for i = 1, new.get_max_transport_line_index() do
          local line = new.get_transport_line(i)
          while extra > 0 and line.can_insert_at_back() do
            if not line.insert_at_back({ name = c.name, count = 1, quality = c.quality }) then break end
            inv.remove({ name = c.name, count = 1, quality = c.quality })
            extra = extra - 1
          end
        end
      end
    end
    if new and new.valid then
      inv.remove({ name = it.name, count = it.count, quality = it.quality })
      job.n = job.n + 1
      m.wait_until = game.tick + math.random(8, 20)
    else
      job.skip[key] = true
    end
  else
    job.skip[key] = true
  end
  if own and t.valid and job.skip[key] then t.cancel_upgrade(t.force) end -- (their own mark: not left hanging)
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
    for _, c in pairs(e.surface.find_entities_filtered({ position = job_area(m, job), radius = RADIUS,
      to_be_deconstructed = true })) do
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
  local mt = t.prototype.mineable_properties.mining_time or 0.5
  local speed = 1 + e.force.manual_mining_speed_modifier + e.character_mining_speed_modifier -- (research, yours)
  if e.mine_entity(t, false) then
    job.n = job.n + 1
    -- (taking it down takes a moment)
    m.wait_until = game.tick + math.floor(math.min(mt * 40, 60) / math.max(speed, 0.1)) + 4
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
  if job.n >= job.count then
    stop_mining(m)
    say(m, "Got " .. job.n .. " " .. pretty(job.item) .. ".", job.goal and "quiet")
    table.insert(m.jobs, 2, { kind = "deliver" })
    return true
  end
  if not inv.can_insert({ name = job.item }) then
    stop_mining(m)
    table.insert(m.jobs, 1, { kind = "deliver" })
    return false
  end
  local t = job.target
  if not (t and t.valid) or job.since and game.tick - job.since > 900 then -- (15 s at it with nothing to show)
    if t and t.valid then job.skip[t.position.x .. "," .. t.position.y] = true end
    stop_mining(m)
    t = nearest_source(m, job)
    job.target, job.since = t, nil
    if not t then
      say(m, "No " .. pretty(job.item) .. " to mine around here." .. (job.n > 0 and (" Got " .. job.n .. ".") or ""))
      if job.n > 0 then table.insert(m.jobs, 2, { kind = "deliver" }) end
      return true
    end
  end
  local reach = e.resource_reach_distance -- hand mining, trees and rocks too, needs to be this close
  if not go(m, t.position, math.max(reach - 0.6, 1)) then
    m.mining = nil
    job.since = nil -- (the time to give up on a source counts from getting there, not the trip)
    return false
  end
  job.since = job.since or game.tick
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
    m.belts_at = job.here and m.entity.position or nil -- (a roamer's batch: the belts where it is, see belt_lanes)
    local missing = gather(m, r, job.runs)
    m.belts_at = nil
    if missing and job.auto then return true end -- (gone since it looked: no matter)
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
  if job.keep then return true end -- (its own gun or ammo: equipped already)
  say(m, "Made " .. job.started .. " " .. pretty(job.recipe) .. ".", (job.goal or job.auto) and "quiet")
  table.insert(m.jobs, 2, { kind = "deliver" })
  return true
end

JOBS.fetch = function(m, job)
  local got = take(m, job.item, job.count, nil, true)
  say(m, got > 0 and ("Got " .. got .. " " .. pretty(job.item) .. " from the chests.") or job.why
    or ("No " .. pretty(job.item) .. " in the chests."),
    got > 0 and job.goal and "quiet" or nil)
  if got > 0 then table.insert(m.jobs, 2, { kind = "deliver" }) end
  return true
end

JOBS.deliver = function(m, job)
  local inv = m.entity.get_main_inventory()
  if inv.is_empty() then return true end
  -- after a step towards a need or the goal with more to come: kept for the next step (what the crew carry counts),
  -- not walked over to you and fetched back; idle hands it over once no step follows (pockets filling: now)
  if job.step and not m.jobs[2] and (needs(m.owner)[1] or goals()[m.owner or 0]) and inv.count_empty_stacks() > 10 then
    m.kept = true
    return true
  end
  if not go(m, spot(m, anchor(m)), 2) then return false end
  unload(m)
  return true
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
      local cur, q = f.get_recipe()
      if not (cur and cur.name == r.name) then
        if cur and not crew_built(f) then -- (your idle machine on another recipe: borrowed, set back after)
          job.borrowed = job.borrowed or {}
          job.borrowed[#job.borrowed + 1] = { f = f, recipe = cur.name, quality = q and q.name }
        end
        f.set_recipe(r.name)
      end
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
  for _, b in pairs(job.borrowed or {}) do -- (back on your recipe, once nothing of ours is left in it)
    local f = b.f
    if f.valid and f.get_inventory(IN[f.type]).is_empty() and f.get_inventory(OUT[f.type]).is_empty() then
      f.set_recipe(b.recipe, b.quality)
    end
  end
  say(m, "Made " .. job.n .. " " .. pretty(job.item) .. ".", job.goal and "quiet")
  table.insert(m.jobs, 2, { kind = "deliver" })
  return true
end

-- burners low on fuel within 150 tiles of the owner, nearest first
low_burners = function(m, limit)
  local e = m.entity
  local out = {}
  for _, f in pairs(e.surface.find_entities_filtered({ type = { "boiler", "furnace", "mining-drill", "assembling-machine",
    "burner-generator", "inserter", "lab" }, force = e.force, position = anchor(m), radius = 150 })) do
    if needs_fuel(f) and not kept_out(f.surface, f.position) then out[#out + 1] = f end
  end
  table.sort(out, function(a, b) return dist2(e.position, a.position) < dist2(e.position, b.position) end)
  for i = #out, limit + 1, -1 do out[i] = nil end
  return out
end

-- is anything of the force's (not the crew's own, not a character) in area; or a floor the player laid (concrete,
-- stone path: a tile with a hidden tile under it)
local function players_stuff(s, force, area)
  for _, e in pairs(s.find_entities_filtered({ area = area, force = force })) do
    if e.type ~= "character" and e.type ~= "character-corpse" and not crew_built(e) then return true end
  end
  return s.count_tiles_filtered({ area = area, has_hidden_tile = true, limit = 1 }) > 0
end

-- where the crew may put a building of `name` near `near`: on its own grid (a 2x2 at whole tiles, a 3x3 at half tiles:
-- nothing shifts when it's built), placeable as a player's would be, `clear` tiles clear of the player's buildings,
-- ghosts and floors (so it never crowds a production line, an inserter or a walkway) and a tile clear of the crew's
-- own. Nearest first, out to 40 tiles
local function free_spot(s, force, name, near, clear)
  local box = prototypes.entity[name].collision_box
  local w = math.ceil(box.right_bottom.x - box.left_top.x - 0.01)
  local h = math.ceil(box.right_bottom.y - box.left_top.y - 0.01)
  local ox, oy = (w % 2 == 1) and 0.5 or 0, (h % 2 == 1) and 0.5 or 0
  local cx, cy = math.floor(near.x + 0.5), math.floor(near.y + 0.5)
  for r = 0, 40 do
    for dx = -r, r do
      for dy = -r, r do
        if math.max(math.abs(dx), math.abs(dy)) == r then
          local pos = { x = cx + dx + ox, y = cy + dy + oy }
          -- (count_entities_filtered's invert would invert the force too: the player's own buildings then didn't count)
          if s.can_place_entity({ name = name, position = pos, force = force, build_check_type = defines.build_check_type.manual })
            and not kept_out(s, pos)
            and not players_stuff(s, force, { { pos.x - w / 2 - clear, pos.y - h / 2 - clear }, { pos.x + w / 2 + clear, pos.y + h / 2 + clear } })
            and s.count_entities_filtered({ area = { { pos.x - w / 2 - 1, pos.y - h / 2 - 1 }, { pos.x + w / 2 + 1, pos.y + h / 2 + 1 } },
              force = force, type = { "furnace", "assembling-machine", "electric-pole", "boiler", "generator", "offshore-pump" }, limit = 1 }) == 0 then
            return pos
          end
        end
      end
    end
  end
end

-- where the crew's own machines go: beside the ones they built before, else open ground a little way from the owner
local function crew_area(m, type)
  storage.crew_built = storage.crew_built or {}
  for i = #storage.crew_built, 1, -1 do
    local b = storage.crew_built[i]
    if not b.valid then
      table.remove(storage.crew_built, i)
    elseif b.type == type and b.surface == m.entity.surface and dist2(b.position, anchor(m)) < RADIUS * RADIUS then
      return b.position
    end
  end
  local a = anchor(m)
  return { x = a.x + 8, y = a.y - 6 }
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
    job.at = free_spot(e.surface, e.force, proto.name, crew_area(m, proto.type), 3)
    if not job.at then say(m, "No clear ground for a " .. pretty(job.item) .. " near you.") return true end
  end
  if not go(m, job.at, math.max(e.build_distance - 2, 2)) then return false end
  spec.position = job.at
  if not e.surface.can_place_entity(spec) then -- (something got built there meanwhile)
    if job.fixed then return true end
    job.at = nil
    return false
  end
  spec.build_check_type, spec.raise_built = nil, true
  local built = e.surface.create_entity(spec)
  if built then
    inv.remove({ name = job.item, count = 1 })
    job.n = 1
    if not job.fixed then
      storage.crew_built = storage.crew_built or {}
      table.insert(storage.crew_built, built)
    end
    say(m, "Set up a " .. pretty(job.item) .. ".", "quiet")
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

-- ------------------------------------------------------------------------------------------------------------- shared
-- what the other files use of this one, and its link: control.lua calls it once all files are loaded
return {
  share = { add_need = add_need, claims = claims, DOING_WORD = DOING_WORD, gather = gather, key_of = key_of,
    low_burners = low_burners, nearest_source = nearest_source, needs = needs, players_stuff = players_stuff,
    product_amount = product_amount, upgrade_item = upgrade_item },
  link = function(A)
    anchor, available, crew, crew_built, dist2 = A.anchor, A.available, A.crew, A.crew_built, A.dist2
    fuel_available, go, handcraft_recipe, IN, kept_out = A.fuel_available, A.go, A.handcraft_recipe, A.IN, A.kept_out
    machines_for, needs_fuel, OUT, pretty, RADIUS = A.machines_for, A.needs_fuel, A.OUT, A.pretty, A.RADIUS
    refuel, remember, say, sources_for, spot = A.refuel, A.remember, A.say, A.sources_for, A.spot
    goals, stop_mining, take, unload = A.goals, A.stop_mining, A.take, A.unload
  end,
  JOBS = JOBS,
}
