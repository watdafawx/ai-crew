-- Headless check of poling from a far power plant: the generator is 268 tiles from the dark assembler (a big base's
-- steam plant), its line ends in a small pole 26 tiles short, with a powered assembler just past it. Rook, roaming,
-- must run a few poles on from the line's end, not pile them up: where the line passes 200 tiles from the generator,
-- a medium pole's reach off the small pole, or (run with --with power-propagation) by the assembler's hidden pole.
local out = {}
local function log(s) out[#out + 1] = s helpers.write_file("ac-farpower.txt", table.concat(out, "\n") .. "\n") end

script.on_nth_tick(5, function(ev)
  if ev.tick ~= 5 then return end
  local s, f = game.surfaces.nauvis, game.forces.player
  s.always_day = true
  game.forces.enemy.set_evolution_factor(0, s)
  game.map_settings.enemy_expansion.enabled = false
  for _, e in pairs(s.find_entities_filtered({ area = { { -260, -40 }, { 100, 40 } } })) do e.destroy() end
  for _, e in pairs(s.find_entities_filtered({ force = "enemy", area = { { -600, -400 }, { 400, 400 } } })) do e.destroy() end
  local tiles = {}
  for x = -260, 100 do for y = -40, 40 do tiles[#tiles + 1] = { name = "lab-dark-1", position = { x, y } } end end
  s.set_tiles(tiles)
  local chest = s.create_entity({ name = "iron-chest", position = { 0.5, 0.5 }, force = f })
  chest.insert({ name = "medium-electric-pole", count = 40 })
  chest.insert({ name = "raw-fish", count = 20 })
  s.create_entity({ name = "electric-energy-interface", position = { -240, 0 }, force = f })
  s.create_entity({ name = "radar", position = { -236.5, 4.5 }, force = f }) -- (a load: the network's statistics see the generator)
  for x = -238, -6, 8 do s.create_entity({ name = "medium-electric-pole", position = { x + 0.5, 0.5 }, force = f, raise_built = true }) end
  s.create_entity({ name = "small-electric-pole", position = { 1.5, 0.5 }, force = f, raise_built = true })
  s.create_entity({ name = "assembling-machine-1", position = { 4.5, 0.5 }, force = f, recipe = "iron-gear-wheel", raise_built = true })
  storage.asm = s.create_entity({ name = "assembling-machine-1", position = { 27.5, 0.5 }, force = f, recipe = "iron-gear-wheel",
    raise_built = true })
  storage.placed = 0
  remote.call("ai-crew", "hire", "Rook", "nauvis", { x = 2, y = 2 })
  remote.call("ai-crew", "order", nil, "Rook roam")
end)

script.on_event(defines.events.script_raised_built, function(e)
  if e.entity.name == "medium-electric-pole" and e.entity.position.x > 0 then storage.placed = storage.placed + 1 end
end)

script.on_nth_tick(60, function(ev)
  if storage.done or ev.tick < 18000 then return end
  local checks = {
    { "ran poles to the dark assembler", storage.asm.status ~= defines.entity_status.no_power },
    { "placed " .. storage.placed .. " poles (a straight run is 3 or 4)", storage.placed <= 5 },
  }
  local fails = 0
  for _, k in ipairs(checks) do log((k[2] and "PASS " or "FAIL ") .. k[1]) if not k[2] then fails = fails + 1 end end
  log(fails == 0 and "ALL PASS" or (fails .. " FAILED"))
  storage.done = true
end)
