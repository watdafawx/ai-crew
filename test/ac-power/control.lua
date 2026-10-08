-- Headless check: an engine goal with no assembler and no power. The crew must hand-craft an assembler and set it up,
-- build steam power at the lake (pump, boiler, engine), run poles to the assembler, fuel the boiler, then make it.
local out = {}
local function log(s) out[#out + 1] = s helpers.write_file("ac-power.txt", table.concat(out, "\n") .. "\n") end

script.on_nth_tick(5, function(ev)
  if ev.tick ~= 5 then return end
  local s, f = game.surfaces.nauvis, game.forces.player
  s.always_day = true
  for _, e in pairs(s.find_entities_filtered({ area = { { -90, -90 }, { 90, 90 } } })) do e.destroy() end
  local tiles = {}
  for x = -90, 90 do for y = -90, 90 do tiles[#tiles + 1] = { name = (x >= 30 and "water" or "lab-dark-1"), position = { x, y } } end end
  s.set_tiles(tiles)
  for _, r in pairs({ "steel-plate", "engine-unit", "pipe", "offshore-pump", "boiler", "steam-engine", "small-electric-pole",
    "assembling-machine-1", "electronic-circuit", "copper-cable" }) do f.recipes[r].enabled = true end
  s.create_entity({ name = "iron-chest", position = { 0.5, 0.5 }, force = f })
  local function patch(name, x0, y0) for x = x0, x0 + 4 do for y = y0, y0 + 4 do s.create_entity({ name = name, position = { x + 0.5, y + 0.5 }, amount = 500 }) end end end
  patch("iron-ore", -22, -2)
  patch("copper-ore", -22, 8)
  patch("stone", 12, -14)
  patch("coal", 12, 10)
  for i = 0, 5 do s.create_entity({ name = "tree-01", position = { -8 + i * 2, -18 } }) end
  remote.call("ai-crew", "hire", "Rook", "nauvis", { x = 2, y = 2 })
  remote.call("ai-crew", "order", nil, "Rook goal 1 engine unit")
end)

script.on_nth_tick(1800, function(ev)
  if storage.done then return end
  local st = remote.call("ai-crew", "status", "Rook")
  if not st then return end
  local s = game.surfaces.nauvis
  local inv = s.find_entities_filtered({ name = "iron-chest", position = { 0.5, 0.5 } })[1].get_inventory(defines.inventory.chest)
  local am = s.find_entities_filtered({ name = "assembling-machine-1" })[1]
  local function n(name) return s.count_entities_filtered({ name = name }) end
  log(string.format("t=%d at %.0f,%.0f doing %s need %s; furnaces %d am %d pump %d boiler %d engine %d poles %d; chest: engine %d plates %d",
    ev.tick, st.position.x, st.position.y, tostring(st.doing), tostring(st.need), n("stone-furnace"), n("assembling-machine-1"), n("offshore-pump"),
    n("boiler"), n("steam-engine"), n("small-electric-pole"), inv.get_item_count("engine-unit"), inv.get_item_count("iron-plate")))
  local done = inv.get_item_count("engine-unit") >= 1
  if not done and ev.tick < 144000 then return end
  local checks = {
    { "assembler hand-crafted and placed", am ~= nil },
    { "steam plant built", n("offshore-pump") == 1 and n("boiler") == 1 and n("steam-engine") == 1 },
    { "assembler powered", am and am.status ~= defines.entity_status.no_power },
    { "engine goal reached", done },
  }
  local fails = 0
  for _, k in ipairs(checks) do log((k[2] and "PASS " or "FAIL ") .. k[1]) if not k[2] then fails = fails + 1 end end
  log(fails == 0 and "ALL PASS" or (fails .. " FAILED"))
  storage.done = true
end)
