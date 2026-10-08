-- Headless check: a goal with a line. A stand-in for bpgen (no Python headless) places a small line as ghosts:
-- input belt -> burner inserter -> stone furnace -> burner inserter -> output belt, and answers line_placed. The crew
-- build it, fuel it, feed ore and coal onto its input, take plates off its output, until the goal is reached.
local out = {}
local function log(s) out[#out + 1] = s helpers.write_file("ac-line.txt", table.concat(out, "\n") .. "\n") end
local D = defines.direction

remote.add_interface("bpgen", {
  plan_line = function(owner, item, rate, reply)
    local s, f = game.surfaces.nauvis, game.forces.player
    -- which way an inserter faces to drop south (the API's facing differs between versions)
    local probe = s.create_entity({ name = "burner-inserter", position = { 60.5, 60.5 }, direction = D.north, force = f })
    local south = probe.drop_position.y > probe.position.y and D.north or D.south
    probe.destroy()
    local function ghost(name, x, y, dir) s.create_entity({ name = "entity-ghost", inner_name = name, position = { x, y }, direction = dir, force = f }) end
    for x = -3, 0 do ghost("transport-belt", x + 0.5, 8.5, D.east) end
    ghost("burner-inserter", -0.5, 9.5, south)
    ghost("stone-furnace", 0, 11)
    ghost("burner-inserter", -0.5, 12.5, south)
    for x = 0, 3 do ghost("transport-belt", x - 0.5, 13.5, D.east) end
    storage.asked = (storage.asked or 0) + 1
    remote.call(reply, "line_placed", owner, item, 11, nil, { box = { -5, 7, 10, 8 },
      inputs = { { items = { "coal", "iron-ore" }, position = { x = -2.5, y = 8.5 } } },
      outputs = { { item = "iron-plate", position = { x = 2.5, y = 13.5 } } } })
  end,
})

script.on_nth_tick(5, function(ev)
  if ev.tick ~= 5 then return end
  local s, f = game.surfaces.nauvis, game.forces.player
  s.always_day = true
  for _, e in pairs(s.find_entities_filtered({ area = { { -80, -80 }, { 80, 80 } } })) do e.destroy() end
  local tiles = {}
  for x = -80, 80 do for y = -80, 80 do tiles[#tiles + 1] = { name = "lab-dark-1", position = { x, y } } end end
  s.set_tiles(tiles)
  s.create_entity({ name = "iron-chest", position = { 20.5, 0.5 }, force = f }).insert({ name = "iron-plate", count = 30 })
  local function patch(name, x0, y0) for x = x0, x0 + 4 do for y = y0, y0 + 4 do s.create_entity({ name = name, position = { x + 0.5, y + 0.5 }, amount = 500 }) end end end
  patch("iron-ore", -25, -2)
  patch("coal", -25, 14)
  patch("stone", 25, -14)
  remote.call("ai-crew", "hire", "Rook", "nauvis", { x = 10, y = 2 })
  remote.call("ai-crew", "order", nil, "Rook goal 80 iron plate line")
end)

script.on_nth_tick(1800, function(ev)
  if storage.done then return end
  local st = remote.call("ai-crew", "status", "Rook")
  if not st then return end
  local s = game.surfaces.nauvis
  local inv = s.find_entities_filtered({ name = "iron-chest", position = { 20.5, 0.5 } })[1].get_inventory(defines.inventory.chest)
  local ghosts = s.count_entities_filtered({ type = "entity-ghost" })
  local fur = s.find_entities_filtered({ name = "stone-furnace", position = { 0, 11 }, radius = 1 })[1]
  log(string.format("t=%d doing %s; ghosts %d; fed %s collected %s; line furnace made %s; chest plates %d", ev.tick,
    tostring(st.doing), ghosts, tostring(st.fed), tostring(st.collected), tostring(fur and fur.products_finished), inv.get_item_count("iron-plate")))
  local reached = inv.get_item_count("iron-plate") >= 80
  if not reached and ev.tick < 72000 then return end
  local checks = {
    { "bpgen asked once", storage.asked == 1 },
    { "line built", ghosts == 0 and fur ~= nil },
    { "line fed by hand", (st.fed or 0) > 0 },
    { "line's furnace ran", fur and fur.products_finished > 0 },
    { "output collected", (st.collected or 0) > 0 },
    { "goal reached", reached },
  }
  local fails = 0
  for _, k in ipairs(checks) do log((k[2] and "PASS " or "FAIL ") .. k[1]) if not k[2] then fails = fails + 1 end end
  log(fails == 0 and "ALL PASS" or (fails .. " FAILED"))
  storage.done = true
end)
