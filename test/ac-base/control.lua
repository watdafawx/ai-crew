-- Headless check of "Mark base": the base pinned at home, where a belt runs east to x=300 (so the base reaches that
-- far), 60 iron plates in a chest at x=280 by the belt (past the 160 tiles a crew member looks without a base), 40
-- copper plates in a chest 150 tiles west with nothing joining it to the base. The base makes both (production
-- statistics), stone, coal and ore at home could make a furnace. "get 20 iron plate": fetched from x=280. "get 20
-- copper plate": the west chest is out of the base, so none taken, no furnace either. Marked again at the pin: forgotten.
local out, checks = {}, {}
local function log(s) out[#out + 1] = s helpers.write_file("ac-base.txt", table.concat(out, "\n") .. "\n") end
local function check(name, ok) checks[#checks + 1] = { name, ok and true or false } end
local function furnaces() return game.surfaces.nauvis.count_entities_filtered({ type = "furnace" }) end

script.on_event(defines.events.on_tick, function(ev)
  local t = ev.tick
  local s, f = game.surfaces.nauvis, game.forces.player
  if t == 5 then
    s.always_day = true
    game.map_settings.enemy_expansion.enabled = false
    s.request_to_generate_chunks({ 0, 0 }, 12)
    s.force_generate_chunk_requests()
    for _, e in pairs(s.find_entities_filtered({ area = { { -350, -150 }, { 350, 150 } } })) do e.destroy() end
    for _, e in pairs(s.find_entities_filtered({ force = "enemy", area = { { -500, -500 }, { 500, 500 } } })) do e.destroy() end
    local tiles = {}
    for x = -200, 320 do for y = -40, 40 do tiles[#tiles + 1] = { name = "lab-dark-1", position = { x, y } } end end
    s.set_tiles(tiles)
    for x = 12, 15 do for y = -6, -3 do
      s.create_entity({ name = "iron-ore", position = { x + 0.5, y + 0.5 }, amount = 500 })
      s.create_entity({ name = "copper-ore", position = { x + 0.5, y - 6.5 }, amount = 500 })
    end end
    storage.home = s.create_entity({ name = "iron-chest", position = { 0.5, 0.5 }, force = f })
    for _, it in ipairs({ { "stone", 50 }, { "coal", 50 }, { "raw-fish", 20 } }) do storage.home.insert({ name = it[1], count = it[2] }) end
    for x = 2, 300 do
      s.create_entity({ name = "transport-belt", position = { x + 0.5, 3.5 }, direction = defines.direction.east, force = f })
    end
    storage.far = s.create_entity({ name = "iron-chest", position = { 280.5, 5.5 }, force = f })
    storage.far.insert({ name = "iron-plate", count = 60 })
    storage.west = s.create_entity({ name = "iron-chest", position = { -150.5, 0.5 }, force = f })
    storage.west.insert({ name = "copper-plate", count = 40 })
    local stats = f.get_item_production_statistics(s)
    for _, it in ipairs({ "iron-plate", "copper-plate" }) do stats.on_flow(it, 500) end
    remote.call("ai-crew", "hire", "Rook", "nauvis", { x = 2, y = 1 })
    remote.call("ai-crew", "mark_base", nil, "nauvis", { x = 0, y = 0 })
  elseif t == 60 then
    local b = remote.call("ai-crew", "base", nil)
    log(string.format("t=60: base %s chunks, filling %s", tostring(b and b.chunks), tostring(b and b.filling)))
    check("the base reaches along the belt (" .. tostring(b and b.chunks) .. " chunks)", b and (b.chunks or 0) >= 10)
    remote.call("ai-crew", "order", nil, "Rook get 20 iron plate")
  elseif t == 7000 then
    local far = storage.far.get_item_count("iron-plate")
    local carried = 0
    for _, c in pairs(s.find_entities_filtered({ type = "character" })) do carried = carried + c.get_item_count("iron-plate") end
    log(string.format("t=7000: far chest %d, home %d, carried %d, furnaces %d", far, storage.home.get_item_count("iron-plate"), carried, furnaces()))
    check("fetched iron plates from the chest 280 out, in the base (" .. (60 - far) .. " taken)", far <= 40)
    check("built no furnace for iron plates", furnaces() == 0)
    remote.call("ai-crew", "order", nil, "Rook get 20 copper plate")
  elseif t == 10000 then
    local st = remote.call("ai-crew", "status", "Rook")
    for _, l in ipairs(st.last_lines or {}) do log("  " .. l) end
    log(string.format("t=10000: west chest %d copper, furnaces %d", storage.west.get_item_count("copper-plate"), furnaces()))
    check("left the chest outside the base alone", storage.west.get_item_count("copper-plate") == 40)
    check("built no furnace for copper plates", furnaces() == 0)
    local kept = remote.call("ai-crew", "mark_base", nil, "nauvis", { x = 3, y = 2 })
    check("marked again by the pin: forgotten", kept == false and remote.call("ai-crew", "base", nil) == nil)
    local fails = 0
    for _, c in ipairs(checks) do log((c[2] and "PASS " or "FAIL ") .. c[1]) if not c[2] then fails = fails + 1 end end
    log(fails == 0 and "ALL PASS" or (fails .. " FAILED"))
  end
end)
