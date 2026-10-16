-- Headless check that the crew fetch what the base makes instead of building furnaces for it: stone, coal and ore at
-- home (enough for a furnace and to smelt), and the base's production statistics say it made iron plates, copper
-- plates and stone bricks. "get 20 iron plate": fetched from a belt 105-135 tiles out (past the old 80). "get 20 copper
-- plate": taken from a furnace's output 130 tiles out. "get 10 stone brick": none anywhere, still no furnace built.
local out, checks = {}, {}
local function log(s) out[#out + 1] = s helpers.write_file("ac-fetch.txt", table.concat(out, "\n") .. "\n") end
local function check(name, ok) checks[#checks + 1] = { name, ok and true or false } end
local function furnaces() -- (near home: the far one is the base's)
  return game.surfaces.nauvis.count_entities_filtered({ type = "furnace", position = { 0, 0 }, radius = 80 })
end
local function belt_plates()
  local n = 0
  for _, b in pairs(storage.belts) do n = n + b.get_item_count("iron-plate") end
  return n
end

script.on_event(defines.events.on_tick, function(ev)
  local t = ev.tick
  local s, f = game.surfaces.nauvis, game.forces.player
  if t == 5 then
    s.always_day = true
    game.map_settings.enemy_expansion.enabled = false
    for _, e in pairs(s.find_entities_filtered({ area = { { -150, -150 }, { 150, 150 } } })) do e.destroy() end
    for _, e in pairs(s.find_entities_filtered({ force = "enemy", area = { { -400, -400 }, { 400, 400 } } })) do e.destroy() end
    for _, e in pairs(s.find_entities_filtered({ type = { "resource", "fish" }, area = { { -400, -400 }, { 400, 400 } } })) do
      e.destroy()
    end
    local tiles = {}
    for x = -150, 150 do for y = -100, 100 do tiles[#tiles + 1] = { name = "lab-dark-1", position = { x, y } } end end
    s.set_tiles(tiles)
    for x = 12, 15 do for y = -2, 1 do
      s.create_entity({ name = "iron-ore", position = { x + 0.5, y + 0.5 }, amount = 500 })
      s.create_entity({ name = "copper-ore", position = { x + 0.5, y + 8.5 }, amount = 500 })
    end end
    storage.home = s.create_entity({ name = "iron-chest", position = { 0.5, 0.5 }, force = f })
    for _, it in ipairs({ { "stone", 50 }, { "coal", 50 }, { "raw-fish", 20 } }) do storage.home.insert({ name = it[1], count = it[2] }) end
    storage.belts = {}
    for x = 105, 134 do -- (a plate a lane: insert_at_back takes one onto a still belt)
      local b = s.create_entity({ name = "transport-belt", position = { x + 0.5, 0.5 }, direction = defines.direction.east, force = f })
      storage.belts[#storage.belts + 1] = b
      for lane = 1, 2 do for _ = 1, 3 do b.get_transport_line(lane).insert_at_back({ name = "iron-plate", count = 1 }) end end
    end
    storage.furnace = s.create_entity({ name = "stone-furnace", position = { 130, 0 }, force = f })
    storage.furnace.get_inventory(defines.inventory.furnace_result).insert({ name = "copper-plate", count = 40 })
    local stats = f.get_item_production_statistics(s)
    for _, it in ipairs({ "iron-plate", "copper-plate", "stone-brick" }) do stats.on_flow(it, 500) end
    remote.call("ai-crew", "hire", "Rook", "nauvis", { x = 2, y = 2 })
  elseif t == 60 then
    storage.belt0 = belt_plates()
    log("t=60: " .. storage.belt0 .. " iron plates on the far belt")
    remote.call("ai-crew", "order", nil, "Rook get 20 iron plate")
  elseif t == 3000 then
    local home, belt = storage.home.get_item_count("iron-plate"), belt_plates()
    local carried = 0
    for _, c in pairs(s.find_entities_filtered({ type = "character" })) do carried = carried + c.get_item_count("iron-plate") end
    log(string.format("t=3000: home %d iron plates, belt %d, carried %d, furnaces %d", home, belt, carried, furnaces()))
    check("fetched iron plates from the belt 105+ out (" .. (storage.belt0 - belt) .. " taken)", storage.belt0 - belt >= 20 and home + carried >= 20)
    check("built no furnace for iron plates", furnaces() == 0)
    remote.call("ai-crew", "order", nil, "Rook get 20 copper plate")
  elseif t == 6000 then
    local home = storage.home.get_item_count("copper-plate")
    local left = storage.furnace.get_inventory(defines.inventory.furnace_result).get_item_count("copper-plate")
    log(string.format("t=6000: home %d copper plates, far furnace %d, furnaces %d", home, left, furnaces()))
    check("took copper plates from the furnace 130 out (" .. (40 - left) .. " taken)", left <= 20 and home >= 20)
    check("built no furnace for copper plates", furnaces() == 0)
    remote.call("ai-crew", "order", nil, "Rook get 10 stone brick")
  elseif t == 9000 then
    local st = remote.call("ai-crew", "status", "Rook")
    local said = false
    for _, l in ipairs(st.last_lines or {}) do
      log("  " .. l)
      if l:find("won't build", 1, true) then said = true end
    end
    log(string.format("t=9000: furnaces %d, bricks at home %d", furnaces(), storage.home.get_item_count("stone-brick")))
    check("the base makes bricks, none to fetch: no furnace built", furnaces() == 0)
    check("said why", said)
    local fails = 0
    for _, c in ipairs(checks) do log((c[2] and "PASS " or "FAIL ") .. c[1]) if not c[2] then fails = fails + 1 end end
    log(fails == 0 and "ALL PASS" or (fails .. " FAILED"))
  end
end)
