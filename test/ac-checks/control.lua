-- Headless check of "Crew check machines" and "Crew ping places": Rook roams round home with both off. He walks past
-- an assembler standing dark (no poles run to it, no word of it) and his line about a nest has no map pin. Both on:
-- he runs the poles, and his line about a second nest ends in a [gps] pin.
local out = {}
local function log(s) out[#out + 1] = s helpers.write_file("ac-checks.txt", table.concat(out, "\n") .. "\n") end

local function nest_lines()
  local st = remote.call("ai-crew", "status", "Rook")
  local found = {}
  for _, l in ipairs(st and st.last_lines or {}) do
    if l:lower():find("spawner") or l:lower():find("nest") then found[#found + 1] = l end
  end
  return found
end

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
  chest.insert({ name = "small-electric-pole", count = 20 })
  s.create_entity({ name = "electric-energy-interface", position = { 10, 0 }, force = f })
  s.create_entity({ name = "small-electric-pole", position = { 12.5, 0.5 }, force = f })
  storage.asm = s.create_entity({ name = "assembling-machine-1", position = { 27.5, 0.5 }, force = f, recipe = "iron-gear-wheel" })
  local n = s.create_entity({ name = "biter-spawner", position = { -20, -16 }, force = "enemy" })
  n.active = false
  remote.call("ai-crew", "test_checks", false)
  remote.call("ai-crew", "test_pings", false)
  remote.call("ai-crew", "hire", "Rook", "nauvis", { x = 2, y = 2 })
  remote.call("ai-crew", "order", nil, "Rook roam")
  storage.phase = "off"
end)

script.on_nth_tick(600, function(ev)
  if storage.done or not storage.phase then return end
  local dark = storage.asm.status == defines.entity_status.no_power
  log(string.format("t=%d %s: asm %s, nest lines %d", ev.tick, storage.phase, dark and "dark" or "powered", #nest_lines()))
  if storage.phase == "off" and ev.tick >= 12000 then
    local lines = nest_lines()
    storage.off_dark = dark
    storage.off_said = #lines > 0
    storage.off_nopin = #lines > 0
    for _, l in ipairs(lines) do log("off: " .. l) if l:find("[gps=", 1, true) then storage.off_nopin = false end end
    storage.off_quiet = true
    for _, m in ipairs(remote.call("ai-crew", "memory", nil) or {}) do
      if m.text:find("assembling") then storage.off_quiet = false end
    end
    remote.call("ai-crew", "test_checks", true)
    remote.call("ai-crew", "test_pings", true)
    local n = game.surfaces.nauvis.create_entity({ name = "biter-spawner", position = { -16, 24 }, force = "enemy" })
    n.active = false
    storage.phase = "on"
  elseif storage.phase == "on" then
    local pin = false
    for _, l in ipairs(nest_lines()) do if l:find("[gps=", 1, true) then pin = true end end
    if (pin and not dark) or ev.tick >= 36000 then
      for _, l in ipairs(nest_lines()) do log("on: " .. l) end
      local checks = {
        { "checks off: the dark assembler left alone", storage.off_dark },
        { "checks off: no word of it", storage.off_quiet },
        { "pings off: said something about the nest", storage.off_said },
        { "pings off: no map pin on it", storage.off_nopin },
        { "checks on: ran poles to the assembler", not dark },
        { "pings on: map pin on the second nest", pin },
      }
      local fails = 0
      for _, k in ipairs(checks) do log((k[2] and "PASS " or "FAIL ") .. k[1]) if not k[2] then fails = fails + 1 end end
      log(fails == 0 and "ALL PASS" or (fails .. " FAILED"))
      storage.done = true
    end
  end
end)
