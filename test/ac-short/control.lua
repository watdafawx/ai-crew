-- Headless check that stock isn't a shortage: the base "used" 500 assembling machine 2 more than it made in 10 minutes
-- (placed from 1000 in a chest at home, as you place machines made long ago) and 300 pipes (none in stock). With the
-- ingredients for both at home, a roamer's own batch is pipes, never assembling machines, and so is the offer.
local out, checks = {}, {}
local function log(s) out[#out + 1] = s helpers.write_file("ac-short.txt", table.concat(out, "\n") .. "\n") end
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
    f.recipes.pipe.enabled = true
    storage.home = s.create_entity({ name = "steel-chest", position = { 0.5, 0.5 }, force = f })
    storage.home.insert({ name = "assembling-machine-2", count = 1000 })
    storage.parts = s.create_entity({ name = "steel-chest", position = { 2.5, 0.5 }, force = f })
    for _, it in ipairs({ { "steel-plate", 50 }, { "electronic-circuit", 50 }, { "iron-gear-wheel", 100 },
      { "assembling-machine-1", 20 }, { "iron-plate", 200 }, { "raw-fish", 20 } }) do
      storage.parts.insert({ name = it[1], count = it[2] })
    end
    local stats = f.get_item_production_statistics(s)
    stats.on_flow("assembling-machine-2", -500)
    stats.on_flow("pipe", -300)
    remote.call("ai-crew", "hire", "Rook", "nauvis", { x = 3, y = 3 }, nil, nil, "roam")
  elseif t == 3000 then
    local st = remote.call("ai-crew", "status", "Rook")
    local asm, pipes = 0, 0
    for _, ch in ipairs({ storage.home, storage.parts }) do
      asm, pipes = asm + ch.get_item_count("assembling-machine-2"), pipes + ch.get_item_count("pipe")
    end
    asm = asm + (st.inventory["assembling-machine-2"] or 0)
    pipes = pipes + (st.inventory.pipe or 0)
    for _, l in ipairs(st.last_lines or {}) do log("  " .. l) end
    log("mode " .. tostring(st.mode) .. ", doing " .. tostring(st.doing) .. ", need " .. tostring(st.need) .. ", goal " .. serpent.line(remote.call("ai-crew", "goal", nil)))
    log(string.format("t=3000: assembling machine 2 %d, pipes %d, asm1 left %d", asm, pipes, storage.parts.get_item_count("assembling-machine-1")))
    check("made no assembling machine 2 (1000 in stock)", asm == 1000 and storage.parts.get_item_count("assembling-machine-1") == 20)
    check("hand-crafted pipes instead (" .. pipes .. ")", pipes >= 5)
    local stats = f.get_item_production_statistics(s)
    for _, n in ipairs({ "pipe", "assembling-machine-2" }) do
      local function fl(c) return stats.get_flow_count({ name = n, category = c, precision_index = defines.flow_precision_index.ten_minutes, count = true }) end
      log(string.format("%s: in %s out %s, output_counts %s", n, fl("input"), fl("output"), tostring(stats.output_counts[n])))
    end
    local offer = remote.call("ai-crew", "propose", nil)
    log("offer: " .. tostring(offer and offer.item))
    check("the offer isn't assembling machine 2", not (offer and offer.item == "assembling-machine-2"))
    local fails = 0
    for _, c in ipairs(checks) do log((c[2] and "PASS " or "FAIL ") .. c[1]) if not c[2] then fails = fails + 1 end end
    log(fails == 0 and "ALL PASS" or (fails .. " FAILED"))
  end
end)
