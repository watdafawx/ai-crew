-- Headless check: a goal of 10 gear wheels from nothing but ore, coal and an empty furnace: mine iron ore and coal,
-- fuel and load the furnace, collect plates, hand-craft the gears, deliver to the chest at home.
local out = {}
local function log(s) out[#out + 1] = s helpers.write_file("ac-goal.txt", table.concat(out, "\n") .. "\n") end

script.on_nth_tick(5, function(ev)
  if ev.tick ~= 5 then return end
  local s, f = game.surfaces.nauvis, game.forces.player
  s.always_day = true
  for _, e in pairs(s.find_entities_filtered({ area = { { -80, -80 }, { 80, 80 } } })) do e.destroy() end
  local tiles = {}
  for x = -80, 80 do for y = -80, 80 do tiles[#tiles + 1] = { name = "lab-dark-1", position = { x, y } } end end
  s.set_tiles(tiles)
  s.create_entity({ name = "iron-chest", position = { 0.5, 0.5 }, force = f })
  s.create_entity({ name = "stone-furnace", position = { 6, 0 }, force = f })
  for x = -20, -17 do for y = -2, 1 do s.create_entity({ name = "iron-ore", position = { x + 0.5, y + 0.5 }, amount = 100 }) end end
  for x = 15, 17 do for y = 10, 12 do s.create_entity({ name = "coal", position = { x + 0.5, y + 0.5 }, amount = 100 }) end end
  remote.call("ai-crew", "hire", "Rook", "nauvis", { x = 2, y = 2 })
  remote.call("ai-crew", "order", nil, "Rook goal 10 iron gear wheel")
end)

script.on_nth_tick(600, function(ev)
  if storage.done then return end
  local st = remote.call("ai-crew", "status", "Rook")
  if not st then return end
  local s = game.surfaces.nauvis
  local inv = s.find_entities_filtered({ name = "iron-chest", position = { 0.5, 0.5 } })[1].get_inventory(defines.inventory.chest)
  local gears = inv.get_item_count("iron-gear-wheel")
  log(string.format("t=%d at %.1f,%.1f doing %s, chest: gears %d plates %d ore %d coal %d", ev.tick, st.position.x,
    st.position.y, tostring(st.doing), gears, inv.get_item_count("iron-plate"), inv.get_item_count("iron-ore"), inv.get_item_count("coal")))
  if gears < 10 and ev.tick < 36000 then return end
  log(gears >= 10 and "PASS goal reached: " .. gears .. " gears" or "FAIL goal not reached")
  log(gears >= 10 and "ALL PASS" or "1 FAILED")
  storage.done = true
end)
