-- Headless check of hints: four powered gear assemblers with no iron plates. Rook points out they're starved of iron
-- plates; asked again at once he doesn't repeat it; after 5 minutes with nothing done he suggests research to start.
local out, checks = {}, {}
local function log(s) out[#out + 1] = s helpers.write_file("ac-hint.txt", table.concat(out, "\n") .. "\n") end
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
    s.create_entity({ name = "electric-energy-interface", position = { 20, -8 }, force = f })
    for _, x in ipairs({ 16.5, 24.5 }) do s.create_entity({ name = "medium-electric-pole", position = { x, -4.5 }, force = f }) end
    for _, x in ipairs({ 15.5, 18.5, 21.5, 24.5 }) do
      s.create_entity({ name = "assembling-machine-1", position = { x, -1.5 }, force = f, recipe = "iron-gear-wheel" })
    end
    remote.call("ai-crew", "hire", "Rook", "nauvis", { x = 2, y = 2 })
  elseif t == 600 then
    local k = remote.call("ai-crew", "hint", nil)
    log("hint at 600: " .. tostring(k))
    check("points out the gear machines starved of plates", k == "starved:iron-gear-wheel")
    local again = remote.call("ai-crew", "hint", nil)
    check("doesn't repeat it (" .. tostring(again) .. ")", again == nil)
  elseif t == 18700 then
    local k = remote.call("ai-crew", "hint", nil)
    log("hint at 18700: " .. tostring(k))
    check("after 5 minutes with nothing done: research to start", k and k:find("^research:"))
    local said = false
    for _, e in ipairs(remote.call("ai-crew", "memory", nil) or {}) do if e.text:find("pointed out") then said = true end end
    check("remembered what was pointed out", said)
    local fails = 0
    for _, c in ipairs(checks) do log((c[2] and "PASS " or "FAIL ") .. c[1]) if not c[2] then fails = fails + 1 end end
    log(fails == 0 and "ALL PASS" or (fails .. " FAILED"))
  end
end)
