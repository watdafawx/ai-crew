-- AI Crew: roaming (a look round: nests, dark or starved machines, upgrades, a batch of what runs short), offers
-- and hints. One of control.lua's files.

-- (the other files' that this one uses: set by link, at the end)
local a_an, any_player, available, canned, chatter, CREW, crew_built, dist2, gather, go, goals, gun_range,
  handcraft_recipe, in_box, kept_out, key_of, line, llm_settings, members_of, needs, owner_char, player_setting,
  power_to, pretty, product_amount, py, remember, ROAM, say, spot, upgrade_item

-- --------------------------------------------------------------------------------------------------------- roaming
-- Roam: instead of following, each one wanders the area round the player (or home) on its own, stops a while to look
-- around, and deals with what it finds as a player would: goes after a nest when it's armed and may fight, runs poles
-- to a machine standing dark (pole by pole, while poles are all it takes) and mentions machines starved of inputs or
-- backed up (nothing at all taking their output; a full belt is no news). Each thing once; those remarks at most every
-- 3 minutes a member. Also: upgrade marks round where it walks (idle), the next tier for what's in stock
-- (tier_up), and now and then a few of what runs short, hand-crafted (craft_short). You hit: they come (alarm).

local S = defines.entity_status
local REMARKS = {}
for name, kind in pairs({ item_ingredient_shortage = "starved", no_ingredients = "starved", fluid_ingredient_shortage = "starved",
  full_output = "backed", waiting_for_space_in_destination = "backed" }) do
  if S[name] then REMARKS[S[name]] = kind end
end
-- does something take f's output (an inserter or loader taking from it; a drill's belt, chest or machine)? Then "output
-- full" is only a full belt or chest downstream: normal, not worth a word
local function output_taken(f)
  if f.type == "mining-drill" then
    return f.drop_target ~= nil or f.surface.count_entities_filtered({ position = f.drop_position, limit = 1,
      type = { "transport-belt", "underground-belt", "splitter", "loader", "loader-1x1", "linked-belt" } }) > 0
  end
  local b = f.bounding_box
  local area = { { b.left_top.x - 3, b.left_top.y - 3 }, { b.right_bottom.x + 3, b.right_bottom.y + 3 } }
  for _, i in pairs(f.surface.find_entities_filtered({ type = "inserter", area = area })) do
    if i.pickup_target == f then return true end
  end
  for _, l in pairs(f.surface.find_entities_filtered({ type = { "loader", "loader-1x1" }, area = area })) do
    if l.loader_type == "output" and l.loader_container == f then return true end
  end
  return false
end

