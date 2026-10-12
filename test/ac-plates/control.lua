-- Headless check of fetching before making: stone and coal at home (enough for a furnace), iron and copper ore close
-- by, 60 iron plates in a chest 100 tiles out. "get 20 iron plate": Rook fetches them from that chest, builds no
-- furnace. Then, with "Crew build machines" off, "get 20 copper plate" (none made anywhere): still no furnace.
local out, checks = {}, {}
local function log(s) out[#out + 1] = s helpers.write_file("ac-plates.txt", table.concat(out, "\n") .. "\n") end
local function check(name, ok) checks[#checks + 1] = { name, ok and true or false } end
local function furnaces() return game.surfaces.nauvis.count_entities_filtered({ type = "furnace" }) end

script.on_event(defines.events.on_tick, function(ev)
  local t = ev.tick
  local s, f = game.surfaces.nauvis, game.forces.player
  if t == 5 then
    s.always_day = true
    game.map_settings.enemy_expansion.enabled = false
    for _, e in pairs(s.find_entities_filtered({ area = { { -150, -150 }, { 150, 150 } } })) do e.destroy() end
    for _, e in pairs(s.find_entities_filtered({ force = "enemy", area = { { -400, -400 }, { 400, 400 } } })) do e.destroy() end
    for _, e in pairs(s.find_entities_filtered({ type = { "resource", "fish" }, area = { { -400, -400 }, { 400, 400 } } })) do
      e.destroy()
    end
    local tiles = {}
    for x = -150, 150 do for y = -100, 100 do tiles[#tiles + 1] = { name = "lab-dark-1", position = { x, y } } end end
    s.set_tiles(tiles)
    for x = 12, 15 do for y = -2, 1 do
      s.create_entity({ name = "iron-ore", position = { x + 0.5, y + 0.5 }, amount = 500 })
      s.create_entity({ name = "copper-ore", position = { x + 0.5, y + 8.5 }, amount = 500 })
    end end
    storage.home = s.create_entity({ name = "iron-chest", position = { 0.5, 0.5 }, force = f })
    for _, it in ipairs({ { "stone", 50 }, { "coal", 50 }, { "raw-fish", 20 } }) do storage.home.insert({ name = it[1], count = it[2] }) end
    storage.far = s.create_entity({ name = "iron-chest", position = { 100.5, 0.5 }, force = f })
    storage.far.insert({ name = "iron-plate", count = 60 })
    remote.call("ai-crew", "hire", "Rook", "nauvis", { x = 2, y = 2 })
  elseif t == 60 then
    remote.call("ai-crew", "order", nil, "Rook get 20 iron plate")
  elseif t == 3000 then
    local home, far = storage.home.get_item_count("iron-plate"), storage.far.get_item_count("iron-plate")
    log(string.format("t=3000: home %d iron plates, far chest %d, furnaces %d", home, far, furnaces()))
    check("fetched the plates from the far chest (" .. (60 - far) .. " taken)", far <= 40 and home >= 20)
    check("built no furnace for them", furnaces() == 0)
    remote.call("ai-crew", "test_machines", false)
    remote.call("ai-crew", "order", nil, "Rook get 20 copper plate")
  elseif t == 6000 then
    local st = remote.call("ai-crew", "status", "Rook")
    for _, l in ipairs(st.last_lines or {}) do log("  " .. l) end
    log(string.format("t=6000: furnaces %d, copper plates at home %d", furnaces(), storage.home.get_item_count("copper-plate")))
    check("machines off: no furnace for copper plates", furnaces() == 0)
    local fails = 0
    for _, c in ipairs(checks) do log((c[2] and "PASS " or "FAIL ") .. c[1]) if not c[2] then fails = fails + 1 end end
    log(fails == 0 and "ALL PASS" or (fails .. " FAILED"))
  end
end)
