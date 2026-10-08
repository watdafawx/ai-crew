-- Headless check: three crew members carry items home through a field of assemblers with one-tile gaps (as in a
-- real build), home being a gap among the machines; nobody may stay stuck against a machine.
local out = {}
local function log(s) out[#out + 1] = s helpers.write_file("ac-path.txt", table.concat(out, "\n") .. "\n") end
local NAMES = { "Rook", "Mara", "Juno" }

local function body(name)
  local st = remote.call("ai-crew", "status", name)
  return st and game.surfaces.nauvis.find_entities_filtered({ name = "character", position = st.position, radius = 0.3 })[1]
end

script.on_nth_tick(5, function(ev)
  if ev.tick ~= 5 then return end
  local s, f = game.surfaces.nauvis, game.forces.player
  s.always_day = true
  for _, e in pairs(s.find_entities_filtered({ area = { { -60, -60 }, { 60, 60 } } })) do e.destroy() end
  local tiles = {}
  for x = -60, 60 do for y = -60, 60 do tiles[#tiles + 1] = { name = "lab-dark-1", position = { x, y } } end end
  s.set_tiles(tiles)
  s.create_entity({ name = "iron-chest", position = { 0.5, 0.5 }, force = f })
  -- assemblers 3x3 with 1-tile gaps, offset rows, between x = 6 and 30
  for row = 0, 5 do
    for col = 0, 5 do
      s.create_entity({ name = "assembling-machine-1", position = { 7.5 + col * 4 + (row % 2) * 2, -10.5 + row * 4 }, force = f })
    end
  end
  for i, n in ipairs(NAMES) do
    -- (home: in a one-tile gap between the assemblers, as when you stand among your machines)
    remote.call("ai-crew", "hire", n, "nauvis", { x = 9.5 + (i - 2) * 4, y = -8.5 })
    remote.call("ai-crew", "order", nil, n .. " stay")
    local b = body(n)
    b.teleport({ x = 36, y = -6 + i * 3 })
    b.insert({ name = "iron-plate", count = 10 })
    remote.call("ai-crew", "order", nil, n .. " deliver")
  end
  storage.start = ev.tick
end)

script.on_nth_tick(300, function(ev)
  if storage.done or not storage.start then return end
  local s = game.surfaces.nauvis
  local inv = s.find_entities_filtered({ name = "iron-chest", position = { 0.5, 0.5 } })[1].get_inventory(defines.inventory.chest)
  local parts = {}
  for _, n in ipairs(NAMES) do
    local st = remote.call("ai-crew", "status", n)
    parts[#parts + 1] = string.format("%s %.1f,%.1f %s", n, st.position.x, st.position.y, tostring(st.doing))
  end
  log(string.format("t=%d plates home %d; %s", ev.tick, inv.get_item_count("iron-plate"), table.concat(parts, " | ")))
  local done = inv.get_item_count("iron-plate") == 30
  if not done and ev.tick < storage.start + 7200 then return end
  log((done and "PASS" or "FAIL") .. " all three got through the machines (" .. math.floor((ev.tick - storage.start) / 60) .. " s)")
  log(done and "ALL PASS" or "1 FAILED")
  storage.done = true
end)
