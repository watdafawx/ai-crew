-- Headless check: a chest with a submachine gun and magazines at home. Small biters walk up: the crew member arms
-- itself (armor, gun, ammo) and shoots them. Then "attack": it destroys a spawner and a worm 40 tiles out, falling back when hurt.
-- Then it dies, and is back a minute later.
local out = {}
local function log(s) out[#out + 1] = s helpers.write_file("ac-fight.txt", table.concat(out, "\n") .. "\n") end

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
  local chest = s.create_entity({ name = "iron-chest", position = { 0.5, 0.5 }, force = f })
  chest.insert({ name = "submachine-gun", count = 1 })
  chest.insert({ name = "firearm-magazine", count = 400 })
  chest.insert({ name = "heavy-armor", count = 1 })
  chest.insert({ name = "raw-fish", count = 20 })
  for _, e in pairs(s.find_entities_filtered({ force = "enemy", area = { { -400, -400 }, { 400, 400 } } })) do e.destroy() end
  remote.call("ai-crew", "hire", "Rook", "nauvis", { x = 2, y = 2 })
  for i = 1, 3 do s.create_entity({ name = "small-biter", position = { 14 + i, 2 }, force = "enemy" }) end
  storage.phase = "defend"
end)

script.on_nth_tick(600, function(ev)
  if storage.done or not storage.phase then return end
  local s = game.surfaces.nauvis
  local st = remote.call("ai-crew", "status", "Rook")
  local near = { { -100, -100 }, { 100, 100 } }
  local biters = s.count_entities_filtered({ type = "unit", force = "enemy", area = near })
  local nests = s.count_entities_filtered({ type = { "unit-spawner", "turret" }, force = "enemy", area = near })
  log(string.format("t=%d %s: biters %d nests %d; Rook %s hp %s doing %s fighting %s retreat %s", ev.tick, storage.phase,
    biters, nests, st and "up" or "down", st and tostring(st.health) or "-", st and tostring(st.doing) or "-",
    st and tostring(st.fighting) or "-", st and tostring(st.retreat) or "-"))
  if storage.phase == "defend" and ev.tick >= 1800 then
    storage.killed_first = biters == 0
    s.create_entity({ name = "biter-spawner", position = { 40, -10 }, force = "enemy" })
    s.create_entity({ name = "small-worm-turret", position = { 36, -16 }, force = "enemy" })
    remote.call("ai-crew", "order", nil, "Rook attack")
    storage.phase = "attack"
  elseif storage.phase == "attack" and (nests == 0 or ev.tick >= 30000) then
    storage.cleared = nests == 0
    storage.first_unit = st and st.unit
    local rook = st and s.find_entities_filtered({ type = "character", position = st.position, radius = 1 })[1]
    if rook then rook.die("enemy") end
    storage.died_at, storage.phase = ev.tick, "respawn"
  elseif storage.phase == "respawn" and ev.tick >= storage.died_at + 4200 then
    local back = remote.call("ai-crew", "status", "Rook")
    local checks = {
      { "armed itself and killed the biters that came", storage.killed_first },
      { "spawner and worm destroyed", storage.cleared },
      { "Rook back after dying, a new body", back ~= nil and back.unit ~= storage.first_unit },
    }
    local fails = 0
    for _, k in ipairs(checks) do log((k[2] and "PASS " or "FAIL ") .. k[1]) if not k[2] then fails = fails + 1 end end
    log(fails == 0 and "ALL PASS" or (fails .. " FAILED"))
    storage.done = true
  end
end)
