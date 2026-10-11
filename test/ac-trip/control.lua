-- Headless check of coming back from a trip: Rook stands 40 tiles west of home, where the chest is (fish in it, no
-- fuel). A stone furnace by the chest has none either, and the only coal is a patch 60 tiles east. Rook goes and mines
-- some, brings it home, fuels the furnace, and then goes back to where it stood. Hurt there with no fish to eat, it
-- falls back home, heals, and comes back again.
local out, checks = {}, {}
local function log(s) out[#out + 1] = s helpers.write_file("ac-trip.txt", table.concat(out, "\n") .. "\n") end
local function check(name, ok) checks[#checks + 1] = { name, ok and true or false } end
local STOOD = { x = -40, y = 0 }

script.on_event(defines.events.on_tick, function(ev)
  local t = ev.tick
  local s, f = game.surfaces.nauvis, game.forces.player
  if t == 5 then
    s.always_day = true
    game.map_settings.enemy_expansion.enabled = false
    for _, e in pairs(s.find_entities_filtered({ area = { { -150, -150 }, { 150, 150 } } })) do e.destroy() end
    for _, e in pairs(s.find_entities_filtered({ force = "enemy", area = { { -400, -400 }, { 400, 400 } } })) do e.destroy() end
    -- (no coal or trees but ours: the map round the test area is random)
    for _, e in pairs(s.find_entities_filtered({ type = { "resource", "tree" }, area = { { -400, -400 }, { 400, 400 } } })) do
      e.destroy()
    end
    local tiles = {}
    for x = -150, 150 do for y = -100, 100 do tiles[#tiles + 1] = { name = "lab-dark-1", position = { x, y } } end end
    s.set_tiles(tiles)
    for x = 60, 62 do for y = -1, 1 do s.create_entity({ name = "coal", position = { x + 0.5, y + 0.5 }, amount = 100 }) end end
    storage.chest = s.create_entity({ name = "iron-chest", position = { 0.5, 0.5 }, force = f })
    storage.chest.insert({ name = "raw-fish", count = 20 }) -- (no fishing trips)
    remote.call("ai-crew", "hire", "Rook", "nauvis", { x = 2, y = 2 })
  elseif t == 10 then
    local st = remote.call("ai-crew", "status", "Rook")
    s.find_entities_filtered({ type = "character", position = st.position, radius = 0.3 })[1].teleport(STOOD)
    remote.call("ai-crew", "hear", nil, "Rook stay")
    storage.furnace = s.create_entity({ name = "stone-furnace", position = { 1, 6 }, force = f }) -- (after the order: an
    -- order forgets where a trip started)
  elseif t > 10 and t % 30 == 0 then
    local p = remote.call("ai-crew", "status", "Rook").position
    local d = math.sqrt((p.x - STOOD.x) ^ 2 + (p.y - STOOD.y) ^ 2)
    if d > 40 then storage.left = storage.left or t end
    if storage.left and not storage.fuelled and storage.furnace.get_fuel_inventory().get_item_count("coal") >= 3 then
      storage.fuelled = t
      log("furnace fuelled at t=" .. t)
    end
    if storage.fuelled and not storage.back and d < 4 then
      storage.back = t
      log("back where it stood at t=" .. t)
      -- then hurt, with no fish anywhere: it falls back home, heals, and comes back again
      for _, e in pairs(s.find_entities_filtered({ type = "fish", area = { { -400, -400 }, { 400, 400 } } })) do e.destroy() end
      storage.chest.clear_items_inside()
      local rook = s.find_entities_filtered({ type = "character", position = p, radius = 0.3 })[1]
      rook.get_main_inventory().remove({ name = "raw-fish", count = 1000 })
      rook.health = rook.max_health * 0.3
      storage.hurt = t
    end
    if storage.hurt and not storage.fell_back and remote.call("ai-crew", "status", "Rook").retreat and d > 30 then
      storage.fell_back = t
      log("fell back hurt at t=" .. t)
    end
    if storage.fell_back and not storage.back2 and d < 4 then storage.back2 = t log("back again at t=" .. t) end
    if t == 7200 then
      check("went off for coal (left at t=" .. tostring(storage.left) .. ")", storage.left ~= nil)
      check("fuelled the furnace (at t=" .. tostring(storage.fuelled) .. ")", storage.fuelled ~= nil)
      check(string.format("came back where it stood (at t=%s)", tostring(storage.back)), storage.back ~= nil)
      check("hurt, fell back home (at t=" .. tostring(storage.fell_back) .. ")", storage.fell_back ~= nil)
      check(string.format("healed, came back again (at t=%s, %.0f tiles from it)", tostring(storage.back2), d), storage.back2 ~= nil)
      local fails = 0
      for _, k in ipairs(checks) do log((k[2] and "PASS " or "FAIL ") .. k[1]) if not k[2] then fails = fails + 1 end end
      log(fails == 0 and "ALL PASS" or (fails .. " FAILED"))
    end
  end
end)
