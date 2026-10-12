-- Headless check that the crew match the player. A stand-in character plays the owner (test_owner: no player
-- headless), Rook follows it. Reach: the stand-in gets +10 reach, build, resource reach, drop and pickup (as far reach
-- sets them): Rook has the same on hire, a change follows within 5 s, the force's reach bonus adds on top; it builds a
-- ghost 16 tiles off and mines stone 11 tiles off without a step. Speed: 10 gears hand-crafted ~5x faster with the
-- force's manual crafting speed at +4 than at 0; 5 stone mined ~2x faster with manual mining speed at +1. Following:
-- the stand-in walks back and forth while Rook builds a row of ghosts 34 tiles off, their items in the stand-in's
-- pockets: all built in one go, no walking back to it (nor off with it) till the row's done.
local out, checks = {}, {}
local function log(s) out[#out + 1] = s helpers.write_file("ac-parity.txt", table.concat(out, "\n") .. "\n") end
local function check(name, ok) checks[#checks + 1] = { name, ok and true or false } end
local BONUSES = { "character_build_distance_bonus", "character_reach_distance_bonus",
  "character_resource_reach_distance_bonus", "character_item_drop_distance_bonus",
  "character_item_pickup_distance_bonus" }
local ROW = { "wooden-chest", "iron-chest", "small-electric-pole", "stone-furnace", "transport-belt", "inserter",
  "pipe", "burner-inserter" }
local ROW_Y = -30.5

local function rook() return game.surfaces.nauvis.find_entities_filtered({ name = "crew-character" })[1] end
local function d(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end
local function status() return remote.call("ai-crew", "status", "Rook") end
local function doing(kind) local st = status() return st.doing and st.doing:find("^" .. kind) ~= nil end

local function finish()
  local fails = 0
  for _, k in ipairs(checks) do log((k[2] and "PASS " or "FAIL ") .. k[1]) if not k[2] then fails = fails + 1 end end
  log(fails == 0 and "ALL PASS" or (fails .. " FAILED"))
  storage.stage = "done"
end

script.on_event(defines.events.on_tick, function(ev)
  local t = ev.tick
  local s, f = game.surfaces.nauvis, game.forces.player
  local S = storage
  if t == 5 then
    s.always_day = true
    game.map_settings.enemy_expansion.enabled = false
    for _, e in pairs(s.find_entities_filtered({ area = { { -150, -150 }, { 150, 150 } } })) do e.destroy() end
    -- (no ore, trees, fish or biters but ours: the map round the test area is random)
    local junk = { "unit", "unit-spawner", "turret", "resource", "tree", "fish" }
    for _, e in pairs(s.find_entities_filtered({ type = junk, area = { { -400, -400 }, { 400, 400 } } })) do
      e.destroy()
    end
    local tiles = {}
    for x = -150, 150 do for y = -150, 150 do tiles[#tiles + 1] = { name = "lab-dark-1", position = { x, y } } end end
    s.set_tiles(tiles)
    local chest = s.create_entity({ name = "iron-chest", position = { 0.5, 0.5 }, force = f })
    chest.insert({ name = "raw-fish", count = 20 }) -- (no fishing trips)
    S.boss = s.create_entity({ name = "character", position = { 2, 12 }, force = f })
    for _, k in ipairs(BONUSES) do S.boss[k] = 10 end
    remote.call("ai-crew", "test_owner", S.boss)
    remote.call("ai-crew", "hire", "Rook", "nauvis", { x = 0, y = 12 }, "player", nil, "follow")
    local e, proto = rook(), prototypes.entity["crew-character"]
    local same = true
    for _, k in ipairs(BONUSES) do same = same and e[k] == 10 end
    check("hired with the stand-in's bonuses (+10 reach, build, resource reach, drop, pickup)", same)
    check(string.format("its reach counts them: reach %.1f build %.1f resource %.1f (prototype %.1f %.1f %.1f)",
      e.reach_distance, e.build_distance, e.resource_reach_distance, proto.reach_distance, proto.build_distance,
      proto.reach_resource_distance), e.reach_distance == proto.reach_distance + 10
      and e.build_distance == proto.build_distance + 10
      and math.abs(e.resource_reach_distance - proto.reach_resource_distance - 10) < 0.01)
    S.base_reach = proto.reach_distance
    S.boss.character_reach_distance_bonus = 12
    f.character_reach_distance_bonus = 3
    S.stage, S.at = "copy", t
  elseif S.stage == "copy" and t == S.at + 320 then
    local e = rook()
    check(string.format("a changed bonus follows within 5 s; the force's adds (reach %.1f = %.1f + 12 + 3)",
      e.reach_distance, S.base_reach), e.character_reach_distance_bonus == 12 and e.reach_distance == S.base_reach + 15)
    f.character_reach_distance_bonus = 0
    -- a ghost 16 tiles off (build distance 10 + 10), its item in Rook's pockets
    e.teleport({ 0, 12 })
    S.boss.teleport({ 2, 12 })
    S.from = { x = e.position.x, y = e.position.y }
    e.insert({ name = "wooden-chest", count = 1 })
    s.create_entity({ name = "entity-ghost", inner_name = "wooden-chest", position = { 0.5, 28.5 }, force = f })
    S.stage, S.at, S.moved = "build", t, 0
  elseif S.stage == "build" then
    S.moved = math.max(S.moved, d(rook().position, S.from))
    local built = s.find_entities_filtered({ name = "wooden-chest", position = { 0.5, 28.5 }, radius = 0.5 })[1]
    if built or t > S.at + 900 then
      check(string.format("built the ghost 16 tiles off from where it stood (moved %.1f tiles)", S.moved),
        built and S.moved < 1.5)
      built.destroy()
      s.create_entity({ name = "stone", position = { 11.5, 12.5 }, amount = 500 })
      remote.call("ai-crew", "order", nil, "Rook mine 5 stone")
      S.stage, S.at, S.moved = "mine", t, 0
    end
  elseif S.stage == "mine" or S.stage == "mine2" then
    S.moved = math.max(S.moved, d(rook().position, S.from))
    if t > S.at + 20 and not doing("mine") or t > S.at + 2400 then
      local ticks = t - S.at
      local got = S.boss.get_item_count("stone") + rook().get_item_count("stone")
      if S.stage == "mine" then
        check(string.format("mined 5 stone 11 tiles off from where it stood (got %d, moved %.1f tiles, %d ticks)", got,
          S.moved, ticks), got >= 5 and S.moved < 1.5)
        S.mine0 = ticks
        f.manual_mining_speed_modifier = 1
        S.stage, S.next, S.order = "idle", "mine2", "Rook mine 5 stone"
      else
        check(string.format("mining speed +1: 5 stone in %d ticks, %d at +0 (%.2fx)", ticks, S.mine0, S.mine0 / ticks),
          got >= 10 and S.mine0 / ticks > 1.6 and S.mine0 / ticks < 2.4)
        f.manual_mining_speed_modifier = 0
        rook().insert({ name = "iron-plate", count = 40 })
        f.manual_crafting_speed_modifier = 0
        S.stage, S.next, S.order = "idle", "craft", "Rook craft 10 iron-gear-wheel"
      end
    end
  elseif S.stage == "idle" then -- (the last job's delivery done first: then the next order, timed from now)
    if status().jobs == 0 then
      remote.call("ai-crew", "order", nil, S.order)
      S.stage, S.at, S.c0, S.c1 = S.next, t, nil, nil
    end
  elseif S.stage == "craft" or S.stage == "craft2" then
    local q = rook().crafting_queue_size
    if q > 0 and not S.c0 then S.c0 = t end
    if S.c0 and q == 0 and not S.c1 then S.c1 = t end
    if S.c1 or t > S.at + 1800 then
      local ticks = S.c1 and S.c0 and S.c1 - S.c0 or 99999
      if S.stage == "craft" then
        log("10 gears at crafting speed +0: " .. ticks .. " ticks")
        S.craft0 = ticks
        f.manual_crafting_speed_modifier = 4
        S.stage, S.next, S.order = "idle", "craft2", "Rook craft 10 iron-gear-wheel"
      else
        check(string.format("crafting speed +4: 10 gears in %d ticks, %d at +0 (%.2fx)", ticks, S.craft0,
          S.craft0 / ticks), S.craft0 / ticks > 4 and S.craft0 / ticks < 6)
        f.manual_crafting_speed_modifier = 0
        for _, k in ipairs(BONUSES) do S.boss[k] = 0 end -- (a plain reach for the walk: as Rook will have in 5 s)
        local inv = S.boss.get_main_inventory()
        for _, n in ipairs(ROW) do inv.insert({ name = n, count = 10 }) end
        S.stage, S.at = "settle", t
      end
    end
  elseif S.stage == "settle" and t == S.at + 400 then
    -- a row of ghosts 34 tiles north; the stand-in walks east and west along y = 4 meanwhile, x -30..30
    S.boss.teleport({ 0, 4 })
    rook().teleport({ 2, 6 })
    for i, n in ipairs(ROW) do
      s.create_entity({ name = "entity-ghost", inner_name = n, position = { -15 + i * 4 + 0.5, ROW_Y }, force = f })
    end
    S.stage, S.at, S.near, S.worst, S.walk_at = "follow", t, false, 0, t
  elseif S.stage == "follow" then
    local b = S.boss
    local leg = math.floor((t - S.walk_at + 200) / 400) % 2 -- (east 200 ticks, then west and east 400 each)
    b.walking_state = { walking = true, direction = leg == 0 and defines.direction.east or defines.direction.west }
    local e = rook()
    local off = math.abs(e.position.y - ROW_Y)
    if doing("build") then
      if off < 12 then S.near = true end
      if S.near then S.worst = math.max(S.worst, off) end
    end
    if t % 60 == 0 then
      log(string.format("t=%d rook (%.1f,%.1f) stand-in (%.1f,%.1f) %s", t, e.position.x, e.position.y, b.position.x,
        b.position.y, tostring(status().doing)))
    end
    local left = s.count_entities_filtered({ type = "entity-ghost" })
    if left == 0 and status().jobs == 0 or t > S.at + 4000 then
      check(string.format("following: the row of %d ghosts built (%d left, %d ticks)", #ROW, left, t - S.at), left == 0)
      check(string.format("no walking back to the stand-in mid-job: at most %.1f tiles off the row once there",
        S.worst),
        S.near and S.worst < 16)
      b.walking_state = { walking = false, direction = defines.direction.north }
      finish()
    end
  end
end)
