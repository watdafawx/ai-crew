-- Headless check of Roam: Rook is told to roam (no player: round home). He must wander (many places, never far off),
-- find an assembler standing dark 25 tiles out and run poles to it from the powered pole, and find a worm, arm
-- himself from the chest at home and kill it. What he found goes into the crew's memory.
local out = {}
local function log(s) out[#out + 1] = s helpers.write_file("ac-roam.txt", table.concat(out, "\n") .. "\n") end

script.on_nth_tick(5, function(ev)
  if ev.tick ~= 5 then return end
  local s, f = game.surfaces.nauvis, game.forces.player
  s.always_day = true
  game.forces.enemy.set_evolution_factor(0, s)
  game.map_settings.enemy_expansion.enabled = false
  for _, e in pairs(s.find_entities_filtered({ area = { { -100, -100 }, { 100, 100 } } })) do e.destroy() end
  for _, e in pairs(s.find_entities_filtered({ force = "enemy", area = { { -400, -400 }, { 400, 400 } } })) do e.destroy() end
  local tiles = {}
  for x = -100, 100 do for y = -100, 100 do tiles[#tiles + 1] = { name = "lab-dark-1", position = { x, y } } end end
  s.set_tiles(tiles)
  local chest = s.create_entity({ name = "iron-chest", position = { 0.5, 0.5 }, force = f })
  chest.insert({ name = "submachine-gun", count = 1 })
  chest.insert({ name = "firearm-magazine", count = 400 })
  chest.insert({ name = "heavy-armor", count = 1 })
  chest.insert({ name = "raw-fish", count = 20 })
  chest.insert({ name = "small-electric-pole", count = 20 })
  s.create_entity({ name = "electric-energy-interface", position = { 10, 0 }, force = f })
  s.create_entity({ name = "small-electric-pole", position = { 12.5, 0.5 }, force = f })
  storage.asm = s.create_entity({ name = "assembling-machine-1", position = { 27.5, 0.5 }, force = f, recipe = "iron-gear-wheel" })
  storage.worm = s.create_entity({ name = "small-worm-turret", position = { -24, -20 }, force = "enemy" })
  remote.call("ai-crew", "hire", "Rook", "nauvis", { x = 2, y = 2 })
  remote.call("ai-crew", "order", nil, "Rook roam")
  storage.cells, storage.far = {}, 0
end)

script.on_nth_tick(60, function(ev)
  if storage.done or not storage.cells then return end
  local st = remote.call("ai-crew", "status", "Rook")
  if st then
    local p = st.position
    storage.cells[math.floor(p.x / 8) .. "," .. math.floor(p.y / 8)] = true
    storage.far = math.max(storage.far, math.sqrt((p.x - 2) ^ 2 + (p.y - 2) ^ 2))
  end
  if ev.tick % 1800 == 0 then
    log(string.format("t=%d Rook %s at %s doing %s; asm %s; worm %s", ev.tick, st and "up" or "down",
      st and string.format("%.0f,%.0f", st.position.x, st.position.y) or "-", st and tostring(st.doing) or "-",
      storage.asm.valid and storage.asm.status == defines.entity_status.no_power and "dark" or "powered",
      storage.worm.valid and "alive" or "dead"))
  end
  if ev.tick < 36000 then return end
  local memory = remote.call("ai-crew", "memory", nil) or {}
  local found = 0
  for _, m in ipairs(memory) do
    log("memory: " .. m.text)
    if m.text:find("found") then found = found + 1 end
  end
  local cells = table_size(storage.cells)
  local checks = {
    { "wandered: " .. cells .. " places", cells >= 8 },
    { string.format("stayed near home (farthest %.0f tiles)", storage.far), storage.far <= 60 },
    { "ran poles to the dark assembler", storage.asm.valid and storage.asm.status ~= defines.entity_status.no_power },
    { "found the worm and killed it", not storage.worm.valid },
    { "remembers what it found (" .. found .. ")", found >= 1 }, -- (the worm may pick the fight first: then it was never "found")
  }
  local fails = 0
  for _, k in ipairs(checks) do log((k[2] and "PASS " or "FAIL ") .. k[1]) if not k[2] then fails = fails + 1 end end
  log(fails == 0 and "ALL PASS" or (fails .. " FAILED"))
  storage.done = true
end)
