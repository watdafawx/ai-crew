-- Headless check: one crew member with no owner works out of a chest at home (0, 0). Build and clear aren't
-- ordered: it does them on its own once its orders are done.
local out = {}
local function log(s) out[#out + 1] = s helpers.write_file("ac-test.txt", table.concat(out, "\n") .. "\n") end

script.on_nth_tick(5, function(ev)
  if ev.tick ~= 5 then return end
  local s, f = game.surfaces.nauvis, game.forces.player
  s.always_day = true
  for _, e in pairs(s.find_entities_filtered({ area = { { -80, -80 }, { 80, 80 } } })) do e.destroy() end
  local tiles = {}
  for x = -80, 80 do for y = -80, 80 do tiles[#tiles + 1] = { name = "lab-dark-1", position = { x, y } } end end
  s.set_tiles(tiles)
  local chest = s.create_entity({ name = "iron-chest", position = { 0.5, 0.5 }, force = f })
  chest.insert({ name = "iron-plate", count = 40 })
  chest.insert({ name = "transport-belt", count = 5 })
  chest.insert({ name = "stone-furnace", count = 1 })
  for i = 0, 2 do s.create_entity({ name = "entity-ghost", inner_name = "transport-belt", position = { 15.5 + i, 10.5 }, force = f }) end
  s.create_entity({ name = "entity-ghost", inner_name = "stone-furnace", position = { 15, 14 }, force = f })
  s.create_entity({ name = "entity-ghost", inner_name = "assembling-machine-1", position = { 20.5, 14.5 }, force = f }) -- needs circuits: skipped
  s.create_entity({ name = "entity-ghost", inner_name = "iron-chest", position = { 10.5, 18.5 }, force = f }) -- none in the chest: hand-crafted
  local junk = s.create_entity({ name = "wooden-chest", position = { -12.5, 6.5 }, force = f })
  junk.order_deconstruction(f)
  for x = -26, -23 do for y = -3, 0 do s.create_entity({ name = "iron-ore", position = { x + 0.5, y + 0.5 }, amount = 50 }) end end
  -- a wall of chests between home and the ore: walking needs a path round it
  for y = -8, 6 do s.create_entity({ name = "iron-chest", position = { -18.5, y + 0.5 }, force = "neutral" }) end
  log("hired " .. remote.call("ai-crew", "hire", "Rook", "nauvis", { x = 2, y = 2 }))
  for _, o in ipairs({ "Rook get 10 iron ore", "Rook craft 2 belts", "Rook craft 5 gears", "Rook bogus words here now" }) do
    remote.call("ai-crew", "order", nil, o)
  end
  log("queued: " .. remote.call("ai-crew", "status", "Rook").jobs)
end)

script.on_nth_tick(600, function(ev)
  if storage.done then return end
  local s = game.surfaces.nauvis
  local st = remote.call("ai-crew", "status", "Rook")
  if not st then return end
  log(string.format("t=%d at %.1f,%.1f doing %s (%d)", ev.tick, st.position.x, st.position.y, tostring(st.doing), st.jobs))
  if ev.tick < 6000 or (ev.tick < 14400 and st.jobs > 0) then return end
  local chest = s.find_entities_filtered({ name = "iron-chest", position = { 0.5, 0.5 } })[1]
  local inv = chest.get_inventory(defines.inventory.chest)
  local function c(n) return inv.get_item_count(n) end
  local built = s.count_entities_filtered({ name = "transport-belt" })
  local checks = {
    { "belts built", built == 3 },
    { "iron chest hand-crafted and built", s.count_entities_filtered({ name = "iron-chest", position = { 10.5, 18.5 } }) == 1 },
    { "furnace built", s.count_entities_filtered({ name = "stone-furnace" }) == 1 },
    { "assembler ghost left (no item)", s.count_entities_filtered({ ghost_name = "assembling-machine-1" }) == 1 },
    { "marked chest cleared", s.count_entities_filtered({ name = "wooden-chest" }) == 0 },
    { "its chest delivered home", c("wooden-chest") == 1 },
    { "iron ore mined and delivered", c("iron-ore") >= 10 },
    { "gears crafted and delivered", c("iron-gear-wheel") == 5 },
    { "belts crafted (gear made on the way)", c("transport-belt") == 2 + 2 },
    { "plates used: 40 - 3 (belts) - 10 (gears) - 8 (chest)", c("iron-plate") == 19 },
    { "pockets empty", next(st.inventory) == nil },
    { "nothing left queued", st.jobs == 0 },
  }
  local fails = 0
  for _, k in ipairs(checks) do
    log((k[2] and "PASS " or "FAIL ") .. k[1])
    if not k[2] then fails = fails + 1 end
  end
  log(string.format("chest: plates %d ore %d gears %d belts %d wood-chest %d", c("iron-plate"), c("iron-ore"), c("iron-gear-wheel"), c("transport-belt"), c("wooden-chest")))
  log(fails == 0 and "ALL PASS" or (fails .. " FAILED"))
  storage.done = true
end)
