-- Headless check of the jetpack: the only rock is inside a closed ring of walls. "Rook mine 10 stone": no way in on
-- foot, so he flies in, mines it, and flies out to bring the stone home.
local out = {}
local function log(s) out[#out + 1] = s helpers.write_file("ac-jet.txt", table.concat(out, "\n") .. "\n") end

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
    for x = 14, 26 do for y = -6, 6 do
      if x == 14 or x == 26 or y == -6 or y == 6 then s.create_entity({ name = "stone-wall", position = { x + 0.5, y + 0.5 }, force = f }) end
    end end
    storage.rock = s.create_entity({ name = "big-rock", position = { 20.5, 0.5 } })
    storage.chest = s.create_entity({ name = "iron-chest", position = { 0.5, 0.5 }, force = f })
    remote.call("ai-crew", "hire", "Rook", "nauvis", { x = 2, y = 2 })
    remote.call("ai-crew", "order", nil, "Rook mine 10 stone")
  elseif t == 6000 then
    local st = remote.call("ai-crew", "status", "Rook")
    local stone = storage.chest.get_item_count("stone")
    local checks = {
      { "mined the walled-in rock", not storage.rock.valid },
      { "brought the stone home (" .. stone .. ")", stone >= 10 },
      { "flew in and out (" .. st.flights .. " flights)", st.flights >= 2 },
      { "back outside the walls", st.position.x < 13 or st.position.x > 27 or math.abs(st.position.y) > 7 },
    }
    local fails = 0
    for _, k in ipairs(checks) do log((k[2] and "PASS " or "FAIL ") .. k[1]) if not k[2] then fails = fails + 1 end end
    log(fails == 0 and "ALL PASS" or (fails .. " FAILED"))
  end
end)
