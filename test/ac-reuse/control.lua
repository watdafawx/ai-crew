-- Headless check: the crew use a machine the player already placed before building their own. Your assembler stands
-- idle on another recipe (copper cable), powered, fed by nothing; the goal is engine units (assembler-only), and the
-- chest holds their ingredients and two assemblers they could put down. Rook makes them in yours (no new assembler)
-- and sets it back to copper cable after. Three of yours in lines stand nearer, idle on other recipes: one an inserter
-- empties onto a belt, one a loader empties, one with a pipe on it; those are never switched.
local out = {}
local function log(s) out[#out + 1] = s helpers.write_file("ac-reuse.txt", table.concat(out, "\n") .. "\n") end

script.on_nth_tick(5, function(ev)
  if ev.tick ~= 5 then return end
  local s, f = game.surfaces.nauvis, game.forces.player
  s.always_day = true
  for _, e in pairs(s.find_entities_filtered({ area = { { -80, -80 }, { 80, 80 } } })) do e.destroy() end
  local tiles = {}
  for x = -80, 80 do for y = -80, 80 do tiles[#tiles + 1] = { name = "lab-dark-1", position = { x, y } } end end
  s.set_tiles(tiles)
  f.recipes["engine-unit"].enabled = true
  local chest = s.create_entity({ name = "iron-chest", position = { 0.5, 0.5 }, force = f })
  chest.insert({ name = "steel-plate", count = 20 })
  chest.insert({ name = "iron-gear-wheel", count = 20 })
  chest.insert({ name = "pipe", count = 40 })
  chest.insert({ name = "assembling-machine-1", count = 2 })
  s.create_entity({ name = "electric-energy-interface", position = { 10, 0 }, force = f })
  s.create_entity({ name = "small-electric-pole", position = { 12.5, 0.5 }, force = f })
  storage.asm = s.create_entity({ name = "assembling-machine-1", position = { 14.5, 3.5 }, force = f, recipe = "copper-cable" })
  -- your lines: nearer, idle, on other recipes (an output inserter onto a belt; a loader; a pipe)
  f.recipes["electric-engine-unit"].enabled = true
  storage.lines = {
    s.create_entity({ name = "assembling-machine-1", position = { 6.5, -4.5 }, force = f, recipe = "iron-gear-wheel" }),
    s.create_entity({ name = "assembling-machine-1", position = { 6.5, 8.5 }, force = f, recipe = "iron-gear-wheel" }),
    s.create_entity({ name = "assembling-machine-2", position = { 16.5, -5.5 }, force = f, recipe = "electric-engine-unit" }),
  }
  s.create_entity({ name = "inserter", position = { 6.5, -2.5 }, direction = defines.direction.north, force = f })
  s.create_entity({ name = "transport-belt", position = { 6.5, -1.5 }, force = f })
  s.create_entity({ name = "small-electric-pole", position = { 8.5, -1.5 }, force = f })
  s.create_entity({ name = "loader", position = { 6.5, 11 }, direction = defines.direction.south, type = "output", force = f })
  s.create_entity({ name = "small-electric-pole", position = { 8.5, 6.5 }, force = f })
  s.create_entity({ name = "small-electric-pole", position = { 14.5, -3.5 }, force = f })
  s.create_entity({ name = "pipe", position = storage.lines[3].fluidbox.get_pipe_connections(1)[1].target_position, force = f })
  remote.call("ai-crew", "test_machines", true)
  remote.call("ai-crew", "hire", "Rook", "nauvis", { x = 2, y = 2 }, nil, nil, "stay")
  remote.call("ai-crew", "order", nil, "Rook goal 5 engine unit")
  storage.started = true
end)

script.on_nth_tick(600, function(ev)
  if storage.done or not storage.started then return end
  local s = game.surfaces.nauvis
  local chest = s.find_entities_filtered({ name = "iron-chest", position = { 0.5, 0.5 } })[1]
  local st = remote.call("ai-crew", "status", "Rook")
  local units = chest.get_item_count("engine-unit") + (st and st.carry and st.carry["engine-unit"] or 0)
  local asms = s.count_entities_filtered({ name = "assembling-machine-1" })
  local r = storage.asm.valid and storage.asm.get_recipe()
  log(string.format("t=%d engine units %d in the chest; assemblers %d; yours on %s; Rook doing %s", ev.tick,
    chest.get_item_count("engine-unit"), asms, r and r.name or "nothing", st and tostring(st.doing) or "-"))
  for i, l in ipairs(storage.lines) do
    local lr = l.get_recipe()
    if not (lr and lr.name == (i == 3 and "electric-engine-unit" or "iron-gear-wheel")) then
      storage.lines_kept = false
      log("line machine " .. i .. " switched to " .. (lr and lr.name or "nothing"))
    end
  end
  storage.used = storage.used or (r and r.name == "engine-unit")
  if chest.get_item_count("engine-unit") >= 5 or ev.tick >= 36000 then
    local checks = {
      { "made the engine units", chest.get_item_count("engine-unit") >= 5 },
      { "in your assembler", storage.used },
      { "built none of its own (" .. asms .. " assembler 1s, 3 of yours)", asms == 3 },
      { "yours set back to copper cable", r and r.name == "copper-cable" },
      { "the line machines left on their recipes", storage.lines_kept ~= false },
    }
    local fails = 0
    for _, k in ipairs(checks) do log((k[2] and "PASS " or "FAIL ") .. k[1]) if not k[2] then fails = fails + 1 end end
    log(fails == 0 and "ALL PASS" or (fails .. " FAILED"))
    storage.done = true
  end
end)
