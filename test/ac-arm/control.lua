-- Headless check: no gun or ammo anywhere, only plates in a chest: the crew member makes a submachine gun and
-- magazines for itself and arms up.
local out = {}
local function log(s) out[#out + 1] = s helpers.write_file("ac-arm.txt", table.concat(out, "\n") .. "\n") end

script.on_nth_tick(5, function(ev)
  if ev.tick ~= 5 then return end
  local s, f = game.surfaces.nauvis, game.forces.player
  s.always_day = true
  for _, e in pairs(s.find_entities_filtered({ area = { { -60, -60 }, { 60, 60 } } })) do e.destroy() end
  local tiles = {}
  for x = -60, 60 do for y = -60, 60 do tiles[#tiles + 1] = { name = "lab-dark-1", position = { x, y } } end end
  s.set_tiles(tiles)
  for _, r in pairs({ "submachine-gun", "firearm-magazine" }) do f.recipes[r].enabled = true end
  local chest = s.create_entity({ name = "iron-chest", position = { 0.5, 0.5 }, force = f })
  chest.insert({ name = "iron-plate", count = 200 })
  chest.insert({ name = "copper-plate", count = 50 })
  remote.call("ai-crew", "hire", "Rook", "nauvis", { x = 2, y = 2 })
end)

script.on_nth_tick(600, function(ev)
  if storage.done then return end
  local st = remote.call("ai-crew", "status", "Rook")
  if not st then return end
  log(string.format("t=%d doing %s need %s armed %s", ev.tick, tostring(st.doing), tostring(st.need), tostring(st.armed)))
  if not st.armed and ev.tick < 18000 then return end
  log((st.armed and "PASS" or "FAIL") .. " made its own gun and ammo")
  log(st.armed and "ALL PASS" or "1 FAILED")
  storage.done = true
end)
