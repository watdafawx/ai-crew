-- Headless check of belts and bots: the only iron plates are going round a belt loop near home, so "Rook craft 10
-- gears" takes them off the belt instead of giving up. Then, told to stay on a ghost that a roboport's construction
-- robots can build, he steps off it and the robots build it.
local out = {}
local function log(s) out[#out + 1] = s helpers.write_file("ac-bots.txt", table.concat(out, "\n") .. "\n") end

local function belt_plates(s)
  local n = 0
  for _, b in pairs(s.find_entities_filtered({ type = "transport-belt" })) do
    for i = 1, 2 do n = n + b.get_transport_line(i).get_item_count("iron-plate") end
  end
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
    local tiles = {}
    for x = -150, 150 do for y = -150, 150 do tiles[#tiles + 1] = { name = "lab-dark-1", position = { x, y } } end end
    s.set_tiles(tiles)
    -- a belt loop at x -4..4, y 6..8 with iron plates on it
    local D = defines.direction
    for x = -4, 4 do
      s.create_entity({ name = "transport-belt", position = { x + 0.5, 6.5 }, direction = x == 4 and D.south or D.east, force = f })
      s.create_entity({ name = "transport-belt", position = { x + 0.5, 8.5 }, direction = x == -4 and D.north or D.west, force = f })
    end
    s.create_entity({ name = "transport-belt", position = { 4.5, 7.5 }, direction = D.south, force = f })
    s.create_entity({ name = "transport-belt", position = { -3.5, 7.5 }, direction = D.north, force = f })
    for _, b in pairs(s.find_entities_filtered({ type = "transport-belt" })) do
      for i = 1, 2 do b.get_transport_line(i).insert_at_back({ name = "iron-plate", count = 1 }) end
    end
    storage.plates = belt_plates(s)
    storage.chest = s.create_entity({ name = "iron-chest", position = { -10.5, 0.5 }, force = f })
    -- a powered roboport far from home, with robots and a wooden chest to build
    s.create_entity({ name = "electric-energy-interface", position = { 40, -6 }, force = f })
    s.create_entity({ name = "medium-electric-pole", position = { 42.5, -5.5 }, force = f })
    local rp = s.create_entity({ name = "roboport", position = { 45, -4 }, force = f })
    rp.insert({ name = "construction-robot", count = 10 })
    s.create_entity({ name = "storage-chest", position = { 48.5, -6.5 }, force = f }).insert({ name = "wooden-chest", count = 5 })
    remote.call("ai-crew", "hire", "Rook", "nauvis", { x = -8, y = 2 })
    remote.call("ai-crew", "order", nil, "Rook craft 10 gears")
  elseif t == 2400 then
    storage.gears = storage.chest.get_item_count("iron-gear-wheel")
    storage.left = belt_plates(s)
    remote.call("ai-crew", "order", nil, "Rook stay")
  elseif t == 2460 then
    local st = remote.call("ai-crew", "status", "Rook")
    s.find_entities_filtered({ type = "character", position = st.position, radius = 0.3 })[1].teleport({ 50.5, 2.5 })
    s.create_entity({ name = "entity-ghost", inner_name = "wooden-chest", position = { 50.5, 2.5 }, force = f })
  elseif t == 3600 then
    local built = s.find_entity("wooden-chest", { 50.5, 2.5 })
    local checks = {
      { "made 10 gears from belt plates (" .. storage.gears .. " in the chest)", storage.gears >= 10 },
      { "took the plates off the belt (" .. storage.plates .. " -> " .. storage.left .. ")", storage.left <= storage.plates - 20 },
      { "stepped off the ghost and the robots built it", built ~= nil },
    }
    local fails = 0
    for _, k in ipairs(checks) do log((k[2] and "PASS " or "FAIL ") .. k[1]) if not k[2] then fails = fails + 1 end end
    log(fails == 0 and "ALL PASS" or (fails .. " FAILED"))
  end
end)
