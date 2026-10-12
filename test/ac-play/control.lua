-- Real client (run_gui.py ac-play): the newest behaviours with player 1's own character, no stand-ins. Two crew hired
-- through the window (Hire, a name typed in the box) start out roaming, the player's setting. The player's far reach
-- (+10 reach, build, resource reach, drop, pickup) on the crew within 5 s. Small biters go for the player: the armed
-- crew come, keep up when the player is teleported 30 tiles, kill them, then roam again. A roamer swaps an
-- assembling machine 1 for the 2 in the player's pockets, recipe kept. Juno, following, builds a row of ghosts 30
-- tiles off from the player's pockets while the player hops between two spots every second: all of it, no walking
-- back to the player mid-job. Results in ac-play-result.txt, screenshots ac-play-*.png.
script.on_init(function()
  local fp = remote.interfaces["freeplay"]
  if fp then
    if fp.set_skip_intro then remote.call("freeplay", "set_skip_intro", true) end
    if fp.set_disable_crashsite then remote.call("freeplay", "set_disable_crashsite", true) end
  end
end)

local NAMES = { "Juno", "Rook" }
local BONUSES = { "character_build_distance_bonus", "character_reach_distance_bonus",
  "character_resource_reach_distance_bonus", "character_item_drop_distance_bonus",
  "character_item_pickup_distance_bonus" }
local ROW = { "wooden-chest", "iron-chest", "small-electric-pole", "stone-furnace", "transport-belt", "inserter",
  "pipe", "burner-inserter" }
local ROW_Y = -29.5
local AM = { x = 6.5, y = 6.5 }

