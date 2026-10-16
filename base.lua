-- AI Crew: your base, as you mark it ("Mark base": the shortcut bar's button, or its key in Settings > Controls). A pin
-- where you stand, nothing drawn; the base is every chunk of your buildings joined to the pin's (chunk next to chunk,
-- corners too, each holding some of your machines, chests, belts, inserters, drills or pipes: poles, rails and walls
-- don't count, so an outpost down a rail line stays out). With one, the crew fetch what the base makes from anywhere
-- in it, nearest first (plan.lua's far_find), not just within a fixed distance. Pressed again within 16 tiles of the
-- pin: the base forgotten. The chunks are found a slice a tick (up to 4096 chunks) when the pin is set and again
-- every 10 minutes (the base grows); the old ones stand till the new ones are all found. One of control.lua's files.

local TYPES = { "assembling-machine", "furnace", "container", "logistic-container", "transport-belt", "underground-belt",
  "splitter", "inserter", "loader", "loader-1x1", "lab", "mining-drill", "pipe", "pipe-to-ground", "storage-tank",
  "beacon", "roboport", "rocket-silo", "boiler", "generator" }
local MAX_CHUNKS, PER_TICK, REFRESH = 4096, 48, 36000

local function bases()
  storage.bases = storage.bases or {}
  return storage.bases
end

local function tell(player, text) if player then player.print(text) end end

-- a fresh search from the pin (the chunks found so far stay in use meanwhile)
local function refill(b)
  local cx, cy = math.floor(b.pin.x / 32), math.floor(b.pin.y / 32)
  b.fill = { queue = { { cx, cy } }, seen = { [cx .. "," .. cy] = true }, found = {}, head = 1 }
end

-- the pin set where pos is (owner: a player index, nil in tests), or taken away when it's near the pin already
local function mark(owner, surface, pos, force)
  local key = owner or 0
  local player = owner and game.get_player(owner)
  local b = bases()[key]
  if b and b.surface == surface.name and (pos.x - b.pin.x) ^ 2 + (pos.y - b.pin.y) ^ 2 <= 16 * 16 then
    bases()[key] = nil
    tell(player, "[AI Crew] Base forgotten: the crew fetch from chests and belts round you again.")
    return false
  end
  b = { surface = surface.name, pin = { x = math.floor(pos.x), y = math.floor(pos.y) }, force = force.name,
    tell = owner, moved = b ~= nil }
  bases()[key] = b
  refill(b)
  return true
end

-- a slice of each base's search; called every tick (control.lua)
local function step(tick)
  for key, b in pairs(bases()) do
    local s, f = game.get_surface(b.surface), game.forces[b.force]
    if not (s and f) then
      bases()[key] = nil
    else
      if not b.fill and tick - (b.tick or 0) >= REFRESH then refill(b) end
      local fl = b.fill
      local budget = PER_TICK
      while fl and budget > 0 do
        local c = fl.queue[fl.head]
        if not c or #fl.found >= MAX_CHUNKS then -- (all found: in use from now)
          b.chunks, b.fill, b.tick, fl = fl.found, nil, tick, nil
          if b.tell then
            local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
            for _, ch in ipairs(b.chunks) do
              x0, y0, x1, y1 = math.min(x0, ch[1]), math.min(y0, ch[2]), math.max(x1, ch[1]), math.max(y1, ch[2])
            end
            tell(game.get_player(b.tell), string.format("[AI Crew] Base %s: %d chunks, about %d x %d tiles. The crew fetch from anywhere in it.",
              b.moved and "moved" or "marked", #b.chunks, (x1 - x0 + 1) * 32, (y1 - y0 + 1) * 32))
            b.tell = nil
          end
        else
          fl.head, budget = fl.head + 1, budget - 1
          local x, y = c[1] * 32, c[2] * 32
          local first = fl.head == 2 -- (the pin's own chunk: in, even bare)
          if first or s.count_entities_filtered({ area = { { x, y }, { x + 32, y + 32 } }, force = f, type = TYPES, limit = 1 }) > 0 then
            fl.found[#fl.found + 1] = { c[1], c[2] }
            for dx = -1, 1 do
              for dy = -1, 1 do
                local k = (c[1] + dx) .. "," .. (c[2] + dy)
                if not fl.seen[k] then
                  fl.seen[k] = true
                  fl.queue[#fl.queue + 1] = { c[1] + dx, c[2] + dy }
                end
              end
            end
          end
        end
      end
      if fl and fl.head > 512 then -- (the queue's front dropped now and then: it'd only grow)
        local q = {}
        for i = fl.head, #fl.queue do q[#q + 1] = fl.queue[i] end
        fl.queue, fl.head = q, 1
      end
    end
  end
end

-- the base's chunks ({cx, cy}) for this crew member's owner, when it's on that surface and they're found; else nil
local function base_chunks(m)
  local b = storage.bases and storage.bases[m.owner or 0]
  if b and b.chunks and b.surface == m.entity.surface.name then return b.chunks end
end

local function pressed(ev)
  local player = game.get_player(ev.player_index)
  local c = player and player.character
  if not c then
    if player then tell(player, "[AI Crew] Stand where your base is to mark it.") end
    return
  end
  if mark(player.index, c.surface, c.position, player.force) then
    tell(player, "[AI Crew] Base pin set here; finding its edges...")
  end
end
script.on_event("ai-crew-mark-base", pressed)
script.on_event(defines.events.on_lua_shortcut, function(ev)
  if ev.prototype_name == "ai-crew-mark-base" then pressed(ev) end
end)

return {
  share = { base_chunks = base_chunks, base_step = step, mark_base = mark },
  link = function() end,
}
