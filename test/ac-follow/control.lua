-- Real client: the player walks a route through a block of assemblers with one-tile gaps and inserters between the
-- rows (as in a real build), stopping in the gaps; three crew members follow. Nobody may stay stuck against a machine:
-- the longest a follower stands still while far from the player, and the time it spends walking without moving (into
-- something), are measured. The pathfinder is slowed as in a big base.
-- (no crash-site intro: it pauses the game and waits for the player to press Tab)
script.on_init(function()
  local fp = remote.interfaces["freeplay"]
  if fp then
    if fp.set_skip_intro then remote.call("freeplay", "set_skip_intro", true) end
    if fp.set_disable_crashsite then remote.call("freeplay", "set_disable_crashsite", true) end
  end
end)

local NAMES = { "Rook", "Mara", "Juno" }
local route, seg, pause, track = {}, 1, 0, {}

local function body(name)
  local st = remote.call("ai-crew", "status", name)
  return st and game.surfaces[1].find_entities_filtered({ name = "character", position = st.position, radius = 0.3 })[1]
end

local function shot(name) game.take_screenshot({ player = 1, path = "ac-follow-" .. name .. ".png", show_gui = false, zoom = 0.6 }) end

local function setup()
  local p = game.get_player(1)
  local s, f = p.surface, p.force
  s.always_day = true
  for _, e in pairs(s.find_entities_filtered({ area = { { -40, -30 }, { 50, 30 } } })) do
    if e.type ~= "character" then e.destroy() end
  end
  local tiles = {}
  for x = -40, 50 do for y = -30, 30 do tiles[#tiles + 1] = { name = "lab-dark-1", position = { x, y } } end end
  s.set_tiles(tiles)
  -- two rows of assemblers, one-tile gaps between them, inserters in the gap between the rows
  for col = 0, 6 do
    for _, y in ipairs({ -4.5, 3.5 }) do
      s.create_entity({ name = "assembling-machine-1", position = { 1.5 + col * 4, y }, force = f })
    end
    for _, x in ipairs({ 0.5 + col * 4, 2.5 + col * 4 }) do
      s.create_entity({ name = "inserter", position = { x, -0.5 }, force = f })
    end
  end
  p.teleport({ -10, 0 })
  for i, n in ipairs(NAMES) do remote.call("ai-crew", "hire", n, s.name, { x = -14, y = -4 + i * 2 }, f.name, 1) end
  remote.call("ai-crew", "test_path_delay", 90) -- (a pathfinder as busy as in a big base: answers after 1.5 s)
  -- the route: into the gaps between machines, a pause in each
  route = { { -2, -1.5 }, { 3.5, -1.5 }, { 3.5, -4.5 }, { 3.5, -1.5 }, { 11.5, -1.5 }, { 11.5, 2.5 }, { 19.5, 1.5 },
    { 27.5, 1.5 }, { 27.5, 3.5 }, { 34, 0 } }
end

script.on_event(defines.events.on_tick, function(ev)
  local t = ev.tick
  if t == 30 then setup() return end
  if t < 60 or storage.done then return end
  local p = game.get_player(1)
  -- the player along the route (0.15 tiles a tick, as walking), 4 s in each stop
  if pause > 0 then
    pause = pause - 1
  elseif route[seg] then
    local to, at = route[seg], p.position
    local dx, dy = to[1] - at.x, to[2] - at.y
    local d = math.sqrt(dx * dx + dy * dy)
    if d < 0.2 then
      seg, pause = seg + 1, 240
    else
      p.teleport({ at.x + dx / d * math.min(0.15, d), at.y + dy / d * math.min(0.15, d) })
    end
  end
  -- each follower: how long it has stood still while more than 6 tiles off
  if t % 30 == 0 then
    for _, n in ipairs(NAMES) do
      local b = body(n)
      if b then
        local tr = track[n] or { still = 0, worst = 0, push = 0 }
        track[n] = tr
        local far = (b.position.x - p.position.x) ^ 2 + (b.position.y - p.position.y) ^ 2 > 36
        local moved = not tr.last or (b.position.x - tr.last.x) ^ 2 + (b.position.y - tr.last.y) ^ 2 > 0.01
        tr.still = (far and not moved) and tr.still + 30 or 0
        if b.walking_state.walking and not moved then tr.push = tr.push + 30 end -- (walking into something)
        tr.worst = math.max(tr.worst, tr.still)
        tr.last = { x = b.position.x, y = b.position.y }
        tr.dist = math.sqrt((b.position.x - p.position.x) ^ 2 + (b.position.y - p.position.y) ^ 2)
      end
    end
  end
  if t == 600 then shot("mid") end
  if not route[seg] and pause == 0 and not storage.done then
    if not storage.end_tick then storage.end_tick = t + 600 end
    if t >= storage.end_tick then
      shot("end")
      local lines, ok = {}, true
      for _, n in ipairs(NAMES) do
        local tr = track[n] or { worst = 999, dist = 999, push = 999 }
        local good = tr.worst <= 300 and tr.dist <= 8 and tr.push <= 180
        ok = ok and good
        lines[#lines + 1] = string.format("%s %s: longest stuck %.1f s, walking into things %.1f s, at the end %.1f tiles off",
          good and "PASS" or "FAIL", n, tr.worst / 60, tr.push / 60, tr.dist)
      end
      lines[#lines + 1] = ok and "ALL PASS" or "FAILED"
      helpers.write_file("ac-follow-result.txt", table.concat(lines, "\n"))
      helpers.write_file("ac-follow-done.txt", "done")
      storage.done = true
    end
  end
end)
