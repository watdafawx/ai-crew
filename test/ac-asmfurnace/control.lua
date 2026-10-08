-- Headless check: the placement case with the stone furnace an assembling machine (a recipe must be set), as in
-- overhaul packs: one crew furnace, its recipe set, the goal reached; the line left alone, nothing spammed.
local out = {}
local function log(s) out[#out + 1] = s helpers.write_file("ac-asmfurnace.txt", table.concat(out, "\n") .. "\n") end
local D = defines.direction

script.on_nth_tick(5, function(ev)
  if ev.tick ~= 5 then return end
  local s, f = game.surfaces.nauvis, game.forces.player
  s.always_day = true
  for _, e in pairs(s.find_entities_filtered({ area = { { -80, -80 }, { 80, 80 } } })) do e.destroy() end
  local tiles = {}
  for x = -80, 80 do for y = -80, 80 do tiles[#tiles + 1] = { name = "lab-dark-1", position = { x, y } } end end
  s.set_tiles(tiles)
  s.create_entity({ name = "iron-chest", position = { 0.5, 0.5 }, force = f })
  storage.player_furnaces = {}
  -- the player's line, all round home: furnace + assembler pairs, each fed by an inserter
  for i = 0, 5 do
    for _, y in ipairs({ -6, 7 }) do
      local x = -10 + i * 6
      local fur = s.create_entity({ name = "stone-furnace", position = { x, y }, force = f })
      storage.player_furnaces[#storage.player_furnaces + 1] = fur
      s.create_entity({ name = "assembling-machine-1", position = { x + 2.5, y + 0.5 }, force = f })
      s.create_entity({ name = "inserter", position = { x - 0.5, y - 1.5 }, direction = D.south, force = f })
    end
  end
  for x = -26, -22 do for y = -2, 2 do s.create_entity({ name = "iron-ore", position = { x + 0.5, y + 0.5 }, amount = 200 }) end end
  for x = 22, 24 do for y = -2, 0 do s.create_entity({ name = "stone", position = { x + 0.5, y + 0.5 }, amount = 100 }) end end
  for x = 22, 24 do for y = 12, 14 do s.create_entity({ name = "coal", position = { x + 0.5, y + 0.5 }, amount = 100 }) end end
  remote.call("ai-crew", "hire", "Rook", "nauvis", { x = 2, y = 2 })
  remote.call("ai-crew", "order", nil, "Rook goal 10 iron plate")
end)

script.on_nth_tick(600, function(ev)
  if storage.done or ev.tick == 0 then return end
  local s = game.surfaces.nauvis
  local st = remote.call("ai-crew", "status", "Rook")
  local inv = s.find_entities_filtered({ name = "iron-chest", position = { 0.5, 0.5 } })[1].get_inventory(defines.inventory.chest)
  local mine = {}
  for _, fur in pairs(s.find_entities_filtered({ name = "stone-furnace" })) do
    local theirs = false
    for _, pf in pairs(storage.player_furnaces) do if pf == fur then theirs = true end end
    if not theirs then mine[#mine + 1] = fur end
  end
  log(string.format("t=%d doing %s; crew furnaces %d; chest plates %d", ev.tick, tostring(st.doing), #mine, inv.get_item_count("iron-plate")))
  if inv.get_item_count("iron-plate") < 10 and #mine <= 1 and ev.tick < 36000 then return end
  local untouched = true
  for _, pf in pairs(storage.player_furnaces) do
    if pf.get_recipe() or pf.products_finished > 0 then untouched = false end
  end
  local clear, overlaps = #mine > 0, false
  for _, fur in pairs(mine) do
    local b = fur.bounding_box
    for _, other in pairs(s.find_entities_filtered({ area = { { b.left_top.x - 2.9, b.left_top.y - 2.9 },
      { b.right_bottom.x + 2.9, b.right_bottom.y + 2.9 } }, force = "player" })) do
      local crews = false
      for _, c in pairs(mine) do if c == other then crews = true end end
      if not crews and other.type ~= "character" then clear = false log("  too close: " .. other.name .. " at " .. other.position.x .. "," .. other.position.y .. " (furnace at " .. fur.position.x .. "," .. fur.position.y .. ")") end
    end
    for _, other in pairs(s.find_entities_filtered({ area = b, force = "player" })) do
      if other ~= fur and other.type ~= "character" then overlaps = true end
    end
  end
  local checks = {
    { "the player's line furnaces left alone", untouched },
    { "one crew furnace, not a row of them (" .. #mine .. ")", #mine == 1 },
    { "its recipe set", mine[1] ~= nil and mine[1].get_recipe() ~= nil and mine[1].get_recipe().name == "iron-plate" },
    { "it overlaps nothing", not overlaps },
    { "3 tiles clear of the player's buildings", clear },
    { "goal reached", inv.get_item_count("iron-plate") >= 10 },
  }
  local fails = 0
  for _, k in ipairs(checks) do log((k[2] and "PASS " or "FAIL ") .. k[1]) if not k[2] then fails = fails + 1 end end
  log(fails == 0 and "ALL PASS" or (fails .. " FAILED"))
  storage.done = true
end)
