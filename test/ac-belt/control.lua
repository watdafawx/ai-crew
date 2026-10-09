-- Headless check of belt immunity: the home chest sits in a field of running belts, and three long belt lines (with
-- iron on them) run between home and the only rock. "Rook mine 10 stone": he gets the stone and brings it home across
-- them. Then, told to stay while standing on a running belt, he isn't carried off.
local out = {}
local function log(s) out[#out + 1] = s helpers.write_file("ac-belt.txt", table.concat(out, "\n") .. "\n") end

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
    for _, x in ipairs({ 8, 10, 12 }) do
      for y = -30, 30 do
        local b = s.create_entity({ name = "transport-belt", position = { x + 0.5, y + 0.5 }, direction = defines.direction.south, force = f })
        b.get_transport_line(1).insert_at_back({ name = "iron-plate", count = 1 })
      end
    end
    for x = -5, 5 do for y = -5, 5 do
      if not (x == 0 and y == 0) then
        s.create_entity({ name = "transport-belt", position = { x + 0.5, y + 0.5 }, direction = defines.direction.east, force = f })
      end
    end end
    storage.rock = s.create_entity({ name = "big-rock", position = { 20.5, 0.5 } })
    storage.chest = s.create_entity({ name = "iron-chest", position = { 0.5, 0.5 }, force = f })
    remote.call("ai-crew", "hire", "Rook", "nauvis", { x = -8, y = 2 })
    remote.call("ai-crew", "order", nil, "Rook mine 10 stone")
  elseif t == 5000 then
    local st = remote.call("ai-crew", "status", "Rook")
    s.find_entities_filtered({ type = "character", position = st.position, radius = 0.3 })[1].teleport({ 10.5, 20.5 })
    remote.call("ai-crew", "order", nil, "Rook stay")
  elseif t == 6000 then
    local stone = storage.chest.get_item_count("stone")
    local st = remote.call("ai-crew", "status", "Rook")
    local checks = {
      { "mined the rock past the belts", not storage.rock.valid },
      { "brought the stone home across the belts (" .. stone .. ")", stone >= 10 },
      { string.format("standing on a running belt, not carried off (at %.1f, %.1f)", st.position.x, st.position.y),
        math.abs(st.position.x - 10.5) < 0.5 and math.abs(st.position.y - 20.5) < 0.5 },
    }
    local fails = 0
    for _, k in ipairs(checks) do log((k[2] and "PASS " or "FAIL ") .. k[1]) if not k[2] then fails = fails + 1 end end
    log(fails == 0 and "ALL PASS" or (fails .. " FAILED"))
  end
end)
