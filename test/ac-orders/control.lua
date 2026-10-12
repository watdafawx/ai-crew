-- Headless check of "Back where they stood after orders": Rook stands 40 tiles west of home (the chest, fish in it);
-- the only stone is a patch 40 tiles east of home. "Rook mine 10 stone" with the setting on: it mines, brings the
-- stone home, then goes back to where it stood. The same order with it off: it stays at home, where the work ended.
local out, checks = {}, {}
local function log(s) out[#out + 1] = s helpers.write_file("ac-orders.txt", table.concat(out, "\n") .. "\n") end
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
    -- (no stone, trees or fish but ours: the map round the test area is random)
    local junk = { "resource", "tree", "fish" }
    for _, e in pairs(s.find_entities_filtered({ type = junk, area = { { -400, -400 }, { 400, 400 } } })) do
      e.destroy()
    end
    local tiles = {}
    for x = -150, 150 do for y = -100, 100 do tiles[#tiles + 1] = { name = "lab-dark-1", position = { x, y } } end end
    s.set_tiles(tiles)
    for x = 40, 42 do for y = -1, 1 do s.create_entity({ name = "stone", position = { x + 0.5, y + 0.5 }, amount = 100 }) end end
    storage.chest = s.create_entity({ name = "iron-chest", position = { 0.5, 0.5 }, force = f })
    storage.chest.insert({ name = "raw-fish", count = 20 }) -- (no fishing trips)
    remote.call("ai-crew", "hire", "Rook", "nauvis", { x = 2, y = 2 })
  elseif t == 10 then
    local st = remote.call("ai-crew", "status", "Rook")
    s.find_entities_filtered({ type = "character", position = st.position, radius = 0.3 })[1].teleport(STOOD)
    remote.call("ai-crew", "order", nil, "Rook stay")
    remote.call("ai-crew", "test_back_after_orders", true)
    remote.call("ai-crew", "order", nil, "Rook mine 10 stone")
  elseif t > 10 and t % 30 == 0 then
    local st = remote.call("ai-crew", "status", "Rook")
    local p = st.position
    local d = math.sqrt((p.x - STOOD.x) ^ 2 + (p.y - STOOD.y) ^ 2)
    if not storage.left and d > 60 then storage.left = t log("on: off to the stone at t=" .. t) end
    if storage.left and not storage.back and st.jobs == 0 and d < 4 then
      storage.back = t
      log("on: back where it stood at t=" .. t)
      remote.call("ai-crew", "test_back_after_orders", false)
      remote.call("ai-crew", "order", nil, "Rook mine 10 stone")
    end
    if storage.back and not storage.left2 and d > 60 then storage.left2 = t log("off: off to the stone at t=" .. t) end
    if storage.left2 and st.jobs == 0 then
      storage.idle2 = storage.idle2 or t
    else
      storage.idle2 = nil
    end
    if t == 6000 then
      check("on: went off for the stone (at t=" .. tostring(storage.left) .. ")", storage.left ~= nil)
      check("on: came back where it stood (at t=" .. tostring(storage.back) .. ")", storage.back ~= nil)
      check("off: went off for the stone (at t=" .. tostring(storage.left2) .. ")", storage.left2 ~= nil)
      check(string.format("off: done, stayed where the work ended (idle since t=%s, %.0f tiles from where it stood)",
        tostring(storage.idle2), d), storage.idle2 and t - storage.idle2 >= 600 and d > 16)
      local fails = 0
      for _, k in ipairs(checks) do log((k[2] and "PASS " or "FAIL ") .. k[1]) if not k[2] then fails = fails + 1 end end
      log(fails == 0 and "ALL PASS" or (fails .. " FAILED"))
    end
  end
end)
