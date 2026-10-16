-- Headless check of ghosts wanting a better quality: an uncommon assembling machine 2's ghost by home, 100 normal ones
-- in a chest and the ingredients to hand-craft more. "build": nothing is crafted (the hand makes only normal ones, and
-- a need for the item by name made normal ones for ever), the ghost stays, and Rook says it's out of uncommon ones.
local out, checks = {}, {}
local function log(s) out[#out + 1] = s helpers.write_file("ac-quality.txt", table.concat(out, "\n") .. "\n") end
local function check(name, ok) checks[#checks + 1] = { name, ok and true or false } end

script.on_event(defines.events.on_tick, function(ev)
  local t = ev.tick
  local s, f = game.surfaces.nauvis, game.forces.player
  if t == 5 then
    s.always_day = true
    game.map_settings.enemy_expansion.enabled = false
    for _, e in pairs(s.find_entities_filtered({ area = { { -100, -100 }, { 100, 100 } } })) do e.destroy() end
    for _, e in pairs(s.find_entities_filtered({ force = "enemy", area = { { -400, -400 }, { 400, 400 } } })) do e.destroy() end
    local tiles = {}
    for x = -60, 60 do for y = -60, 60 do tiles[#tiles + 1] = { name = "lab-dark-1", position = { x, y } } end end
    s.set_tiles(tiles)
    f.recipes["assembling-machine-2"].enabled = true
    storage.home = s.create_entity({ name = "steel-chest", position = { 0.5, 0.5 }, force = f })
    for _, it in ipairs({ { "assembling-machine-2", 100 }, { "steel-plate", 50 }, { "electronic-circuit", 50 },
      { "iron-gear-wheel", 100 }, { "assembling-machine-1", 20 }, { "raw-fish", 20 } }) do
      storage.home.insert({ name = it[1], count = it[2] })
    end
    storage.ghost = s.create_entity({ name = "entity-ghost", inner_name = "assembling-machine-2", quality = "uncommon",
      position = { 10.5, 0.5 }, force = f })
    remote.call("ai-crew", "hire", "Rook", "nauvis", { x = 3, y = 3 })
  elseif t == 60 then
    remote.call("ai-crew", "order", nil, "Rook build")
  elseif t == 2400 then
    local st = remote.call("ai-crew", "status", "Rook")
    local said = false
    for _, l in ipairs(st.last_lines or {}) do
      log("  " .. l)
      if l:find("uncommon assembling machine 2", 1, true) then said = true end
    end
    local asm2 = storage.home.get_item_count("assembling-machine-2") + (st.inventory["assembling-machine-2"] or 0)
    log(string.format("t=2400: normal asm2 %d, asm1 %d, need %s, ghost %s", asm2, storage.home.get_item_count("assembling-machine-1"),
      tostring(st.need), tostring(storage.ghost.valid)))
    check("crafted no assembling machine 2 (" .. asm2 .. ")", asm2 == 100 and storage.home.get_item_count("assembling-machine-1") == 20)
    check("no need for one", st.need == nil)
    check("the ghost still waits", storage.ghost.valid)
    check("said it's out of uncommon ones", said)
    local fails = 0
    for _, c in ipairs(checks) do log((c[2] and "PASS " or "FAIL ") .. c[1]) if not c[2] then fails = fails + 1 end end
    log(fails == 0 and "ALL PASS" or (fails .. " FAILED"))
  end
end)
