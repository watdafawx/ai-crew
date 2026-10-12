-- Headless check of "backed up": four copper drills drop onto belts that end there (soon full, as a belt waiting on
-- what's downstream is), four iron drills drop onto bare ground (soon blocked, nothing takes their ore). The hint is
-- about the iron drills only: a full belt is no news.
local out, checks = {}, {}
local function log(s) out[#out + 1] = s helpers.write_file("ac-backed.txt", table.concat(out, "\n") .. "\n") end
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
    for x = -100, 100 do for y = -100, 100 do tiles[#tiles + 1] = { name = "lab-dark-1", position = { x, y } } end end
    s.set_tiles(tiles)
    storage.drills = {}
    for i = 0, 3 do
      for _, g in ipairs({ { ore = "copper-ore", x = 10, belt = true }, { ore = "iron-ore", x = -20 } }) do
        local x, y = g.x + i * 3, -10
        for dx = 0, 1 do for dy = 0, 1 do
          s.create_entity({ name = g.ore, position = { x + dx + 0.5, y + dy + 0.5 }, amount = 1000 })
        end end
        local d = s.create_entity({ name = "burner-mining-drill", position = { x + 1, y + 1 }, direction = defines.direction.north, force = f })
        d.get_fuel_inventory().insert({ name = "coal", count = 20 })
        if g.belt then
          s.create_entity({ name = "transport-belt", position = d.drop_position, direction = defines.direction.east, force = f })
        end
        storage.drills[#storage.drills + 1] = { d = d, ore = g.ore }
      end
    end
    remote.call("ai-crew", "hire", "Rook", "nauvis", { x = 2, y = 2 })
  elseif t == 3000 then
    local st = {}
    for _, r in ipairs(storage.drills) do
      local name
      for k, v in pairs(defines.entity_status) do if v == r.d.status then name = k end end
      st[r.ore] = (st[r.ore] and st[r.ore] .. "," or "") .. tostring(name)
    end
    log("copper (belts): " .. st["copper-ore"])
    log("iron (ground): " .. st["iron-ore"])
    check("the drills on belts are waiting on full belts", not st["copper-ore"]:find("working"))
    local keys = {}
    for _ = 1, 4 do keys[#keys + 1] = remote.call("ai-crew", "hint", nil) or "-" end
    log("hints: " .. table.concat(keys, " "))
    local all = table.concat(keys, " ")
    check("points out the iron drills with nowhere to put their ore", all:find("backed:iron-ore", 1, true))
    check("not the copper drills on full belts", not all:find("backed:copper-ore", 1, true))
    local fails = 0
    for _, c in ipairs(checks) do log((c[2] and "PASS " or "FAIL ") .. c[1]) if not c[2] then fails = fails + 1 end end
    log(fails == 0 and "ALL PASS" or (fails .. " FAILED"))
  end
end)
