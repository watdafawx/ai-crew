-- Headless measure of the crew's script cost on a big base: 2000 chests, 10000 belts (copper plates on some), 320
-- furnaces full of plates (half with a burner inserter putting them on a belt), all within 150 tiles; no armor or gun
-- anywhere. Game time per tick is profiled with no crew, then with 4 crew on a goal of iron plates (plan()'s far
-- search: fetched off the belts) and two sent for copper plates (in far chests). Then plan() and a hint alone.
-- The numbers go to ac-perf.txt (each tick's to ac-perf-ticks.txt); run.py holds them to loose bounds (profilers
-- can't be read from Lua). Here: the plates were fetched, and plan() still finds what's made.
local OUT, TICKS = "ac-perf.txt", "ac-perf-ticks.txt"
local BASE0, CREW0, CREW1, DIRECT = 300, 1700, 4700, 4710
local NAMES = { "Rook", "Ada", "Max", "Ivy" }
local prof, tprof -- (profilers can't be saved: a headless benchmark never saves)
local function log(s) helpers.write_file(OUT, { "", s, "\n" }, true) end

local function build(s, f)
  s.always_day = true
  game.map_settings.enemy_expansion.enabled = false
  for _, e in pairs(s.find_entities_filtered({ area = { { -400, -400 }, { 400, 400 } } })) do
    if e.type ~= "character" then e.destroy() end
  end
  local tiles = {}
  for x = -160, 160 do for y = -160, 160 do tiles[#tiles + 1] = { name = "lab-dark-1", position = { x, y } } end end
  s.set_tiles(tiles)
  -- rows of 7 tiles: chests at +0, belts at +3 (eastwards), output inserters at +4, furnaces at +5..+6
  local chests, belts, furnaces, inserters, plates = 0, 0, 0, 0, 0
  for k = 0, 39 do
    local y = -148 + 7 * k
    for j = 0, 49 do
      local c = s.create_entity({ name = "iron-chest", position = { -148 + 6 * j + 0.5, y + 0.5 }, force = f })
      chests = chests + 1
      if (k * 50 + j) % 10 == 0 then c.insert({ name = "copper-plate", count = 50 }) end
      if (k * 50 + j) % 10 == 5 then c.insert({ name = "coal", count = 20 }) end
    end
    for x = -125, 124 do
      local b = s.create_entity({ name = "transport-belt", position = { x + 0.5, y + 3.5 }, direction = defines.direction.east, force = f })
      belts = belts + 1
      if k % 4 == 0 and x % 3 == 0 then
        for i = 1, 2 do
          if b.get_transport_line(i).insert_at_back({ name = "copper-plate", count = 1 }) then plates = plates + 1 end
        end
      end
    end
    for j = 0, 7 do
      local x = -140 + 36 * j
      local fu = s.create_entity({ name = "stone-furnace", position = { x, y + 6 }, force = f })
      furnaces = furnaces + 1
      fu.insert({ name = "coal", count = 10 })
      fu.get_inventory(defines.inventory.furnace_source).insert({ name = "iron-ore", count = 50 })
      fu.get_inventory(defines.inventory.furnace_result).insert({ name = "iron-plate", count = 100 })
      if j % 2 == 0 then
        local i = s.create_entity({ name = "burner-inserter", position = { x + 0.5, y + 4.5 }, direction = defines.direction.south,
          force = f })
        i.pickup_target = i.pickup_target or fu
        i.insert({ name = "coal", count = 5 })
        if i.pickup_target == fu then inserters = inserters + 1 end
      end
    end
  end
  log(string.format("base: %d chests, %d belts (%d copper plates on them), %d furnaces, %d with an output inserter",
    chests, belts, plates, furnaces, inserters))
end

script.on_event(defines.events.on_tick, function(ev)
  local t = ev.tick
  if prof and tprof then -- (the game since our last handler: its update, ai-crew's handlers)
    prof.stop()
    tprof.stop()
    helpers.write_file(TICKS, { "", t, " ", tprof, "\n" }, true)
  end
  local s, f = game.surfaces.nauvis, game.forces.player
  if t == 5 then
    helpers.write_file(TICKS, "") -- (appended to below: emptied first)
    build(s, f)
  elseif t == BASE0 or t == CREW0 then
    prof = helpers.create_profiler(true)
    if t == CREW0 then
      for i, name in ipairs(NAMES) do
        local pos = s.find_non_colliding_position("character", { -10 + 6 * i, 1.5 }, 10, 0.5)
        remote.call("ai-crew", "hire", name, "nauvis", pos)
      end
      remote.call("ai-crew", "order", nil, "Rook goal 500 iron plate")
      remote.call("ai-crew", "order", nil, "Max get 100 copper plate")
      remote.call("ai-crew", "order", nil, "Ivy get 100 copper plate")
    end
  elseif t == BASE0 + 1000 then
    log({ "", "no crew, 1000 ticks: ", prof })
    prof = nil
  elseif t == CREW1 then
    log({ "", "crew, 3000 ticks: ", prof })
    prof = nil
    local got = 0
    for _, name in ipairs(NAMES) do
      local st = remote.call("ai-crew", "status", name)
      got = got + (st.collected or 0)
      log(string.format("  %s: doing %s, collected %d, at %.0f,%.0f", name, tostring(st.doing), st.collected or 0,
        st.position.x, st.position.y))
    end
    storage.checks = { { "plates fetched from afar meanwhile (" .. got .. ")", got > 0 } }
  elseif t == DIRECT then
    -- plan() alone, no far search skipped: bricks (none anywhere: everything searched), copper (in chests), iron
    -- (on belts, put there by the furnaces' inserters)
    local kinds = {}
    for _, it in ipairs({ "stone-brick", "copper-plate", "iron-plate" }) do
      local p = helpers.create_profiler()
      for _ = 1, 10 do kinds[it] = remote.call("ai-crew", "test_plan", "Rook", it, 50) end
      p.stop()
      log({ "", "plan " .. it .. " x10: ", p, " (" .. tostring(kinds[it]) .. ")" })
    end
    local p = helpers.create_profiler()
    for _ = 1, 5 do remote.call("ai-crew", "hint", nil) end
    p.stop()
    log({ "", "hint x5: ", p })
    local checks = storage.checks
    checks[#checks + 1] = { "no bricks to fetch", kinds["stone-brick"] ~= "collect" }
    checks[#checks + 1] = { "copper and iron plates to fetch", kinds["copper-plate"] == "collect" and kinds["iron-plate"] == "collect" }
    local fails = 0
    for _, c in ipairs(checks) do log((c[2] and "PASS " or "FAIL ") .. c[1]) if not c[2] then fails = fails + 1 end end
    log(fails == 0 and "ALL PASS" or (fails .. " FAILED"))
  end
  if prof then
    prof.restart()
    tprof = tprof or helpers.create_profiler(true)
    tprof.reset()
  else
    tprof = nil
  end
end)
