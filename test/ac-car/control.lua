-- Headless check of long trips by car, and of fuel: an empty car beside home, coal in the chest, the only rock 120
-- tiles east. "Rook mine 10 stone": he fuels the car, drives there, mines, drives back. Then a stone furnace with no
-- fuel and none in stock but a coal patch near home: he mines coal and fuels it.
local out = {}
local function log(s) out[#out + 1] = s helpers.write_file("ac-car.txt", table.concat(out, "\n") .. "\n") end

script.on_event(defines.events.on_tick, function(ev)
  local t = ev.tick
  local s, f = game.surfaces.nauvis, game.forces.player
  if t == 5 then
    s.always_day = true
    game.map_settings.enemy_expansion.enabled = false
    for _, e in pairs(s.find_entities_filtered({ area = { { -150, -150 }, { 260, 150 } } })) do e.destroy() end
    for _, e in pairs(s.find_entities_filtered({ force = "enemy", area = { { -400, -400 }, { 400, 400 } } })) do e.destroy() end
    local tiles = {}
    for x = -150, 260 do for y = -150, 150 do tiles[#tiles + 1] = { name = "lab-dark-1", position = { x, y } } end end
    s.set_tiles(tiles)
    storage.chest = s.create_entity({ name = "iron-chest", position = { 0.5, 0.5 }, force = f })
    storage.chest.insert({ name = "coal", count = 10 })
    storage.car = s.create_entity({ name = "car", position = { 6, 6 }, force = f })
    storage.rock = s.create_entity({ name = "big-rock", position = { 120.5, 0.5 } })
    remote.call("ai-crew", "hire", "Rook", "nauvis", { x = 2, y = 2 })
    remote.call("ai-crew", "order", nil, "Rook mine 10 stone")
    storage.far = 0
  elseif t > 5 and t < 5400 then
    local st = remote.call("ai-crew", "status", "Rook")
    if st and st.riding == "car" then storage.drove = true end
    if storage.car.valid then storage.far = math.max(storage.far, storage.car.position.x) end
    if t == 5390 then
      local stone = storage.chest.get_item_count("stone")
      log(string.format("rides %d, car went as far as x=%.0f, stone home %d, Rook at %.0f,%.0f", st.rides, storage.far, stone,
        st.position.x, st.position.y))
      storage.checks = {
        { "drove the car on the long trip", storage.drove and storage.far > 95 },
        { "mined the far rock", not storage.rock.valid },
        { "brought the stone home (" .. stone .. ")", stone >= 10 },
      }
      -- now fuel: a furnace with none, no fuel in stock, coal ore near home
      storage.chest.remove_item({ name = "coal", count = 1000 })
      storage.car.get_fuel_inventory().clear()
      for x = -20, -16 do for y = -2, 2 do s.create_entity({ name = "coal", position = { x, y }, amount = 500 }) end end
      storage.furnace = s.create_entity({ name = "stone-furnace", position = { -6, 6 }, force = f })
      storage.furnace.insert({ name = "iron-ore", count = 50 })
    end
  elseif t == 12000 then
    local fuel = storage.furnace.get_fuel_inventory().get_item_count()
    table.insert(storage.checks, { "out of fuel: mined coal and fuelled the furnace (" .. fuel .. " in it)", fuel > 0 })
    local fails = 0
    for _, k in ipairs(storage.checks) do log((k[2] and "PASS " or "FAIL ") .. k[1]) if not k[2] then fails = fails + 1 end end
    log(fails == 0 and "ALL PASS" or (fails .. " FAILED"))
  end
end)
