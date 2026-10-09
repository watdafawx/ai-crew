-- Headless check of the crew acting like a player: talking to them in normal chat (by name, "everyone", a name later
-- in the line, the nearest when nobody is named); building at a hand's pace, not all at once; looking round while
-- standing about; going over to the chest for what they take from it; notes, and a keep-out zone they take nothing
-- from; offering to deal with what runs short, and a "yes" in chat making it the goal.
local out, checks = {}, {}
local function log(s) out[#out + 1] = s helpers.write_file("ac-human.txt", table.concat(out, "\n") .. "\n") end
local function check(name, ok) checks[#checks + 1] = { name, ok and true or false } end
local function st(name) return remote.call("ai-crew", "status", name) end
local function hear(text) remote.call("ai-crew", "hear", nil, text) end

local steps = {
  [5] = function()
    local s, f = game.surfaces.nauvis, game.forces.player
    s.always_day = true
    game.map_settings.enemy_expansion.enabled = false
    for _, e in pairs(s.find_entities_filtered({ area = { { -100, -100 }, { 100, 100 } } })) do e.destroy() end
    for _, e in pairs(s.find_entities_filtered({ force = "enemy", area = { { -400, -400 }, { 400, 400 } } })) do e.destroy() end
    local tiles = {}
    for x = -100, 100 do for y = -100, 100 do tiles[#tiles + 1] = { name = "lab-dark-1", position = { x, y } } end end
    s.set_tiles(tiles)
    storage.chest = s.create_entity({ name = "iron-chest", position = { 0.5, 0.5 }, force = f })
    storage.chest.insert({ name = "iron-plate", count = 50 })
    storage.chest.insert({ name = "raw-fish", count = 20 }) -- (no fishing trips: the map round the test area is random)
    remote.call("ai-crew", "hire", "Rook", "nauvis", { x = 2, y = 2 })
    remote.call("ai-crew", "hire", "Mara", "nauvis", { x = 4, y = 2 })
  end,
  [60] = function()
    hear("Mara, craft 4 gears")
    local m = st("Mara")
    check("chat: \"Mara, craft 4 gears\" goes to Mara", m.doing and m.doing:find("^craft") and st("Rook").jobs == 0)
    hear("everyone stay")
    check("chat: \"everyone stay\" goes to all", st("Rook").mode == "stay" and st("Mara").mode == "stay")
    hear("roam, Rook")
    check("chat: a name later in the line", st("Rook").mode == "roam" and st("Mara").mode == "stay")
    hear("/kill everyone")
    hear("Rook follow")
    check("chat: commands ignored", st("Mara").mode == "stay" and st("Rook").mode == "follow")
    storage.plates = storage.chest.get_item_count("iron-plate")
    hear("get 5 iron plate")
  end,
  [600] = function()
    check("chat: no name, the nearest takes it (5 plates out of the chest)",
      storage.chest.get_item_count("iron-plate") <= storage.plates - 5)
  end,
  [700] = function()
    local s, f = game.surfaces.nauvis, game.forces.player
    storage.chest.insert({ name = "wooden-chest", count = 10 })
    for i = 1, 6 do s.create_entity({ name = "entity-ghost", inner_name = "wooden-chest", position = { -6 + i * 2, 8 }, force = f }) end
    storage.revived, storage.dirs = {}, {}
  end,
  [2400] = function()
    local r = storage.revived
    check("built all 6 ghosts", #r == 6)
    check("at a hand's pace (" .. (#r > 0 and (r[#r] - r[1]) or 0) .. " ticks for 6)", #r == 6 and r[#r] - r[1] >= 25)
    check("looks round while standing about (" .. table_size(storage.dirs) .. " directions)", table_size(storage.dirs) >= 2)
  end,
  [2500] = function()
    local s, f = game.surfaces.nauvis, game.forces.player
    for _, n in ipairs({ "Rook", "Mara" }) do
      local e = s.find_entities_filtered({ type = "character", position = st(n).position, radius = 0.3 })[1]
      e.teleport({ 34, 26 + (n == "Mara" and 2 or 0) })
    end
    storage.chest.insert({ name = "stone-furnace", count = 1 })
    s.create_entity({ name = "entity-ghost", inner_name = "stone-furnace", position = { 30, 30 }, force = f })
    storage.near_chest = 1e9
  end,
  [4500] = function()
    check("built the furnace far from the chest", storage.furnace_at ~= nil)
    for _, e in pairs(game.surfaces.nauvis.find_entities_filtered({ name = "stone-furnace" })) do e.destroy() end -- (unfuelled, it would
    -- send them off for fuel: not what the rest is about)
    check(string.format("went to the chest for it first (came within %.1f tiles)", storage.near_chest), storage.near_chest <= 10)
  end,
  [4600] = function()
    hear("crew keep out of my stuff")
    game.forces.player.recipes["wooden-chest"].enabled = false -- (only the chest has any: none made from wood)
    for _, n in ipairs({ "Rook", "Mara" }) do
      game.surfaces.nauvis.find_entities_filtered({ type = "character", position = st(n).position, radius = 0.3 })[1].get_main_inventory().clear()
    end
    storage.wood = storage.chest.get_item_count("wooden-chest")
    storage.ghost = game.surfaces.nauvis.create_entity({ name = "entity-ghost", inner_name = "wooden-chest", position = { 20, -25 },
      force = game.forces.player })
  end,
  [6600] = function()
    check("keep out: nothing taken from the chest there", storage.wood > 0 and storage.chest.get_item_count("wooden-chest") == storage.wood
      and storage.ghost.valid)
    hear("Rook, remember the north is for iron")
    local n = remote.call("ai-crew", "notes", nil) or {}
    check("notes: a keep-out zone and a note (" .. #n .. ")", #n == 2 and n[1].keep_out and n[2].text == "the north is for iron" and not n[2].keep_out)
    hear("crew forget")
    check("notes: forget clears them", #(remote.call("ai-crew", "notes", nil) or {}) == 0)
  end,
  [8600] = function()
    check("zone gone: the ghost gets built", not storage.ghost.valid)
  end,
  [8700] = function()
    local stats = game.forces.player.get_item_production_statistics("nauvis")
    stats.on_flow("iron-gear-wheel", -300) -- (300 gears used, none made)
    local offer = remote.call("ai-crew", "propose", nil)
    check("offers to deal with the gears running short", offer and offer.item == "iron-gear-wheel" and offer.count >= 100)
    hear("nah")
    check("\"nah\": no goal, the offer dropped", remote.call("ai-crew", "goal", nil) == nil and remote.call("ai-crew", "propose", nil) == nil)
    storage.declined_ok = true
  end,
  [8800] = function()
    local stats = game.forces.player.get_item_production_statistics("nauvis")
    game.forces.player.recipes["copper-cable"].enabled = true -- (locked at the start in 2.0)
    stats.on_flow("copper-cable", -200)
    local offer = remote.call("ai-crew", "propose", nil)
    check("the next offer skips what was turned down", offer and offer.item == "copper-cable")
    hear("sure")
    local g = remote.call("ai-crew", "goal", nil)
    check("\"sure\": the cable becomes the goal", g and g.item == "copper-cable" and g.count == offer.count)
  end,
}
local LAST = 8800

script.on_event(defines.events.script_raised_revive, function(ev)
  if storage.revived and ev.entity.name == "wooden-chest" then table.insert(storage.revived, ev.tick) end
  if ev.entity.name == "stone-furnace" then storage.furnace_at = ev.tick end
end)

script.on_event(defines.events.on_tick, function(ev)
  local f = steps[ev.tick]
  if f then f() end
  if storage.dirs and ev.tick % 30 == 0 then
    local m = st("Mara")
    local e = m and game.surfaces.nauvis.find_entities_filtered({ type = "character", position = m.position, radius = 0.3 })[1]
    if e and not m.doing then storage.dirs[e.direction] = true end
  end
  if storage.near_chest and not storage.furnace_at then
    for _, n in ipairs({ "Rook", "Mara" }) do
      local p = st(n).position
      storage.near_chest = math.min(storage.near_chest, math.sqrt((p.x - 0.5) ^ 2 + (p.y - 0.5) ^ 2))
    end
  end
  if ev.tick == LAST + 1 then
    local fails = 0
    for _, k in ipairs(checks) do log((k[2] and "PASS " or "FAIL ") .. k[1]) if not k[2] then fails = fails + 1 end end
    log(fails == 0 and "ALL PASS" or (fails .. " FAILED"))
  end
end)