-- a better tier for what it walks past (setting "Crew upgrade to better tiers"): your machines, inserters, furnaces
-- whose next tier is in stock already (pockets, chests, belts, network: never made for it) get the upgrade mark, a few
-- a look and no more than there are items, and the upgrade job does the rest (recipe, contents, direction kept). Never
-- belts (a partly upgraded belt only holds the rest back), nor in a keep-out place or a bpgen line. Its own marks are
-- kept in storage.tier_marks (unit number -> entity): one it can't carry out after all it takes back (next_upgrade)
local tier_names -- (prototypes with a next tier, belts aside: once a session)
local function tier_up(m)
  local e = m.entity
  local on = storage.test_tiers
  if on == nil then
    local pl = m.owner and game.get_player(m.owner) or not m.owner and any_player()
    on = not pl or player_setting(pl, "ai-crew-tier-upgrades") ~= false
  end
  if not on or m.auto == false then return end
  if not tier_names then
    local names, belts = {}, { ["transport-belt"] = true, ["underground-belt"] = true, splitter = true, loader = true,
      ["loader-1x1"] = true, ["linked-belt"] = true, ["lane-splitter"] = true }
    for name, p in pairs(prototypes.entity) do
      if p.next_upgrade and not belts[p.type] then names[#names + 1] = name end
    end
    tier_names = names
  end
  if #tier_names == 0 then return end
  storage.tier_marks = storage.tier_marks or {}
  local tm, s = storage.tier_marks, e.surface
  for k, o in pairs(tm) do if not (o.valid and o.to_be_upgraded()) then tm[k] = nil end end
  local boxes, have, n = {}, {}, 0
  for _, g in pairs(storage.goals or {}) do if g.line and g.line.box then boxes[#boxes + 1] = g.line.box end end
  for _, f in pairs(s.find_entities_filtered({ name = tier_names, force = e.force, position = e.position,
    radius = 20, limit = 40 })) do
    local up = f.prototype.next_upgrade
    local it = up and not f.to_be_upgraded() and not kept_out(s, f.position) and up.items_to_place_this
      and up.items_to_place_this[1]
    for _, box in ipairs(boxes) do if it and in_box(box, f.position, 1) then it = nil end end
    if it then
      local q = f.quality.name
      local k = it.name .. "/" .. q
      if have[k] == nil then -- (what's in stock, less what their marks already wait for)
        have[k] = e.get_main_inventory().get_item_count({ name = it.name, quality = q }) + available(m, it.name, q)
        for _, o in pairs(tm) do
          local oi = upgrade_item(o)
          if oi and oi.name == it.name and oi.quality == q then have[k] = have[k] - oi.count end
        end
      end
      local to = { name = up.name, quality = q }
      if have[k] >= (it.count or 1) and f.order_upgrade({ target = to, force = f.force }) then
        have[k], n = have[k] - (it.count or 1), n + 1
        tm[f.unit_number] = f
        if n >= 3 then break end
      end
    end
  end
  if n == 0 then return end
  m.jobs[#m.jobs + 1] = { kind = "upgrade", auto = true, n = 0, skip = {}, at = { x = e.position.x, y = e.position.y } }
  return true
end

-- now and then (every 3 to 5 minutes) a roamer hand-crafts a few (5 to 10) of what the base uses more of than it
-- makes: a recipe for the hand, with what it takes at hand (pockets, chests, the belts where it stands: only what the
-- batch takes), brought to you after. Quietly: a bubble
local shortage -- (with the offers, below)
local function craft_short(m)
  if m.auto == false or game.tick < (m.craft_at or 0) then return end
  m.craft_at = game.tick + 1800 -- (nothing to make: another look in 30 s)
  local e = m.entity
  local count
  m.belts_at = { x = e.position.x, y = e.position.y }
  local item = shortage(m.owner, e.surface, e.force, function(name, d)
    local r = d >= 10 and handcraft_recipe(e.force, name)
    if not r then return false end
    local per = product_amount(r, name)
    for _, c in ipairs({ math.min(math.max(math.ceil(d / 30), 5), 10), 5 }) do
      if not gather(m, r, math.ceil(c / per), true) then count = c return true end
    end
    return false
  end)
  m.belts_at = nil
  if not item then return end
  m.craft_at = game.tick + math.random(10800, 18000)
  m.jobs[#m.jobs + 1] = { kind = "craft", recipe = item, count = count, auto = true, here = true, n = 0, skip = {} }
  say(m, "We go through more " .. pretty(item) .. " than we make. A few more won't hurt.", "quiet")
  remember(m.owner, m.name .. " hand-crafted some " .. pretty(item) .. " (more used than made)")
  return true
end

-- one look round where it stands; true when it found something to do or say
local function notice(m)
  local e = m.entity
  local s = e.surface
  m.noticed = m.noticed or {}
  if table_size(m.noticed) > 300 then m.noticed = {} end
  local function new(x)
    local k = key_of(x)
    if m.noticed[k] then return false end
    m.noticed[k] = true
    return true
  end
  for _, n in pairs(s.find_entities_filtered({ type = { "unit-spawner", "turret" }, position = e.position, radius = 32 })) do
    if e.force.is_enemy(n.force) and new(n) then
      local armed = m.defend ~= false and gun_range(m) > 0
      say(m, line(m, armed and "nest" or "nest_unarmed", { item = pretty(n.name), at = n.position }))
      remember(m.owner, m.name .. " found " .. a_an(n.name) .. (armed and " and went after it" or ", but had no gun"))
      if armed then m.jobs[#m.jobs + 1] = { kind = "attack", n = 0, skip = {}, center = n.position, radius = 24 } end
      return true
    end
  end
  local remark = game.tick >= (m.remark_at or 0)
  for _, f in pairs(s.find_entities_filtered({ type = { "assembling-machine", "furnace", "lab", "mining-drill" }, force = e.force,
    position = e.position, radius = 20 })) do
    local st = f.status
    local kind = st == S.no_power and "dark" or REMARKS[st]
    if kind and kept_out(s, f.position) or kind == "backed" and output_taken(f) then kind = nil end
    if kind and (remark or kind == "dark") and new(f) then
      local job = kind == "dark" and m.auto ~= false and power_to(m, f, 0)
      if job and job.kind == "place" then
        m.powering, m.power_steps = f, 1
        job.n, job.skip = 0, {}
        m.jobs[#m.jobs + 1] = job
      elseif kind == "dark" then
        if not remark then return false end
        kind = "dark_note"
      end
      say(m, line(m, kind, { item = pretty(f.name), at = f.position }))
      remember(m.owner, m.name .. " found " .. a_an(f.name) .. ({ dark = " with no power and ran poles to it",
        dark_note = " with no power", starved = " short of inputs", backed = " with its output backed up" })[kind])
      if kind ~= "dark" then m.remark_at = game.tick + 10800 end
      return true
    end
  end
end

local function roam(m)
  local e = m.entity
  local c = owner_char(m)
  local center = c and c.position or m.home
  local f = m.powering -- the next pole to a dark machine, while that's all it takes
  if f then
    m.powering = nil
    if f.valid and f.status == S.no_power and m.power_steps < 12 then
      local job = power_to(m, f, 0)
      if job and job.kind == "place" then
        m.powering, m.power_steps = f, m.power_steps + 1
        job.n, job.skip = 0, {}
        m.jobs[#m.jobs + 1] = job
        return
      end
    end
  end
  if dist2(e.position, center) > (ROAM + 16) ^ 2 then -- (the player went off: catch up)
    m.roam_walk = nil
    go(m, spot(m, center), 8)
    return
  end
  if m.roam_walk then -- got there: a look round, then a while here
    m.roam_walk = nil
    m.roam_at = game.tick + math.random(300, 900)
    if notice(m) or tier_up(m) or craft_short(m) then return end
  end
  if game.tick < (m.roam_at or 0) then return end
  local a, r = math.random() * 2 * math.pi, 6 + math.random() * (ROAM - 6)
  local to = e.surface.find_non_colliding_position(CREW, { x = center.x + math.cos(a) * r, y = center.y + math.sin(a) * r }, 8, 0.5)
  if not to or kept_out(e.surface, to) then m.roam_at = game.tick + 120 return end
  m.roam_walk = true
  go(m, to, 1.5)
end

-- Proposals. Every 10 minutes, with no goal and nothing needed: they look at what your factory used more of than it
-- made in the last 10 minutes (items with a recipe), and offer to deal with the worst of it: make a batch, or a
-- production line when bpgen is there. "yes" (sure, ok, do it...) makes it the goal; "no" leaves that item alone for
-- half an hour. Unanswered, the offer lapses after 5 minutes.
-- (ok(name, d): only items it passes, asked of the worse ones only)
shortage = function(owner, surface, force, ok)
  local stats = force.get_item_production_statistics(surface)
  local declined = storage.declined and storage.declined[owner or 0] or {}
  local best, bd
  for name in pairs(stats.output_counts) do
    local r = force.recipes[name]
    if r and r.enabled and prototypes.item[name] and game.tick - (declined[name] or -1e9) > 108000 then
      local function flow(cat)
        return stats.get_flow_count({ name = name, category = cat, precision_index = defines.flow_precision_index.ten_minutes, count = true })
      end
      local d = flow("output") - flow("input")
      if d > 0 and (not bd or d > bd) and (not ok or ok(name, d)) then best, bd = name, d end
    end
  end
  return best, bd
end

local function propose(owner)
  local members = members_of(owner)
  local k = owner or 0
  storage.proposals = storage.proposals or {}
  if #members == 0 or storage.proposals[k] or goals()[k] or #needs(owner) > 0 then return end
  local m = members[1]
  local item, d = shortage(owner, m.entity.surface, m.entity.force)
  if not item or d < 20 then return end
  local bp = remote.interfaces["bpgen"] and remote.interfaces["bpgen"].plan_line and true or nil
  local offer = { item = item, count = math.min(math.max(math.ceil(d / 50) * 50, 100), 2000), use_line = bp,
    rate = math.max(math.ceil(d / 50) * 5, 10), at = game.tick }
  storage.proposals[k] = offer
  local what = bp and ("build a production line for " .. pretty(item)) or ("make " .. offer.count .. " " .. pretty(item))
  remember(owner, "offered to " .. what .. " (" .. math.floor(d) .. " more used than made in 10 minutes)")
  local ev = { kind = bp and "propose_line" or "propose", vars = { item = pretty(item), n = offer.count },
    text = "the crew noticed " .. pretty(item) .. " runs short (" .. math.floor(d) .. " more used than made in 10 minutes). "
      .. "One of them asks the player, in one line, whether to " .. what .. ": a yes/no question" }
  local player = owner and game.get_player(owner)
  if player then chatter(player, ev) else canned(owner, members, ev) end
end

-- Hints. What a player at your side would point out, said in chat and out loud by the member nearest you: research
-- to start, machines starved of an ingredient (which one), power running short, machines with none, smelting or
-- mining backed up, something made far beyond what's used, and after 5 minutes with nothing built, crafted or
-- researched, what to do next (research, else an offer to make what runs short). One every 5 minutes at most, the same
-- one not again for half an hour; the AI words them when there is one. Setting: "Crew give hints".
local function cheapest_tech(force)
  local best, bc
  for _, t in pairs(force.technologies) do
    if t.enabled and not t.researched and not t.prototype.hidden and t.research_unit_count > 0 then
      local ok = true
      for _, pre in pairs(t.prerequisites) do if not pre.researched then ok = false break end end
      local cost = t.research_unit_count * #t.research_unit_ingredients
      if ok and (not bc or cost < bc) then best, bc = t, cost end
    end
  end
  return best
end

-- the ingredient a machine of this recipe is out of
local function missing_input(f)
  local r = f.get_recipe()
  local inv = f.get_inventory(defines.inventory.crafter_input or defines.inventory.assembling_machine_input)
  if not (r and inv) then return end
  for _, ing in pairs(r.ingredients) do
    if ing.type == "item" and inv.get_item_count(ing.name) < ing.amount then return ing.name end
  end
end

local function find_hint(owner, surface, force, at)
  local h = {}
  -- machines round you, grouped by what's wrong with them
  local starved, backed, low, dark = {}, {}, 0, 0
  local first = {} -- (where the first machine of each kind of trouble is: the hint points at it)
  for _, f in pairs(surface.find_entities_filtered({ type = { "assembling-machine", "furnace", "mining-drill", "lab" }, force = force,
    position = at, radius = 100 })) do
    local st = f.status
    if st == S.low_power then low, first.low = low + 1, first.low or f.position
    elseif st == S.no_power and not crew_built(f) then dark, first.dark = dark + 1, first.dark or f.position
    elseif (st == S.item_ingredient_shortage or st == S.no_ingredients) and f.type == "assembling-machine" then
      local r = f.get_recipe()
      local miss = r and missing_input(f)
      if miss then
        local g = starved[r.name] or { n = 0, miss = miss, at = f.position }
        g.n = g.n + 1
        starved[r.name] = g
      end
    elseif (st == S.full_output or st == S.waiting_for_space_in_destination) and (f.type == "furnace" or f.type == "mining-drill")
      and not output_taken(f) then -- (output onto a full belt or into a full chest: normal)
      local r = f.type == "furnace" and f.get_recipe()
      local what = r and r.name or f.mining_target and f.mining_target.name or f.name
      backed[what] = (backed[what] or 0) + 1
      first["backed:" .. what] = first["backed:" .. what] or f.position
    end
  end
  if low >= 3 then h[#h + 1] = { key = "power", kind = "hint_power", vars = { n = low, at = first.low }, text = low .. " machines are on low power" } end
  for name, g in pairs(starved) do
    if g.n >= 3 then
      h[#h + 1] = { key = "starved:" .. name, kind = "hint_starved", vars = { n = g.n, item = pretty(name), other = pretty(g.miss), at = g.at },
        text = g.n .. " machines making " .. pretty(name) .. " are starved of " .. pretty(g.miss) }
    end
  end
  if dark >= 3 then h[#h + 1] = { key = "dark", kind = "hint_dark", vars = { n = dark, at = first.dark }, text = dark .. " machines near the player have no power" } end
  for name, n in pairs(backed) do
    if n >= 4 then
      h[#h + 1] = { key = "backed:" .. name, kind = "hint_backed", vars = { n = n, item = pretty(name), at = first["backed:" .. name] },
        text = n .. " " .. pretty(name) .. " machines are backed up, nothing takes their output" }
    end
  end
  -- made far beyond what's used
  local stats = force.get_item_production_statistics(surface)
  for name in pairs(stats.input_counts) do
    local function flow(cat)
      return stats.get_flow_count({ name = name, category = cat, precision_index = defines.flow_precision_index.ten_minutes, count = true })
    end
    local made = flow("input")
    if made >= 2000 and flow("output") < made * 0.1 then
      h[#h + 1] = { key = "over:" .. name, kind = "hint_over", vars = { n = math.floor(made), item = pretty(name) },
        text = math.floor(made) .. " " .. pretty(name) .. " made in 10 minutes and almost none used" }
    end
  end
  -- nothing done for 5 minutes
  storage.progress_at = storage.progress_at or {}
  local k = owner or 0
  storage.progress_at[k] = storage.progress_at[k] or game.tick
  if game.tick - storage.progress_at[k] >= 18000 then
    local tech = not force.current_research and #force.research_queue == 0 and cheapest_tech(force)
    if tech then
      h[#h + 1] = { key = "research:" .. tech.name, kind = "hint_research", vars = { item = pretty(tech.name) },
        text = "nothing is being researched; " .. pretty(tech.name) .. " is the cheapest next technology" }
    else
      h[#h + 1] = { key = "stall", kind = "hint_stall", text = "the player has built and researched nothing for 5 minutes", stall = true }
    end
  end
  return h
end

-- one hint now, if there's one not given lately; its key
local function hint(owner, now)
  local members = members_of(owner)
  if #members == 0 then return end
  local k = owner or 0
  storage.hint_at, storage.hinted = storage.hint_at or {}, storage.hinted or {}
  storage.hinted[k] = storage.hinted[k] or {}
  if not now and game.tick - (storage.hint_at[k] or -18000) < 18000 then return end
  local player = owner and game.get_player(owner)
  local c = player and player.character
  local m = members[1]
  if c then table.sort(members, function(a, b) return dist2(a.entity.position, c.position) < dist2(b.entity.position, c.position) end) m = members[1] end
  for _, h in ipairs(find_hint(owner, c and c.surface or m.entity.surface, m.entity.force, c and c.position or m.home)) do
    if game.tick - (storage.hinted[k][h.key] or -108000) >= 108000 then
      storage.hinted[k][h.key], storage.hint_at[k] = game.tick, game.tick
      if h.stall then
        storage.progress_at[k] = game.tick -- (asked once; not again until another 5 minutes pass)
        storage.proposals = storage.proposals or {}
        propose(owner)
        if storage.proposals[k] then return h.key end
      end
      remember(owner, m.name .. " pointed out: " .. h.text)
      local llm = llm_settings(player)
      if player and py() and llm.provider ~= "off" then
        chatter(player, { kind = h.kind, vars = h.vars, who = nil,
          text = "a hint for the player: " .. h.text .. ". One of them (" .. m.name .. " ideally) tells the player in one short, " ..
            "helpful line, with a concrete suggestion" })
      else
        say(m, line(m, h.kind, h.vars))
      end
      return h.key
    end
  end
end

-- ------------------------------------------------------------------------------------------------------------- shared
-- what the other files use of this one, and its link: control.lua calls it once all files are loaded
return {
  share = { hint = hint, propose = propose, roam = roam },
  link = function(A)
    a_an, any_player, available, canned, chatter, CREW = A.a_an, A.any_player, A.available, A.canned, A.chatter, A.CREW
    crew_built, dist2, gather, go, goals, gun_range = A.crew_built, A.dist2, A.gather, A.go, A.goals, A.gun_range
    handcraft_recipe, in_box, kept_out, key_of, line = A.handcraft_recipe, A.in_box, A.kept_out, A.key_of, A.line
    llm_settings, members_of, needs, owner_char = A.llm_settings, A.members_of, A.needs, A.owner_char
    player_setting, power_to, pretty, product_amount = A.player_setting, A.power_to, A.pretty, A.product_amount
    py, remember, ROAM, say, spot, upgrade_item = A.py, A.remember, A.ROAM, A.say, A.spot, A.upgrade_item
  end,
}
