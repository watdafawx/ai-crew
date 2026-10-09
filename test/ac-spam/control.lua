-- Headless check against chat spam: three crew, no gun anywhere, shotgun shells and plates in the chest but no wood
-- anywhere (a shotgun needs some). They used to start a shotgun, find it short of wood, say so, and start again twice
-- a second, each of them. Over 2 minutes each may say only a few lines, and the same news once for the crew.
local out = {}
local function log(s) out[#out + 1] = s helpers.write_file("ac-spam.txt", table.concat(out, "\n") .. "\n") end
local NAMES = { "Rook", "Mara", "Juno" }

script.on_event(defines.events.on_tick, function(ev)
  local t = ev.tick
  local s, f = game.surfaces.nauvis, game.forces.player
  if t == 5 then
    s.always_day = true
    game.map_settings.enemy_expansion.enabled = false
    for _, e in pairs(s.find_entities_filtered({ area = { { -200, -200 }, { 200, 200 } } })) do e.destroy() end
    for _, e in pairs(s.find_entities_filtered({ force = "enemy", area = { { -400, -400 }, { 400, 400 } } })) do e.destroy() end
    local tiles = {}
    for x = -150, 150 do for y = -150, 150 do tiles[#tiles + 1] = { name = "lab-dark-1", position = { x, y } } end end
    s.set_tiles(tiles)
    for _, r in ipairs({ "shotgun", "shotgun-shell" }) do f.recipes[r].enabled = true end
    local chest = s.create_entity({ name = "iron-chest", position = { 0.5, 0.5 }, force = f })
    for _, it in ipairs({ { "shotgun-shell", 20 }, { "iron-plate", 200 }, { "copper-plate", 200 }, { "iron-gear-wheel", 20 } }) do
      chest.insert({ name = it[1], count = it[2] })
    end
    for i, n in ipairs(NAMES) do remote.call("ai-crew", "hire", n, "nauvis", { x = i * 2, y = 2 }) end
  elseif t == 7200 then
    local fails, total = 0, 0
    for _, n in ipairs(NAMES) do
      local st = remote.call("ai-crew", "status", n)
      local lines = st.lines
      for _, l in ipairs(st.last_lines or {}) do log("  " .. n .. " " .. l) end
      total = total + lines
      local ok = lines <= 3
      log((ok and "PASS " or "FAIL ") .. n .. " said " .. lines .. " lines in 2 minutes")
      if not ok then fails = fails + 1 end
    end
    local ok = total <= 6
    log((ok and "PASS " or "FAIL ") .. "the crew said " .. total .. " lines in all (the same news once)")
    if not ok then fails = fails + 1 end
    log(fails == 0 and "ALL PASS" or (fails .. " FAILED"))
  end
end)
