-- Headless check: an armed crew member shoots the biters that come, and stops shooting once they are dead; it also
-- stops when its target leaves its range (it used to keep firing at the last spot forever, not back to work)
local out = {}
local function log(s) out[#out + 1] = s helpers.write_file("ac-shoot.txt", table.concat(out, "\n") .. "\n") end

local function rook() return remote.call("ai-crew", "status", "Rook") end
local function body()
  local st = rook()
  return st and game.surfaces.nauvis.find_entities_filtered({ type = "character", position = st.position, radius = 1 })[1]
end
local function shooting()
  local e = body()
  return e and e.shooting_state.state ~= defines.shooting.not_shooting
end

script.on_nth_tick(5, function(ev)
  if ev.tick ~= 5 then return end
  local s, f = game.surfaces.nauvis, game.forces.player
  s.always_day = true
  game.forces.enemy.set_evolution_factor(0, s)
  game.map_settings.enemy_expansion.enabled = false
  for _, e in pairs(s.find_entities_filtered({ area = { { -100, -100 }, { 100, 100 } } })) do e.destroy() end
  local tiles = {}
  for x = -100, 100 do for y = -100, 100 do tiles[#tiles + 1] = { name = "lab-dark-1", position = { x, y } } end end
  s.set_tiles(tiles)
  for _, e in pairs(s.find_entities_filtered({ force = "enemy", area = { { -400, -400 }, { 400, 400 } } })) do e.destroy() end
  remote.call("ai-crew", "hire", "Rook", "nauvis", { x = 2, y = 2 })
  local e = body()
  e.get_inventory(defines.inventory.character_guns).insert({ name = "submachine-gun", count = 1 })
  e.get_inventory(defines.inventory.character_ammo).insert({ name = "firearm-magazine", count = 200 })
  for i = 1, 3 do s.create_entity({ name = "small-biter", position = { 12 + i, 2 }, force = "enemy" }) end
  storage.phase = "kill"
end)

script.on_event(defines.events.on_tick, function()
  if storage.done or not storage.phase or not shooting() then return end
  if storage.phase == "kill" then storage.shot = true elseif storage.phase == "far" then storage.shot_far = true end
end)

script.on_nth_tick(60, function(ev)
  if storage.done or not storage.phase then return end
  local s = game.surfaces.nauvis
  local biters = s.count_entities_filtered({ type = "unit", force = "enemy" })
  log(string.format("t=%d %s: biters %d shooting %s", ev.tick, storage.phase, biters, tostring(shooting())))
  if storage.phase == "kill" then
    if biters == 0 and ev.tick >= 600 then
      storage.killed, storage.stopped_after_kill = true, not shooting()
      -- one held still in range: shot at, then moved out of its range
      local b = s.create_entity({ name = "small-biter", position = { 12, -6 }, force = "enemy" })
      b.disabled_by_script, b.destructible = true, false
      storage.far, storage.phase, storage.t = b, "far", ev.tick
    elseif ev.tick > 3000 then
      storage.phase = "end"
    end
  elseif storage.phase == "far" then
    if storage.shot_far and not storage.moved then
      storage.far.teleport({ 70, -6 })
      storage.moved = ev.tick
    elseif storage.moved and ev.tick >= storage.moved + 120 then
      storage.stopped_far = not shooting()
      storage.phase = "end"
    elseif ev.tick > storage.t + 1200 then
      storage.phase = "end"
    end
  elseif storage.phase == "end" then
    local checks = {
      { "shot at the biters", storage.shot },
      { "killed them", storage.killed },
      { "stopped shooting once they were dead", storage.stopped_after_kill },
      { "shot at one held in range", storage.shot_far },
      { "stopped shooting once it left its range", storage.stopped_far },
    }
    local fails = 0
    for _, k in ipairs(checks) do log((k[2] and "PASS " or "FAIL ") .. k[1]) if not k[2] then fails = fails + 1 end end
    log(fails == 0 and "ALL PASS" or (fails .. " FAILED"))
    storage.done = true
  end
end)
