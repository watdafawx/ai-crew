-- Headless check: the upgrade planner's marks carried out like a player would: an assembler mid-recipe with plates in
-- it, three belts carrying plates, an inserter. Assembler 2 is in the chest; the fast belts and fast inserter must be
-- crafted. Recipe, contents, items on the belts and directions kept; the old pieces come back to the chest.
local out = {}
local function log(s) out[#out + 1] = s helpers.write_file("ac-upgrade.txt", table.concat(out, "\n") .. "\n") end
local D = defines.direction

script.on_nth_tick(5, function(ev)
  if ev.tick ~= 5 then return end
  local s, f = game.surfaces.nauvis, game.forces.player
  s.always_day = true
  for _, e in pairs(s.find_entities_filtered({ area = { { -60, -60 }, { 60, 60 } } })) do e.destroy() end
  local tiles = {}
  for x = -60, 60 do for y = -60, 60 do tiles[#tiles + 1] = { name = "lab-dark-1", position = { x, y } } end end
  s.set_tiles(tiles)
  for _, r in pairs({ "fast-transport-belt", "fast-inserter", "assembling-machine-2" }) do f.recipes[r].enabled = true end
  local chest = s.create_entity({ name = "iron-chest", position = { 0.5, 0.5 }, force = f })
  chest.insert({ name = "assembling-machine-2", count = 1 })
  chest.insert({ name = "transport-belt", count = 3 })
  chest.insert({ name = "iron-gear-wheel", count = 15 })
  chest.insert({ name = "electronic-circuit", count = 2 })
  chest.insert({ name = "inserter", count = 1 })
  chest.insert({ name = "iron-plate", count = 2 })
  local am = s.create_entity({ name = "assembling-machine-1", position = { 12.5, 6.5 }, force = f })
  am.set_recipe("iron-gear-wheel")
  am.get_inventory(defines.inventory.assembling_machine_input).insert({ name = "iron-plate", count = 20 })
  am.order_upgrade({ force = f, target = "assembling-machine-2" })
  for i = 0, 2 do
    local b = s.create_entity({ name = "transport-belt", position = { 8.5 + i, -6.5 }, direction = D.east, force = f })
    b.get_transport_line(1).insert_at_back({ name = "iron-plate", count = 1 })
    b.order_upgrade({ force = f, target = "fast-transport-belt" })
  end
  local ins = s.create_entity({ name = "inserter", position = { 14.5, -6.5 }, direction = D.west, force = f })
  ins.order_upgrade({ force = f, target = "fast-inserter" })
  remote.call("ai-crew", "hire", "Rook", "nauvis", { x = 2, y = 2 })
end)

script.on_nth_tick(600, function(ev)
  if storage.done or ev.tick == 0 then return end
  local s = game.surfaces.nauvis
  local inv = s.find_entities_filtered({ name = "iron-chest", position = { 0.5, 0.5 } })[1].get_inventory(defines.inventory.chest)
  local c = function(n) return inv.get_item_count(n) end
  local st = remote.call("ai-crew", "status", "Rook")
  local am = s.find_entities_filtered({ name = "assembling-machine-2", position = { 12.5, 6.5 }, radius = 0.5 })[1]
  local fast = s.find_entities_filtered({ name = "fast-transport-belt" })
  local on_belts = 0
  for _, b in pairs(fast) do on_belts = on_belts + b.get_transport_line(1).get_item_count("iron-plate") end
  local fi = s.find_entities_filtered({ name = "fast-inserter" })[1]
  local marked = s.count_entities_filtered({ to_be_upgraded = true })
  log(string.format("t=%d doing %s; marked %d; am2 %s, fast belts %d, fast inserter %s; chest: am1 %d belts %d inserters %d",
    ev.tick, tostring(st.doing), marked, tostring(am ~= nil), #fast, tostring(fi ~= nil), c("assembling-machine-1"),
    c("transport-belt"), c("inserter")))
  if marked > 0 and ev.tick < 18000 then return end
  if st.jobs > 0 and ev.tick < 18000 then return end
  local recipe = am and am.get_recipe()
  local checks = {
    { "assembler upgraded", am ~= nil and s.count_entities_filtered({ name = "assembling-machine-1" }) == 0 },
    { "its recipe kept", recipe ~= nil and recipe.name == "iron-gear-wheel" },
    { "its plates kept", am ~= nil and am.get_inventory(defines.inventory.assembling_machine_input).get_item_count("iron-plate") +
      am.get_inventory(defines.inventory.assembling_machine_output).get_item_count("iron-gear-wheel") * 2 + (am.is_crafting() and 2 or 0) >= 20 },
    { "belts crafted and upgraded, direction kept", #fast == 3 and fast[1].direction == D.east },
    { "plates on the belts kept", on_belts == 3 },
    { "inserter crafted and upgraded, direction kept", fi ~= nil and fi.direction == D.west },
    { "nothing left marked", marked == 0 },
    { "old pieces back in the chest", c("assembling-machine-1") == 1 and c("transport-belt") == 3 and c("inserter") == 1 },
  }
  local fails = 0
  for _, k in ipairs(checks) do log((k[2] and "PASS " or "FAIL ") .. k[1]) if not k[2] then fails = fails + 1 end end
  log(fails == 0 and "ALL PASS" or (fails .. " FAILED"))
  storage.done = true
end)
