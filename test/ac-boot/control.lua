-- Headless check: nothing to start with but ore, stone, an empty assembler and coal in a logistic network.
-- A ghost (iron chest), a gear order and an engine goal all need plates: the crew mines stone, makes and places a
-- stone furnace, fuels it from the network, smelts, hand-crafts, sets the assembler's recipe for the engine.
local out = {}
local function log(s) out[#out + 1] = s helpers.write_file("ac-boot.txt", table.concat(out, "\n") .. "\n") end

script.on_nth_tick(5, function(ev)
  if ev.tick ~= 5 then return end
  local s, f = game.surfaces.nauvis, game.forces.player
  s.always_day = true
  for _, e in pairs(s.find_entities_filtered({ area = { { -80, -80 }, { 80, 80 } } })) do e.destroy() end
  local tiles = {}
  for x = -80, 80 do for y = -80, 80 do tiles[#tiles + 1] = { name = "lab-dark-1", position = { x, y } } end end
  s.set_tiles(tiles)
  for _, r in pairs({ "steel-plate", "engine-unit", "pipe" }) do f.recipes[r].enabled = true end
  s.create_entity({ name = "iron-chest", position = { 0.5, 0.5 }, force = f })
  s.create_entity({ name = "electric-energy-interface", position = { -6, -6 }, force = f })
  s.create_entity({ name = "substation", position = { -3, -3 }, force = f })
  s.create_entity({ name = "assembling-machine-1", position = { -9.5, 2.5 }, force = f })
  s.create_entity({ name = "roboport", position = { 4, -9 }, force = f })
  s.create_entity({ name = "storage-chest", position = { 8.5, -9.5 }, force = f }).insert({ name = "coal", count = 20 })
  for x = -24, -20 do for y = -2, 2 do s.create_entity({ name = "iron-ore", position = { x + 0.5, y + 0.5 }, amount = 200 }) end end
  for x = 18, 20 do for y = -2, 0 do s.create_entity({ name = "stone", position = { x + 0.5, y + 0.5 }, amount = 100 }) end end
  s.create_entity({ name = "entity-ghost", inner_name = "iron-chest", position = { 10.5, 18.5 }, force = f })
  remote.call("ai-crew", "hire", "Rook", "nauvis", { x = 2, y = 2 })
  remote.call("ai-crew", "order", nil, "Rook craft 5 gears")
  remote.call("ai-crew", "order", nil, "Rook goal 1 engine unit")
end)

script.on_nth_tick(600, function(ev)
  if storage.done then return end
  local st = remote.call("ai-crew", "status", "Rook")
  if not st then return end
  local s = game.surfaces.nauvis
  local inv = s.find_entities_filtered({ name = "iron-chest", position = { 0.5, 0.5 } })[1].get_inventory(defines.inventory.chest)
  local c = function(n) return inv.get_item_count(n) end
  local am = s.find_entities_filtered({ name = "assembling-machine-1" })[1]
  local checks = {
    { "stone furnace made and placed", s.count_entities_filtered({ name = "stone-furnace" }) >= 1 },
    { "iron chest ghost built", s.count_entities_filtered({ name = "iron-chest", position = { 10.5, 18.5 } }) == 1 },
    { "gear order done after working for plates (the engine used one)", c("iron-gear-wheel") + c("engine-unit") >= 5 },
    { "engine goal reached", c("engine-unit") >= 1 },
    { "assembler recipe set by the crew", am.get_recipe() and am.get_recipe().name == "engine-unit" },
    { "coal taken from the logistic network", s.find_entities_filtered({ name = "storage-chest" })[1].get_item_count("coal") < 20 },
  }
  local fails = 0
  for _, k in ipairs(checks) do if not k[2] then fails = fails + 1 end end
  log(string.format("t=%d doing %s (%d), chest: plates %d gears %d steel %d engine %d stone %d", ev.tick, tostring(st.doing),
    st.jobs, c("iron-plate"), c("iron-gear-wheel"), c("steel-plate"), c("engine-unit"), c("stone")))
  if fails > 0 and ev.tick < 36000 then return end
  for _, k in ipairs(checks) do log((k[2] and "PASS " or "FAIL ") .. k[1]) end
  log(fails == 0 and "ALL PASS" or (fails .. " FAILED"))
  storage.done = true
end)