local out, checks = {}, {}
local function log(s) out[#out + 1] = s helpers.write_file("ac-play-log.txt", table.concat(out, "\n") .. "\n") end
local function check(name, ok)
  checks[#checks + 1] = { name, ok and true or false }
  log((ok and "PASS " or "FAIL ") .. name)
end
local function shot(name) game.take_screenshot({ player = 1, path = "ac-play-" .. name .. ".png", show_gui = false,
  zoom = 0.5 }) end
local function d(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end
local function status(n) return remote.call("ai-crew", "status", n) end
local function doing(n, kind) local st = status(n) return st and st.doing and st.doing:find("^" .. kind) ~= nil end
local function ent(n)
  local st = status(n)
  if not st then return end
  for _, e in pairs(game.surfaces.nauvis.find_entities_filtered({ name = "crew-character" })) do
    if e.unit_number == st.unit then return e end
  end
end
local function find(el, name)
  if el.name == name then return el end
  for _, c in pairs(el.children) do local r = find(c, name) if r then return r end end
end

local function finish()
  local fails = 0
  local lines = {}
  for _, k in ipairs(checks) do
    lines[#lines + 1] = (k[2] and "PASS " or "FAIL ") .. k[1]
    if not k[2] then fails = fails + 1 end
  end
  lines[#lines + 1] = fails == 0 and "ALL PASS" or (fails .. " FAILED")
  helpers.write_file("ac-play-result.txt", table.concat(lines, "\n") .. "\n")
  helpers.write_file("ac-play-done.txt", "done")
  storage.stage = "done"
end

script.on_event(defines.events.on_tick, function(ev)
  local t = ev.tick
  local s, f = game.surfaces.nauvis, game.forces.player
  local S = storage
  local p = game.get_player(1)
  local c = p and p.character
  if S.stage == "done" or not c then return end
  if t == 30 then
    game.speed = 2
    s.always_day = true
    s.peaceful_mode = false
    game.map_settings.enemy_expansion.enabled = false
    game.map_settings.pollution.enabled = false
    game.forces.enemy.set_evolution_factor(0, s)
    c.teleport({ 0, 0 })
    s.request_to_generate_chunks({ 0, 0 }, 6)
    s.force_generate_chunk_requests()
    for _, e in pairs(s.find_entities_filtered({ area = { { -150, -150 }, { 150, 150 } } })) do
      if e ~= c then e.destroy() end
    end
    -- (no ore, trees, fish or biters but ours)
    local junk = { "unit", "unit-spawner", "turret", "resource", "tree", "fish" }
    for _, e in pairs(s.find_entities_filtered({ type = junk,
      area = { { -400, -400 }, { 400, 400 } } })) do e.destroy() end
    local tiles = {}
    for x = -150, 150 do for y = -150, 150 do tiles[#tiles + 1] = { name = "lab-dark-1", position = { x, y } } end end
    s.set_tiles(tiles)
    local chest = s.create_entity({ name = "iron-chest", position = { -3.5, 3.5 }, force = f })
    chest.insert({ name = "raw-fish", count = 40 }) -- (no fishing trips)
    p.get_main_inventory().clear()
  elseif t == 60 then -- a. hired through the window: a name in the box, Hire
    remote.call("ai-crew", "panel", 1, 1)
    for _, n in ipairs(NAMES) do
      local w = p.gui.screen.aic_window
      local box = w and find(w, "aic_name")
      if box then box.text = n end
      remote.call("ai-crew", "press", 1, "hire")
    end
  elseif t == 120 then
    shot("hired")
    local modes = {}
    for _, n in ipairs(NAMES) do modes[#modes + 1] = n .. " " .. tostring(status(n) and status(n).mode) end
    check("a. hired with Hire in the window, in the player's New crew mode (roam): " .. table.concat(modes, ", "),
      status("Juno") and status("Juno").mode == "roam" and status("Rook") and status("Rook").mode == "roam")
    -- b. far reach on the player's own character
    for _, k in ipairs(BONUSES) do c[k] = 10 end
    S.stage, S.at = "reach", t
  elseif S.stage == "reach" and t == S.at + 330 then
    local all, txt = true, {}
    for _, n in ipairs(NAMES) do
      local e = ent(n)
      for _, k in ipairs(BONUSES) do all = all and e and e[k] == 10 end
      txt[#txt + 1] = string.format("%s reach %.1f build %.1f", n, e.reach_distance, e.build_distance)
    end
    check("b. the player's +10 reach, build, resource reach, drop, pickup on both within 5 s: "
      .. table.concat(txt, ", "),
      all)
    for _, k in ipairs(BONUSES) do c[k] = 0 end
    -- c. armed, small biters go for the player
    for _, n in ipairs(NAMES) do
      local e = ent(n)
      e.get_inventory(defines.inventory.character_guns).insert({ name = "submachine-gun", count = 1 })
      e.get_inventory(defines.inventory.character_ammo).insert({ name = "firearm-magazine", count = 100 })
      e.insert({ name = "raw-fish", count = 10 })
    end
    S.stage, S.at = "biters", t + 60
  elseif S.stage == "biters" and t == S.at then
    c.teleport({ 0, 0 })
    S.biters = {}
    for i = 1, 8 do
      local b = s.create_entity({ name = "small-biter", position = { -7 + i * 1.5, -7 }, force = "enemy" })
      b.commandable.set_command({ type = defines.command.attack, target = c, distraction = defines.distraction.none })
      S.biters[#S.biters + 1] = b
    end
    S.stage, S.near, S.defended = "fight", {}, {}
  elseif S.stage == "fight" then
    c.health = c.max_health -- (the player kept alive: a hit still counts)
    for _, n in ipairs(NAMES) do if doing(n, "defend") then S.defended[n] = true end end
    if t == S.at + 45 then
      shot("fight")
      c.teleport({ 30, 0 }) -- the player 30 tiles off, the biters after: the crew keep up
      for i, b in ipairs(S.biters) do if b.valid then b.teleport({ 26 + i, -6 }) end end
      S.moved = t
    end
    if S.moved and t > S.moved + 60 then
      for _, n in ipairs(NAMES) do
        local e = ent(n)
        if e and d(e.position, c.position) < 12 then S.near[n] = true end
      end
    end
    if S.moved and t == S.moved + 150 then shot("followed") end
    local alive = 0
    for _, b in ipairs(S.biters) do if b.valid then alive = alive + 1 end end
    if t % 60 == 0 then
      local where = {}
      for _, n in ipairs(NAMES) do
        local e = ent(n)
        where[#where + 1] = string.format("%s (%.1f,%.1f) %s", n, e.position.x, e.position.y, tostring(status(n).doing))
      end
      log(string.format("t=%d biters %d player (%.1f,%.1f) %s", t, alive, c.position.x, c.position.y,
        table.concat(where, "; ")))
    end
    if alive == 0 and S.moved or t > S.at + 1800 then
      check("c. both came to help (defend) when biters hit the player: " .. tostring(S.defended.Juno) .. ", "
        .. tostring(S.defended.Rook), S.defended.Juno and S.defended.Rook)
      check(string.format("c. the biters killed (%d left, %d ticks)", alive, t - S.at), alive == 0)
      S.stage, S.at = "calm", t
    end
  elseif S.stage == "calm" then
    for _, n in ipairs(NAMES) do
      local e = ent(n)
      if e and d(e.position, c.position) < 12 then S.near[n] = true end
    end
    local busy = doing("Juno", "defend") or doing("Rook", "defend")
    if not busy or t > S.at + 1200 then
      check("c. both kept up with the player teleported 30 tiles (within 12): " .. tostring(S.near.Juno) .. ", "
        .. tostring(S.near.Rook), S.near.Juno and S.near.Rook)
      check(string.format("c. back to roaming after the fight (%d ticks after the last kill): Juno %s %s, Rook %s %s",
        t - S.at, status("Juno").mode, tostring(status("Juno").doing), status("Rook").mode,
        tostring(status("Rook").doing)), not busy and status("Juno").mode == "roam" and status("Rook").mode == "roam")
      -- e. an assembling machine 1 by the roamers, a 2 in the player's pockets
      c.teleport({ 0, 0 })
      local am = s.create_entity({ name = "assembling-machine-1", position = AM, force = f })
      am.set_recipe("iron-gear-wheel")
      p.insert({ name = "assembling-machine-2", count = 1 })
      for _, n in ipairs(NAMES) do ent(n).teleport(s.find_non_colliding_position("crew-character", { x = 2, y = 2 },
        8, 0.5)) end
      S.stage, S.at = "tier", t
    end
  elseif S.stage == "tier" then
    local am = s.find_entities_filtered({ name = "assembling-machine-2", position = AM, radius = 0.5 })[1]
    if am and status("Juno").jobs == 0 and status("Rook").jobs == 0 or t > S.at + 3600 then
      local r = am and am.get_recipe()
      shot("upgraded")
      check(string.format("e. the assembling machine 1 swapped for the 2 from the player's pockets (%d ticks)",
        t - S.at), am ~= nil and s.count_entities_filtered({ name = "assembling-machine-1" }) == 0
        and p.get_item_count("assembling-machine-2") == 0)
      check("e. its recipe kept: " .. tostring(r and r.name), r and r.name == "iron-gear-wheel")
      -- d. Juno follows; Rook out of it
      remote.call("ai-crew", "order", 1, "Juno follow")
      remote.call("ai-crew", "order", 1, "Rook stay")
      remote.call("ai-crew", "order", 1, "Rook auto off")
      ent("Rook").teleport({ -60, 40 })
      S.stage, S.at = "settle", t
    end
  elseif S.stage == "settle" and t == S.at + 120 then
    c.teleport({ -15, 0 })
    ent("Juno").teleport({ -13, 2 })
    local inv = p.get_main_inventory()
    for _, n in ipairs(ROW) do inv.insert({ name = n, count = 5 }) end
    for i, n in ipairs(ROW) do
      s.create_entity({ name = "entity-ghost", inner_name = n, position = { -15 + i * 4 + 0.5, ROW_Y }, force = f })
    end
    S.stage, S.at, S.near, S.worst = "follow", t, false, 0
  elseif S.stage == "follow" then
    if (t - S.at) % 60 == 0 then c.teleport({ ((t - S.at) / 60) % 2 == 0 and -15 or 15, 0 }) end -- (hopping, 1 s)
    local e = ent("Juno")
    local off = math.abs(e.position.y - ROW_Y)
    if doing("Juno", "build") then
      if off < 12 then S.near = true end
      if S.near then S.worst = math.max(S.worst, off) end
    end
    if t == S.at + 300 then shot("building") end
    if t % 60 == 0 then
      log(string.format("t=%d juno (%.1f,%.1f) player (%.1f,%.1f) %s", t, e.position.x, e.position.y, c.position.x,
        c.position.y, tostring(status("Juno").doing)))
    end
    local left = s.count_entities_filtered({ type = "entity-ghost" })
    if left == 0 and status("Juno").jobs == 0 or t > S.at + 4000 then
      shot("built")
      check(string.format("d. following, the row of %d ghosts built from the player's pockets (%d left, %d ticks)",
        #ROW, left, t - S.at), left == 0)
      check(string.format("d. no walking back to the hopping player mid-job: at most %.1f tiles off the row once there",
        S.worst), S.near and S.worst < 16)
      finish()
    end
  end
end)
