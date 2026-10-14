-- AI Crew: guns and ammo, fighting, defending the base, nests, fishing to heal. One of control.lua's files.

-- (the other files' that this one uses: set by link, at the end)
local add_need, anchor, available, belt_lanes, CREW, crew, dist2, fly, go, handcraft_recipe, key_of, line, needs,
  network, owner_char, pretty, remember, say, sources, stop_mining, stop_walk, take

-- ----------------------------------------------------------------------------------------------------------- combat

local JOBS = {} -- (this file's jobs: defend, back, fish, attack; control.lua's JOBS gets them)
local GUNS -- hand-held guns, longest range first
local self_craft

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

-- queues hand-crafting `count` of item for itself (kept, not delivered), once; true when queued. What it lacks for it
-- becomes the crew's need, as for any craft
self_craft = function(m, item, count)
  for _, j in pairs(m.jobs) do if j.kind == "craft" and j.recipe == item then return false end end
  -- (already working for it, or for what it's made of: not again; and one try a minute, so a craft short of its
  -- ingredients isn't started, given up and started again every half second)
  for _, nd in pairs(needs(m.owner)) do if nd.item == item or nd.reason == pretty(item) then return false end end
  m.crafted_at = m.crafted_at or {}
  if game.tick - (m.crafted_at[item] or -3600) < 3600 then return false end
  m.crafted_at[item] = game.tick
  if not handcraft_recipe(m.entity.force, item) then
    return add_need(m.owner, item, count, "the crew's guns")
  end
  if not m.jobs[1] and not m.trip_from then -- (standing about: a trip of its own, to the chests; back after)
    m.trip_from = { x = m.entity.position.x, y = m.entity.position.y }
  end
  table.insert(m.jobs, 1, { kind = "craft", recipe = item, count = count, keep = true, n = 0, skip = {} })
  return true
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
  -- what's at hand (as available() counts it): one look at every chest, lane and the network for all the items
  -- asked about, not one each (a big base has hundreds of each near home)
  local stock
  local function has(item)
    if inv.get_item_count(item) > 0 then return true end
    if not stock then
      stock = {}
      local function add(list)
        for _, it in pairs(list) do
          if it.quality == "normal" then stock[it.name] = (stock[it.name] or 0) + it.count end
        end
      end
      for _, src in pairs(sources(m)) do add(src.get_contents()) end
      for _, l in pairs(belt_lanes(m)) do add(l.get_contents()) end
      local net = network(m)
      if net then add(net.get_contents()) end
    end
    return (stock[item] or 0) > 0
  end
  local armor = e.get_inventory(defines.inventory.character_armor)
  if armor and armor.is_empty() then -- the best armor to hand (most resistance)
    local best, bs
    for name, it in pairs(prototypes.get_item_filtered({ { filter = "type", type = "armor" } })) do
      if not it.hidden and has(name) then
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
  for i = 2, #guns do
    if guns[i].valid_for_read and not ammo[i].valid_for_read then
      if inv.insert(guns[i]) > 0 then guns[i].clear() end
    end
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
        if self_craft(m, pick, 1) then say(m, "No gun to hand. I'll make myself a " .. pretty(pick) .. ".") end
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
        if self_craft(m, am, 20) then say(m, "Out of ammo. Making " .. pretty(am) .. ".") end
        break
      end
    end
  end
end

-- stops shooting: a character keeps firing at the last spot it was given until it's told to stop
local function hold_fire(m)
  if m.entity.shooting_state.state ~= defines.shooting.not_shooting then
    m.entity.shooting_state = { state = defines.shooting.not_shooting, position = m.entity.position }
  end
end

-- every half second: shoot what's in range, fall back to the owner when hurt, come back when healed
local function fight(m)
  local e = m.entity
  local hp = e.health / e.max_health
  -- a fish heals 80, as a player's would: eaten whenever that much is missing (in a fight or after it), sooner when low
  if (e.max_health - e.health >= 80 or hp < 0.5) and prototypes.item["raw-fish"] then
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
    if not m.jobs[1] and not m.trip_from then -- (standing about: back where it stood once healed)
      m.trip_from = { x = e.position.x, y = e.position.y }
    end
    m.retreat, m.target = true, nil
    e.shooting_state = { state = defines.shooting.not_shooting, position = e.position }
    stop_mining(m)
    go(m, anchor(m), 4)
    say(m, line(m, "hurt", { at = e.position }))
    return
  end
  if m.defend == false and not (m.jobs[1] and m.jobs[1].kind == "attack") then m.target = nil hold_fire(m) return end
  local range = gun_range(m)
  if range == 0 and game.tick >= (m.arm_at or 0) then -- (no gun: looked for every 5 s, not each half second)
    m.arm_at = game.tick + 300
    arm(m)
    range = gun_range(m)
  end
  -- the target: of the biters in range the most hurt (finish it off), else the nearest of anything
  local enemy
  if range > 0 and not m.retreat then
    local low
    for _, u in pairs(e.surface.find_enemy_units(e.position, range, e.force)) do
      local r = u.health / u.max_health
      if not low or r < low then enemy, low = u, r end
    end
    enemy = enemy or e.surface.find_nearest_enemy({ position = e.position, max_distance = range, force = e.force })
  end
  -- a biter (a melee one) right on it: step back and keep shooting
  if enemy and enemy.type == "unit" and not m.move then
    local close = e.surface.find_enemy_units(e.position, 3.5, e.force)[1]
    local ap = close and close.prototype.attack_parameters
    if close and ap and ap.range < 3 then
      local dx, dy = e.position.x - close.position.x, e.position.y - close.position.y
      local d = math.max(math.sqrt(dx * dx + dy * dy), 0.1)
      local to = e.surface.find_non_colliding_position(CREW, { x = e.position.x + dx / d * 6, y = e.position.y + dy / d * 6 }, 3, 0.5)
      if to then go(m, to, 1) end
    end
  end
  if enemy and not m.target then
    if not m.said_fight or game.tick - m.said_fight > 1800 then
      m.said_fight = game.tick
      say(m, line(m, "contact", { item = pretty(enemy.name), at = enemy.position }))
    end
  end
  m.target = enemy
  if not enemy then hold_fire(m) end -- (dead, or gone out of range: control.lua only stops for a dead one)
  if enemy and enemy.valid then
    local ammo = e.get_inventory(defines.inventory.character_ammo)
    if ammo and ammo.get_item_count() < 5 then arm(m) end
  end
end

-- Your buildings under attack: every armed fighter of the crew within 160 tiles drops what it's doing and rushes
-- over (flying, with jetpacks), fights there until it has been quiet for 5 seconds, then goes back to its work, or
-- with none, back to where it stood (a trip of its own, see JOBS.back). who: you (your character) hit: your own
-- crew that roam or follow you come to you and fight round you wherever you go, till it's been quiet 10 seconds
local function alarm(surface, force, ent, who)
  local pos = ent.position
  local owner = who and who.player and who.player.index
  for _, m in pairs(crew()) do
    local e = m.entity
    if e.valid and e.force == force and e.surface == surface and m.defend ~= false and not m.retreat
      and (not who or (m.roam or m.follow) and (not who.player or m.owner == owner))
      and dist2(e.position, pos) < 160 * 160 and not (m.jobs[1] and (m.jobs[1].kind == "defend" or m.jobs[1].kind == "attack")) then
      if gun_range(m) == 0 then arm(m) end
      if gun_range(m) > 0 then
        stop_mining(m)
        local j = m.jobs[1]
        if not m.trip_from and (not j or j.kind == "back") then -- (standing about, or on its way back from a trip)
          m.trip_from = j and j.at or { x = e.position.x, y = e.position.y }
          if j then table.remove(m.jobs, 1) end
        end
        table.insert(m.jobs, 1, { kind = "defend", at = { x = pos.x, y = pos.y }, who = who, n = 0, skip = {} })
        m.wait_until = nil
        if game.tick - (storage.alarm_said or -3600) > 1800 then
          storage.alarm_said = game.tick
          say(m, line(m, who and "help" or "alarm", { item = pretty(ent.name), at = pos }))
          remember(m.owner, who and "biters went for the player; the crew came to help"
            or ("biters attacked the " .. pretty(ent.name) .. "; the crew went to fight them"))
        end
      end
    end
  end
end

JOBS.defend = function(m, job)
  local e = m.entity
  if m.retreat then return false end
  if gun_range(m) == 0 then return true end
  if job.who then -- (you: wherever you are now; a new route only when you've gone 4 tiles)
    if not (job.who.valid and job.who.surface == e.surface) then return true end
    local p = job.who.position
    if dist2(job.at, p) > 16 then job.at = { x = p.x, y = p.y } end
  end
  local enemy = e.surface.find_nearest_enemy({ position = job.at, max_distance = 32, force = e.force })
  local d2 = dist2(e.position, enemy and enemy.position or job.at)
  if enemy then
    job.quiet = nil
    if d2 > 24 * 24 and fly(m, enemy.position) then return false end -- (rushing there)
    go(m, enemy.position, math.max(gun_range(m) - 4, 4)) -- (in range of it; fight() does the shooting)
    return false
  end
  job.quiet = job.quiet or game.tick
  if game.tick - job.quiet > (job.who and 600 or 300) then return true end
  if d2 > 24 * 24 and fly(m, job.at) then return false end
  go(m, job.at, 8)
  return false
end

-- Trips (fuel, what a need or the goal takes, fish, work round the base, a fight, clearing nests, falling back hurt,
-- a gun or ammo made for itself): where they stood when they took it on is kept (m.trip_from), and once there is
-- nothing more to do they go back there, so they're still about the base: walking, flying when far. Not when it's
-- within 16 tiles, nor when they roam or follow you (that brings them back). Other orders forget the place. (Kept in
-- think, alarm, add_job, self_craft and fight; gone back to from idle)
JOBS.back = function(m, job)
  if m.retreat then return false end -- (hurt: healing where it fell back to first)
  job.t0 = job.t0 or game.tick
  if m.roam or m.follow and owner_char(m) or game.tick - job.t0 > 3600 then return true end -- (roaming, or following you: their own way)
  if dist2(m.entity.position, job.at) > 24 * 24 and fly(m, job.at) then return false end
  return go(m, job.at, 2)
end

-- raw fish from the water, caught by hand (5 a fish) when the crew have none left to heal with
JOBS.fish = function(m, job)
  local e = m.entity
  job.t0 = job.t0 or game.tick
  local have = e.get_main_inventory().get_item_count("raw-fish")
  if have >= job.count or game.tick - job.t0 > 3600 then -- (enough, or a minute at it: what it has will do)
    if have < job.count then m.fish_wait = game.tick + 18000 end
    say(m, "Caught " .. have .. " fish.", "quiet")
    return true
  end
  local f = job.target
  if not (f and f.valid) then
    f = nil
    for _, r in ipairs({ 48, 120, 250 }) do
      local bd
      for _, c in pairs(e.surface.find_entities_filtered({ type = "fish", position = e.position, radius = r, limit = 60 })) do
        if not job.skip[key_of(c)] then
          local d = dist2(e.position, c.position)
          if not bd or d < bd then f, bd = c, d end
        end
      end
      if f then break end
    end
    if not f then
      m.fish_wait = game.tick + 36000
      say(m, "No fish anywhere near. We'll have to manage without.")
      return true
    end
    job.target, job.target_at = f, game.tick
  end
  -- out in the water: as close as the shore gets them is close enough when it's in reach; 15 s without: another fish
  local reach = e.reach_distance
  local near = dist2(e.position, f.position) <= reach * reach
  if not near then
    if game.tick - job.target_at > 900 then
      job.skip[key_of(f)], job.target = true, nil
      stop_walk(m)
    else
      go(m, f.position, math.max(reach - 2, 2))
    end
    return false
  end
  if not e.mine_entity(f, false) then job.skip[key_of(f)] = true end
  m.wait_until = game.tick + 30
  job.target = nil
  return false
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
    for _, c in pairs(e.surface.find_entities_filtered({ type = { "unit-spawner", "turret" }, position = job.center or anchor(m), radius = job.radius or 96 })) do
      if e.force.is_enemy(c.force) then
        local d = dist2(e.position, c.position)
        if not bd or d < bd then t, bd = c, d end
      end
    end
    job.target = t
    if not t then
      say(m, job.n > 0 and ("Cleared " .. job.n .. " nest" .. (job.n > 1 and "s" or "") .. ".") or "No nests around here.")
      if job.n > 0 then remember(m.owner, m.name .. " cleared " .. job.n .. " nest" .. (job.n > 1 and "s" or "")) end
      return true
    end
  end
  go(m, t.position, math.max(gun_range(m) - 3, 4))
  return false
end

-- ------------------------------------------------------------------------------------------------------------- shared
-- what the other files use of this one, and its link: control.lua calls it once all files are loaded
return {
  share = { alarm = alarm, fight = fight, gun_range = gun_range },
  link = function(A)
    add_need, anchor, available, belt_lanes, CREW = A.add_need, A.anchor, A.available, A.belt_lanes, A.CREW
    crew, dist2, fly, go, handcraft_recipe, key_of = A.crew, A.dist2, A.fly, A.go, A.handcraft_recipe, A.key_of
    line, needs, network, owner_char, pretty, remember = A.line, A.needs, A.network, A.owner_char, A.pretty, A.remember
    say, sources, stop_mining, stop_walk, take = A.say, A.sources, A.stop_mining, A.stop_walk, A.take
  end,
  JOBS = JOBS,
}
