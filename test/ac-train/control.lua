-- Headless check of riding a train: a straight track 120 tiles long with a stop "Home" by home and "Far" at the far
-- end, a two-headed train running between them, the only rock by Far. "Rook mine 10 stone": he gets on while it
-- stands at Home, rides to Far, gets off, mines the rock and brings the stone home (on foot or by train).
local out = {}
local function log(s) out[#out + 1] = s helpers.write_file("ac-train.txt", table.concat(out, "\n") .. "\n") end
local D = defines.direction

script.on_event(defines.events.on_tick, function(ev)
  local t = ev.tick
  local s, f = game.surfaces.nauvis, game.forces.player
  if t == 5 then
    s.always_day = true
    game.map_settings.enemy_expansion.enabled = false
    for _, e in pairs(s.find_entities_filtered({ area = { { -150, -150 }, { 280, 150 } } })) do e.destroy() end
    for _, e in pairs(s.find_entities_filtered({ force = "enemy", area = { { -400, -400 }, { 400, 400 } } })) do e.destroy() end
    local tiles = {}
    for x = -150, 280 do for y = -150, 150 do tiles[#tiles + 1] = { name = "lab-dark-1", position = { x, y } } end end
    s.set_tiles(tiles)
    for x = -31, 161, 2 do s.create_entity({ name = "straight-rail", position = { x, 21 }, direction = D.east, force = f }) end
    local stops = {}
    for _, st in ipairs({ { "Home", 0 }, { "Far", 120 } }) do
      local a = s.create_entity({ name = "train-stop", position = { st[2] + 1, 23 }, direction = D.east, force = f })
      local b = s.create_entity({ name = "train-stop", position = { st[2] - 1, 19 }, direction = D.west, force = f })
      for _, x in ipairs({ a or false, b or false }) do if x then x.backer_name = st[1] stops[#stops + 1] = x end end
    end
    log("stops made: " .. #stops)
    local l1 = s.create_entity({ name = "locomotive", position = { -4, 21 }, direction = D.east, force = f })
    local w = l1 and s.create_entity({ name = "cargo-wagon", position = { -11, 21 }, direction = D.east, force = f })
    local l2 = w and s.create_entity({ name = "locomotive", position = { -18, 21 }, direction = D.west, force = f })
    if l2 then l2.connect_rolling_stock(defines.rail_direction.back) l2.connect_rolling_stock(defines.rail_direction.front) end
    log("train made: " .. tostring(l1 ~= nil) .. " " .. tostring(w ~= nil) .. " " .. tostring(l2 ~= nil))
    for _, l in ipairs({ l1, l2 }) do if l then l.get_fuel_inventory().insert({ name = "coal", count = 50 }) end end
    storage.train = l1 and l1.train
    if storage.train then
      log("carriages: " .. #storage.train.carriages)
      local wait = { { type = "time", ticks = 900, compare_type = "or" } }
      storage.train.schedule = { current = 1, records = { { station = "Home", wait_conditions = wait }, { station = "Far", wait_conditions = wait } } }
      storage.train.manual_mode = false
    end
    storage.rock = s.create_entity({ name = "big-rock", position = { 124.5, 32.5 } })
    storage.chest = s.create_entity({ name = "iron-chest", position = { 4.5, 12.5 }, force = f })
    remote.call("ai-crew", "hire", "Rook", "nauvis", { x = 4, y = 10 })
  elseif storage.train and not storage.ordered and t % 10 == 0 and storage.train.valid and storage.train.station
    and storage.train.station.backer_name == "Home" then
    storage.ordered = t
    log("train standing at Home at t=" .. t .. "; order given")
    remote.call("ai-crew", "order", nil, "Rook mine 10 stone")
  elseif storage.ordered and t < 9000 then
    if t % 600 == 0 then
      local st0 = remote.call("ai-crew", "status", "Rook")
      local tr = storage.train
      log(string.format("t=%d Rook at %.0f,%.0f doing %s riding %s; train %s at %s, %d carriages", t, st0.position.x, st0.position.y,
        tostring(st0.doing), tostring(st0.riding), tostring(tr.valid and tr.state), tostring(tr.valid and tr.station and tr.station.backer_name),
        tr.valid and #tr.carriages or 0))
    end
    local st = remote.call("ai-crew", "status", "Rook")
    if st and st.riding and not storage.rode then storage.rode = st.riding log("riding a " .. st.riding .. " at t=" .. t) end
    if st and storage.rode and not st.riding and not storage.off then -- (where they are the tick after getting off)
      storage.off_at = storage.off_at or t
    end
    if storage.off_at and t == storage.off_at + 2 then
      storage.off = st.position
      log(string.format("got off at %.0f,%.0f at t=%d", st.position.x, st.position.y, t))
    end
  elseif t == 9000 then
    local st = remote.call("ai-crew", "status", "Rook")
    local stone = storage.chest.get_item_count("stone")
    local checks = {
      { "rode the train to the far stop (" .. tostring(storage.rode) .. ")", storage.off and storage.off.x > 100 },
      { "mined the rock by the far stop", not storage.rock.valid },
      { "brought the stone home (" .. stone .. ")", stone >= 10 },
    }
    log(string.format("Rook at %.0f,%.0f, rides %d", st.position.x, st.position.y, st.rides))
    local fails = 0
    for _, k in ipairs(checks) do log((k[2] and "PASS " or "FAIL ") .. k[1]) if not k[2] then fails = fails + 1 end end
    log(fails == 0 and "ALL PASS" or (fails .. " FAILED"))
  end
end)
