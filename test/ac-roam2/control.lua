-- Headless check of the roamers' work round the base: Rook roams round home (no player). An upgrade mark 54 tiles
-- out (past the work area round home) is carried out; with "Crew upgrade to better tiers" off for 2 minutes nothing
-- unmarked changes, then on: the assembler, inserter and furnace near home go up a tier from the chest (recipe and
-- direction kept). A yellow belt run (a 20-piece loop with an underground pair and a splitter, bricks going round)
-- stays yellow while the chest is one red belt short of it, then goes red as a whole once it isn't, the bricks still
-- going round; the long plates belt (too many for the chest) stays yellow. Gears run short (faked): he hand-crafts a
-- few from plates on a belt 28 tiles out (none in the chest) and brings them home. A character (standing in for the
-- player) is bitten: he comes to it, follows it when it moves, kills the biters, then roams on.
local out = {}
local function log(s) out[#out + 1] = s helpers.write_file("ac-roam2.txt", table.concat(out, "\n") .. "\n") end
local D = defines.direction

script.on_nth_tick(5, function(ev)
  if ev.tick ~= 5 then return end
  local s, f = game.surfaces.nauvis, game.forces.player
  s.always_day = true
  game.forces.enemy.set_evolution_factor(0, s)
  game.map_settings.enemy_expansion.enabled = false
  for _, e in pairs(s.find_entities_filtered({ area = { { -120, -120 }, { 120, 120 } } })) do e.destroy() end
  for _, e in pairs(s.find_entities_filtered({ force = "enemy", area = { { -400, -400 }, { 400, 400 } } })) do e.destroy() end
  local tiles = {}
  for x = -120, 120 do for y = -120, 120 do tiles[#tiles + 1] = { name = "lab-dark-1", position = { x, y } } end end
  s.set_tiles(tiles)
  local chest = s.create_entity({ name = "iron-chest", position = { 0.5, 0.5 }, force = f })
  for _, it in pairs({ { "submachine-gun", 1 }, { "firearm-magazine", 400 }, { "heavy-armor", 1 }, { "raw-fish", 20 },
    { "steel-furnace", 2 }, { "assembling-machine-2", 1 }, { "fast-inserter", 1 }, { "fast-transport-belt", 16 },
    { "fast-underground-belt", 2 }, { "fast-splitter", 1 } }) do
    chest.insert({ name = it[1], count = it[2] })
  end
  -- near home: things with a better tier in the chest (the assembler powered: no poles to run)
  s.create_entity({ name = "electric-energy-interface", position = { 8, -8 }, force = f })
  s.create_entity({ name = "small-electric-pole", position = { 10.5, -8.5 }, force = f })
  storage.am = s.create_entity({ name = "assembling-machine-1", position = { 12.5, -8.5 }, force = f, recipe = "iron-gear-wheel" })
  storage.ins = s.create_entity({ name = "inserter", position = { 15.5, -8.5 }, direction = D.west, force = f })
  storage.sf = s.create_entity({ name = "stone-furnace", position = { -10, 8 }, force = f })
  -- a yellow loop at (-17..-12, -15..-10), a feeder into the splitter's other side (nothing out of it): 17 belts,
  -- 2 undergrounds (west, under 2 tiles), a splitter. The chest one red belt short of it
  local ox, oy = -17, -15
  local function belt(x, y, d)
    s.create_entity({ name = "transport-belt", position = { ox + x + 0.5, oy + y + 0.5 }, direction = d, force = f })
  end
  for _, b in ipairs({ { 0, 0, D.east }, { 1, 0, D.east }, { 3, 0, D.east }, { 4, 0, D.east }, { 1, -1, D.east },
    { 0, -1, D.east }, { 5, 5, D.west }, { 0, 5, D.north } }) do belt(b[1], b[2], b[3]) end
  for y = 0, 4 do belt(5, y, D.south) end
  for y = 1, 4 do belt(0, y, D.north) end
  s.create_entity({ name = "splitter", position = { ox + 2.5, oy }, direction = D.east, force = f })
  storage.ugi = s.create_entity({ name = "underground-belt", position = { ox + 4.5, oy + 5.5 }, direction = D.west,
    type = "input", force = f })
  s.create_entity({ name = "underground-belt", position = { ox + 1.5, oy + 5.5 }, direction = D.west, type = "output",
    force = f })
  storage.loop = { { ox - 1, oy - 2 }, { ox + 7, oy + 7 } }
  storage.bricks0 = 0
  for _, b in pairs(s.find_entities_filtered({ name = "transport-belt", area = storage.loop })) do
    if b.position.y > oy + 1 then
      b.get_transport_line(1).insert_at_back({ name = "stone-brick", count = 1 })
      storage.bricks0 = storage.bricks0 + 1
    end
  end
  log("loop: " .. s.count_entities_filtered({ area = storage.loop }) .. " pieces, underground paired: "
    .. tostring(storage.ugi.neighbours ~= nil) .. ", bricks " .. storage.bricks0)
  -- far out: a furnace marked for upgrade
  storage.far = s.create_entity({ name = "stone-furnace", position = { 56, 2 }, force = f })
  storage.far.order_upgrade({ force = f, target = "steel-furnace" })
  -- plates going by on a belt 28 tiles out (not within 24 of home)
  storage.plates0 = 0
  for x = -30, 30 do
    local b = s.create_entity({ name = "transport-belt", position = { x + 0.5, 30.5 }, direction = D.east, force = f })
    for i = 1, 2 do b.get_transport_line(i).insert_at_back({ name = "iron-plate", count = 1 }) end
    storage.plates0 = storage.plates0 + 2
  end
  f.get_item_production_statistics(s).on_flow("iron-gear-wheel", -300) -- (300 gears used, none made)
  remote.call("ai-crew", "test_tiers", false)
  remote.call("ai-crew", "hire", "Rook", "nauvis", { x = 2, y = 2 })
  remote.call("ai-crew", "order", nil, "Rook roam")
end)

local function plates()
  local n = 0
  for _, b in pairs(game.surfaces.nauvis.find_entities_filtered({ name = "transport-belt", area = { { -40, 29 }, { 40, 32 } } })) do
    for i = 1, 2 do n = n + b.get_transport_line(i).get_item_count("iron-plate") end
  end
  return n
end

-- the bricks on the loop: how many, and where each is (unique id -> belt/lane/position)
local function bricks()
  local n, at = 0, {}
  for _, b in pairs(game.surfaces.nauvis.find_entities_filtered({ area = storage.loop })) do
    for i = 1, b.get_max_transport_line_index() do
      for _, it in pairs(b.get_transport_line(i).get_detailed_contents()) do
        n = n + it.stack.count
        at[it.unique_id] = b.unit_number .. "/" .. i .. "/" .. it.position
      end
    end
  end
  return n, at
end

-- the stand-in for the player: kept alive (healed) while bitten
script.on_nth_tick(10, function()
  local c = storage.char
  if c and c.valid then c.health = c.max_health end
end)

script.on_nth_tick(60, function(ev)
  if storage.done or not storage.plates0 then return end
  local s, f = game.surfaces.nauvis, game.forces.player
  local st = remote.call("ai-crew", "status", "Rook")
  local t = ev.tick
  if t == 7200 then -- tiers off so far: nothing unmarked touched
    storage.untouched = storage.am.valid and storage.ins.valid and storage.sf.valid
      and s.count_entities_filtered({ to_be_upgraded = true, area = { { -40, -40 }, { 40, 40 } } }) == 0
    remote.call("ai-crew", "test_tiers", true)
  end
  if t == 14400 then -- one red belt short of the loop: none of it touched; then the one more
    storage.short_kept = s.count_entities_filtered({ area = storage.loop, name = { "transport-belt", "underground-belt",
      "splitter" } }) == 20 and s.count_entities_filtered({ area = storage.loop, to_be_upgraded = true }) == 0
    local chest = s.find_entities_filtered({ name = "iron-chest", position = { 0.5, 0.5 } })[1]
    chest.insert({ name = "fast-transport-belt" })
  end
  if t == 15000 then f.get_item_production_statistics(s).on_flow("iron-gear-wheel", -300) end -- (still short)
  if t == 18000 then -- the "player" bitten 35 tiles out
    storage.char = s.create_entity({ name = "character", position = { -30, -25 }, force = f })
    remote.call("ai-crew", "test_char", storage.char)
    storage.biters = {}
    for i = 1, 5 do
      local u = s.create_entity({ name = "small-biter", position = { -40, -27 + i }, force = "enemy" })
      u.commandable.set_command({ type = defines.command.attack, target = storage.char, distraction = defines.distraction.none })
      storage.biters[i] = u
    end
  end
  if t == 18600 and storage.char.valid then storage.char.teleport({ -22, -18 }) end -- (it moves: they follow it)
  if st and st.doing and st.doing:find("^defend") then storage.defended = true end
  if storage.biters and not storage.cleared then
    local alive = 0
    for _, u in pairs(storage.biters) do if u.valid then alive = alive + 1 end end
    if alive == 0 then
      storage.cleared = t
      local c = storage.char.position
      storage.near = math.sqrt((st.position.x - c.x) ^ 2 + (st.position.y - c.y) ^ 2)
    end
  end
  if storage.cleared and t > storage.cleared + 900 and st and st.mode == "roam" and not st.doing then
    storage.after = storage.after or {}
    storage.after[math.floor(st.position.x / 8) .. "," .. math.floor(st.position.y / 8)] = true
  end
  if t % 1800 == 0 then
    log(string.format("t=%d Rook at %.0f,%.0f doing %s; far %s; am %s ins %s sf %s; plates %d; biters %s", t, st.position.x,
      st.position.y, tostring(st.doing), storage.far.valid and "stone" or "steel", tostring(storage.am.valid),
      tostring(storage.ins.valid), tostring(storage.sf.valid), plates(), storage.cleared and "dead" or "-"))
  end
  if t == 35940 then storage.at0 = select(2, bricks()) end
  if t < 36000 then return end
  local nb, at = bricks()
  local moved = 0
  for id, p in pairs(storage.at0 or {}) do if at[id] ~= p then moved = moved + 1 end end
  local ug = s.find_entities_filtered({ name = "fast-underground-belt", area = storage.loop })
  local ug_ok = #ug == 2
  for _, u in ipairs(ug) do
    ug_ok = ug_ok and u.direction == D.west and u.neighbours ~= nil
      and u.belt_to_ground_type == (u.position.x > -14 and "input" or "output")
  end
  local chest = s.find_entities_filtered({ name = "iron-chest", position = { 0.5, 0.5 } })[1].get_inventory(defines.inventory.chest)
  local am2 = s.find_entities_filtered({ name = "assembling-machine-2", position = { 12.5, -8.5 }, radius = 0.5 })[1]
  local fi = s.find_entities_filtered({ name = "fast-inserter", position = { 15.5, -8.5 }, radius = 0.5 })[1]
  local steel = s.count_entities_filtered({ name = "steel-furnace" })
  local recipe = am2 and am2.get_recipe()
  for _, m in ipairs(remote.call("ai-crew", "memory", nil) or {}) do log("memory: " .. m.text) end
  local gears = chest.get_item_count("iron-gear-wheel")
  local checks = {
    { "the far upgrade mark (54 tiles out) carried out", not storage.far.valid
      and s.count_entities_filtered({ name = "steel-furnace", position = { 56, 2 }, radius = 1 }) == 1 },
    { "tiers off: nothing unmarked upgraded", storage.untouched == true },
    { "assembler up a tier, recipe kept", am2 ~= nil and recipe ~= nil and recipe.name == "iron-gear-wheel" },
    { "inserter up a tier, direction kept", fi ~= nil and fi.direction == D.west },
    { "furnace up a tier", not storage.sf.valid and steel == 2 },
    { "belt run one red belt short: left yellow", storage.short_kept == true },
    { "belt run in stock: all 20 pieces red", s.count_entities_filtered({ area = storage.loop, name = {
      "fast-transport-belt", "fast-underground-belt", "fast-splitter" } }) == 20
      and s.count_entities_filtered({ area = storage.loop, name = { "transport-belt", "underground-belt", "splitter" } })
      == 0 and chest.get_item_count("fast-transport-belt") == 0 },
    { "undergrounds kept their ends, paired", ug_ok },
    -- (a few come off with the pieces swapped, into his pockets as for a player: brought home)
    { string.format("bricks all still going round (%d of %d, %d moved; %d brought home)", nb, storage.bricks0, moved,
      chest.get_item_count("stone-brick")), nb == storage.bricks0 and moved > 0 },
    { "the long plates belt (61, more than in stock) left yellow",
      s.count_entities_filtered({ name = "transport-belt", area = { { -40, 29 }, { 40, 32 } } }) == 61 },
    { "nothing left marked", s.count_entities_filtered({ to_be_upgraded = true }) == 0 },
    { "gears hand-crafted from belt plates and brought home (" .. gears .. ")", gears >= 5 and plates() <= storage.plates0 - 5 },
    { "came to the bitten character (defend)", storage.defended == true },
    { string.format("killed the biters by it (%.0f tiles off)", storage.near or -1), storage.cleared ~= nil and (storage.near or 99) <= 24 },
    { "roamed on after", storage.after ~= nil and table_size(storage.after) >= 2 },
  }
  local fails = 0
  for _, k in ipairs(checks) do log((k[2] and "PASS " or "FAIL ") .. k[1]) if not k[2] then fails = fails + 1 end end
  log(fails == 0 and "ALL PASS" or (fails .. " FAILED"))
  storage.done = true
end)
