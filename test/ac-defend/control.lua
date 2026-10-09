-- Headless check of defending: guns and armor at home but no fish. Rook and Mara go fishing at the pond 30 tiles out
-- (fish caught by hand) first. Then biters attack a wall and a chest 70 tiles from home: the crew rush there (flying),
-- kill them all and the chest survives.
local out, checks = {}, {}
local function log(s) out[#out + 1] = s helpers.write_file("ac-defend.txt", table.concat(out, "\n") .. "\n") end
local function check(name, ok) checks[#checks + 1] = { name, ok and true or false } end
local NAMES = { "Rook", "Mara" }

local function fish_count()
  local n = storage.chest.get_item_count("raw-fish")
  for _, name in ipairs(NAMES) do
    local st = remote.call("ai-crew", "status", name)
    n = n + (st and st.inventory["raw-fish"] or 0)
  end
  return n
end

script.on_event(defines.events.on_tick, function(ev)
  local t = ev.tick
  local s, f = game.surfaces.nauvis, game.forces.player
  if t == 5 then
    s.always_day = true
    game.forces.enemy.set_evolution_factor(0, s)
    game.map_settings.enemy_expansion.enabled = false
    for _, e in pairs(s.find_entities_filtered({ area = { { -150, -150 }, { 150, 150 } } })) do e.destroy() end
    for _, e in pairs(s.find_entities_filtered({ force = "enemy", area = { { -400, -400 }, { 400, 400 } } })) do e.destroy() end
    local tiles = {}
    for x = -150, 150 do for y = -100, 100 do
      tiles[#tiles + 1] = { name = (x >= 30 and x <= 40 and y >= -6 and y <= 6) and "water" or "lab-dark-1", position = { x, y } }
    end end
    s.set_tiles(tiles)
    for _, p in ipairs({ { 33, -3 }, { 36, 0 }, { 34, 3 }, { 38, -2 } }) do s.create_entity({ name = "fish", position = p }) end
    storage.chest = s.create_entity({ name = "iron-chest", position = { 0.5, 0.5 }, force = f })
    storage.chest.insert({ name = "submachine-gun", count = 2 })
    storage.chest.insert({ name = "firearm-magazine", count = 400 })
    storage.chest.insert({ name = "heavy-armor", count = 2 })
    remote.call("ai-crew", "hire", "Rook", "nauvis", { x = 2, y = 2 })
    remote.call("ai-crew", "hire", "Mara", "nauvis", { x = 4, y = 2 })
  elseif t == 3000 then
    log("fish at t=3000: " .. fish_count())
    check("went fishing with none to heal with (" .. fish_count() .. " fish)", fish_count() >= 10)
    for y = -6, 6 do s.create_entity({ name = "stone-wall", position = { -72.5, y + 0.5 }, force = f }) end
    storage.target = s.create_entity({ name = "iron-chest", position = { -69.5, 0.5 }, force = f })
    for i = 1, 8 do
      local u = s.create_entity({ name = "small-biter", position = { -82, -4 + i }, force = "enemy" })
      u.commandable.set_command({ type = defines.command.attack_area, destination = { -70, 0 }, radius = 12 })
    end
    storage.near = 1e9
  elseif storage.near and t % 30 == 0 then
    for _, name in ipairs(NAMES) do
      local st = remote.call("ai-crew", "status", name)
      if st then storage.near = math.min(storage.near, math.sqrt((st.position.x + 70) ^ 2 + st.position.y ^ 2)) end
    end
    local biters = s.count_entities_filtered({ type = "unit", force = "enemy" })
    if not storage.arrived and storage.near < 25 then storage.arrived = t log("someone at the fight at t=" .. t) end
    if biters == 0 and not storage.cleared then storage.cleared = t log("biters dead at t=" .. t) end
    if t == 9000 then
      local flights = 0
      for _, name in ipairs(NAMES) do
        local st = remote.call("ai-crew", "status", name)
        flights = flights + (st and st.flights or 0)
      end
      check("rushed to the attack (there by t=" .. tostring(storage.arrived) .. ")", storage.arrived and storage.arrived < 4200)
      check("flew there (" .. flights .. " flights)", flights > 0)
      check("killed every biter (by t=" .. tostring(storage.cleared) .. ")", storage.cleared ~= nil)
      check("the chest they attacked still stands", storage.target.valid)
      local fails = 0
      for _, k in ipairs(checks) do log((k[2] and "PASS " or "FAIL ") .. k[1]) if not k[2] then fails = fails + 1 end end
      log(fails == 0 and "ALL PASS" or (fails .. " FAILED"))
      storage.near = nil
    end
  end
end)
