-- AI Crew: getting about: walking (the pathfinder), jetpacks, cars and trains. One of control.lua's files.

-- (the other files' that this one uses: set by link, at the end)
local any_player, CREW, crew, D, DIRS, dist2, fuel_available, player_setting, refuel

-- ----------------------------------------------------------------------------------------------------------- moving

-- its own place near pos: crew members spread round the owner instead of piling onto one point
local function spot(m, pos)
  local a = (m.phase or 0) * 2.4
  local want = { x = pos.x + math.cos(a) * 3, y = pos.y + math.sin(a) * 3 }
  return m.entity.surface.find_non_colliding_position(CREW, want, 5, 0.5) or want
end

local function stop_walk(m)
  m.move = nil
  if m.entity.valid then m.entity.walking_state = { walking = false, direction = D.north } end
end

local function stop_mining(m)
  m.mining = nil
  if m.entity.valid then m.entity.mining_state = { mining = false } end
end

local function request_path(m)
  local e, mv = m.entity, m.move
  -- its own body, not a player's: a slightly larger box than the crew's so a route through a tight gap is never a
  -- squeeze for them
  local id = e.surface.request_path({ bounding_box = { { -0.15, -0.15 }, { 0.15, 0.15 } },
    collision_mask = e.prototype.collision_mask, start = e.position, goal = mv.goal, force = e.force,
    radius = math.max(mv.radius - 0.5, 0.5), entity_to_ignore = e, pathfind_flags = { cache = false, no_break = true } })
  storage.paths = storage.paths or {}
  storage.paths[id] = m.name
  mv.path, mv.i, mv.final, mv.still = nil, 1, nil, 0
end

local TRIP = 80 -- longer than this: a car or train when there's one (vehicles, below)
local vehicle_trip, leave -- (with the vehicles)

-- true when already within radius of pos; else starts walking there (or driving, riding: a long trip)
local function go(m, pos, radius)
  local r = m.ride
  if r then -- in a car or on a train, or on the way to it: the goal moves along with it, else they get off
    if dist2(r.goal, pos) < 1 then return false end
    if dist2(m.entity.position, pos) > 40 * 40 then
      r.goal, r.radius, r.repath = { x = pos.x, y = pos.y }, radius, true
      return false
    end
    leave(m)
  end
  if dist2(m.entity.position, pos) <= radius * radius then
    if m.move then stop_walk(m) end
    return true
  end
  if not (m.move and dist2(m.move.goal, pos) < 1) then
    if vehicle_trip and dist2(m.entity.position, pos) > TRIP * TRIP and vehicle_trip(m, pos, radius) then return false end
    local near = m.move and dist2(m.move.goal, pos) < 64
    m.move = { goal = { x = pos.x, y = pos.y }, radius = radius, hops = near and m.move.hops or 0,
      still_total = near and m.move.still_total or 0 }
    request_path(m)
  end
  return false
end

-- no route at all (a machine's in the way, a wall of them, a whole line): step through it, a few tiles at a time, in
-- the direction of the goal. Slower than walking and only ever onto free ground, but it gets them there in the end
local function hop_along(m, step, tries)
  local mv, e = m.move, m.entity
  if mv.hop_tries and mv.hop_tries >= tries then return false end
  local dx, dy = mv.goal.x - e.position.x, mv.goal.y - e.position.y
  local d = math.sqrt(dx * dx + dy * dy)
  if d < 0.5 then return false end
  local tx, ty = e.position.x + dx / d * math.min(step, d), e.position.y + dy / d * math.min(step, d)
  local to = e.surface.find_non_colliding_position(CREW, { x = tx, y = ty }, step + 1, 0.5)
  if not to then return false end
  mv.hop_tries, mv.hop_at, mv.last = (mv.hop_tries or 0) + 1, game.tick, { x = to.x, y = to.y }
  e.teleport(to)
  return true
end

-- Jetpack: a short flight straight over whatever is in the way (machines, walls, water, cliffs), landing on free ground
-- near the goal, up to JET tiles at a time. Used when the pathfinder finds no route, when the route is far longer than
-- the way straight there, when walking gets stuck, and to rush to a fight. Off (the player's "Crew jetpacks"
-- setting): they step through blockages a few tiles at a time instead
local JET = 32
local function jets(m)
  local p = m.owner and game.get_player(m.owner) or any_player()
  return player_setting(p, "ai-crew-jetpack") ~= false
end

local function fly(m, to)
  local e = m.entity
  if m.fly or not jets(m) then return false end
  if m.move and m.move.flew and dist2(m.move.goal, to) < 4 then return false end -- (once per goal: no hopping about)
  local dx, dy = to.x - e.position.x, to.y - e.position.y
  local d = math.sqrt(dx * dx + dy * dy)
  if d < 2 then return false end
  if d > JET then to, d = { x = e.position.x + dx / d * JET, y = e.position.y + dy / d * JET }, JET end
  local land = e.surface.find_non_colliding_position(CREW, to, 8, 0.5)
  if not land then return false end
  d = math.sqrt(dist2(e.position, land))
  e.walking_state = { walking = false, direction = D.north }
  m.fly = { from = { x = e.position.x, y = e.position.y }, to = land, t0 = game.tick, ticks = math.max(math.ceil(d / 0.4), 12) }
  m.flights = (m.flights or 0) + 1
  if m.move then m.move.flew = true end
  return true
end

-- each tick of a flight: along the line, a trail of smoke; landed, the walk goes on from there
local function flight(m)
  local f, e = m.fly, m.entity
  local k = math.min((game.tick - f.t0) / f.ticks, 1)
  e.teleport({ x = f.from.x + (f.to.x - f.from.x) * k, y = f.from.y + (f.to.y - f.from.y) * k })
  if game.tick % 3 == 0 and prototypes.trivial_smoke["smoke-fast"] then e.surface.create_trivial_smoke({ name = "smoke-fast", position = e.position }) end
  if k >= 1 then
    m.fly = nil
    if m.move then
      m.move.still, m.move.still_total, m.move.hops, m.move.hop_tries = 0, 0, 0, nil
      request_path(m)
    end
  end
end

local function walk(m)
  local mv, e = m.move, m.entity
  if dist2(e.position, mv.goal) <= mv.radius * mv.radius then return stop_walk(m) end
  if not mv.path then
    -- waiting for the pathfinder (slow in a big base): stand still, not keep walking the old way into a machine
    if mv.walking ~= false then
      e.walking_state = { walking = false, direction = D.north }
      mv.walking = false
    end
    if mv.retry and game.tick >= mv.retry then mv.retry = nil request_path(m) end
    return
  end
  mv.walking = true
  -- path_finished answers "no route" with a straight line at the goal, which only works while nothing is in the way.
  -- Getting no closer to the goal than it has ever been for a couple of seconds means something is: step through it
  if mv.straight then
    local d2 = dist2(e.position, mv.goal)
    if not mv.closest or d2 < mv.closest then mv.closest, mv.closest_at = d2, game.tick end
    if game.tick - (mv.closest_at or 0) >= 150 then
      mv.closest, mv.closest_at = nil, nil
      if fly(m, mv.goal) or hop_along(m, 3, 20) then return end
    end
  end
  local wp = mv.path[mv.i]
  if wp and dist2(e.position, wp.position) < 0.25 then
    mv.i = mv.i + 1
    wp = mv.path[mv.i]
  end
  if not wp then
    if mv.final or not e.surface.can_place_entity({ name = CREW, position = mv.goal }) then return stop_walk(m) end
    mv.final = true
    mv.path[mv.i] = { position = mv.goal }
    wp = mv.path[mv.i]
  end
  local dx, dy = wp.position.x - e.position.x, wp.position.y - e.position.y
  local d = math.floor(math.atan2(dx, -dy) / (math.pi / 4) + 0.5) % 8
  if mv.slide and game.tick < mv.slide.until_tick then d = (d + mv.slide.turn) % 8 end -- (sliding round a corner)
  e.walking_state = { walking = true, direction = DIRS[d + 1] }
  -- stuck (hardly moved for 1.5 s): ask for a new path; after three tries hop next to the goal
  if mv.last and dist2(e.position, mv.last) < 0.0004 then
    mv.still, mv.still_total = mv.still + 1, (mv.still_total or 0) + 1
  else
    mv.still = 0
  end
  mv.last = { x = e.position.x, y = e.position.y }
  -- pushing against something: turn one step either way for a moment to slide along it
  if mv.still > 0 and mv.still % 12 == 0 then
    mv.flip = not mv.flip
    mv.slide = { turn = mv.flip and 1 or 7, until_tick = game.tick + 14 }
  end
  -- stuck a long while, even across small goal changes: hop to free ground near the goal
  if (mv.still_total or 0) > 240 then
    if fly(m, mv.goal) then return end
    local to = e.surface.find_non_colliding_position(e.name, mv.goal, 6, 0.5)
    if to then e.teleport(to) end
    return stop_walk(m)
  end
  if mv.still == 20 then -- (another crew member in the way: step aside)
    for _, o in pairs(crew()) do
      if o ~= m and o.entity.valid and dist2(o.entity.position, e.position) < 2.25 then
        local to = e.surface.find_non_colliding_position(e.name, { x = e.position.x + (m.phase % 2 == 0 and 1.2 or -1.2),
          y = e.position.y + 0.6 }, 2, 0.3)
        if to then e.teleport(to) end
        break
      end
    end
  end
  if mv.still > 90 then
    mv.hops = mv.hops + 1
    if mv.hops > 2 then
      if fly(m, mv.goal) then return end
      local to = e.surface.find_non_colliding_position(e.name, mv.goal, 6, 0.5)
      if to then e.teleport(to) end
      stop_walk(m)
    else
      request_path(m)
    end
  end
end

-- -------------------------------------------------------------------------------------------------------- vehicles
-- Long trips (over TRIP tiles). A train of yours standing at a stop within 24 tiles whose schedule goes to a stop
-- within 60 tiles of where they're headed: they get on and ride along (its schedule left alone), and get off there.
-- Else a car or tank of yours parked within 24 tiles with no one in it (fuelled from stock when low): they drive it
-- along a path the pathfinder found for the car, and park it within 12 tiles of the goal. Stuck in the car for 2 s
-- they back up; a third time, or no route for a car, they get out and go on foot (or fly) and leave cars alone for a
-- minute.
local R = defines.riding

leave = function(m)
  local r = m.ride
  m.ride = nil
  local e = m.entity
  if not (e.valid and e.vehicle) then return end
  local v = e.vehicle
  if v.type == "car" then e.riding_state = { acceleration = R.acceleration.nothing, direction = R.direction.straight } end
  v.set_driver(nil)
  local at = e.surface.find_non_colliding_position(CREW, v.position, 6, 0.5) -- (beside it, not back where they got in)
  if at then
    e.teleport(at)
    m.drop_at = at -- (and again next tick: the game puts them back where they got in once the tick is over)
  end
  if r and r.kind == "car" and r.car.valid and not r.car.get_driver() then -- (handbrake: it stays where they left it)
    r.car.riding_state = { acceleration = R.acceleration.braking, direction = R.direction.straight }
  end
end

local function taken(v)
  for _, o in pairs(crew()) do if o.ride and (o.ride.car == v or o.ride.seat == v) then return true end end
end

-- a train standing near them going where they're going, and a free seat on it
local function train_for(m, goal)
  local e = m.entity
  for _, stop in pairs(e.surface.find_entities_filtered({ type = "train-stop", force = e.force, position = e.position, radius = 24 })) do
    local t = stop.get_stopped_train()
    local sched = t and not t.manual_mode and t.state == defines.train_state.wait_station and t.schedule
    for _, rec in pairs(sched and sched.records or {}) do
      if rec.station and rec.station ~= stop.backer_name then
        for _, to in pairs(game.train_manager.get_train_stops({ station_name = rec.station, surface = e.surface })) do
          if dist2(to.position, goal) < 60 * 60 and dist2(to.position, goal) < dist2(e.position, goal) / 4 then
            local seat, sd
            for _, c in pairs(t.carriages) do
              if not c.get_driver() and not taken(c) then
                local d = dist2(c.position, e.position)
                if not sd or d < sd then seat, sd = c, d end
              end
            end
            if seat then return t, seat, to end
          end
        end
      end
    end
  end
end

local function car_for(m)
  local e = m.entity
  local best, bd
  for _, c in pairs(e.surface.find_entities_filtered({ type = "car", force = e.force, position = e.position, radius = 24 })) do
    local fuel = c.get_fuel_inventory()
    if not c.get_driver() and not c.get_passenger() and not taken(c) and (not fuel or not fuel.is_empty() or fuel_available(m)) then
      local d = dist2(c.position, e.position)
      if not bd or d < bd then best, bd = c, d end
    end
  end
  return best
end

vehicle_trip = function(m, pos, radius)
  if m.fly or m.retreat or game.tick < (m.no_ride or 0) then return false end
  local goal = { x = pos.x, y = pos.y }
  local t, seat, to = train_for(m, goal)
  if t then
    m.ride = { kind = "train", train = t, seat = seat, from = t.station, to = to, goal = goal, radius = radius, t0 = game.tick }
  else
    local car = car_for(m)
    if not car then return false end
    m.ride = { kind = "car", car = car, goal = goal, radius = radius, t0 = game.tick }
  end
  stop_walk(m)
  m.rides = (m.rides or 0) + 1
  return true
end

local function car_path(m)
  local r, car = m.ride, m.ride.car
  local id = car.surface.request_path({ bounding_box = { { -1, -1 }, { 1, 1 } }, collision_mask = car.prototype.collision_mask,
    start = car.position, goal = r.goal, force = car.force, radius = 10, entity_to_ignore = car, path_resolution_modifier = -2,
    pathfind_flags = { cache = false, prefer_straight_paths = true } })
  storage.paths = storage.paths or {}
  storage.paths[id] = m.name
  r.path_id, r.path, r.i, r.repath = id, nil, 1, nil
end

-- each tick of a trip: walking up to the vehicle, getting in; on a train, waiting for its stop; in a car, driving
local function riding(m)
  local r, e = m.ride, m.entity
  local v = r.kind == "car" and r.car or r.seat
  if not (v and v.valid) then return leave(m) end
  if e.vehicle ~= v then
    if r.kind == "train" and not (r.train.valid and r.train.station) then m.move = nil return leave(m) end -- (it left)
    if game.tick - r.t0 > 900 then m.move = nil return leave(m) end
    if dist2(e.position, v.position) > 9 then
      if not (m.move and dist2(m.move.goal, v.position) < 4) then
        m.move = { goal = { x = v.position.x, y = v.position.y }, radius = 2, hops = 0, still_total = 0 }
        request_path(m)
      end
      return
    end
    stop_walk(m)
    if r.kind == "car" then refuel(m, v) end
    v.set_driver(e)
    if e.vehicle ~= v then return leave(m) end
    r.t0 = game.tick
    if r.kind == "car" then car_path(m) end
    return
  end
  if r.kind == "train" then
    local tr = r.train
    r.still = tr.valid and math.abs(tr.speed) < 0.01 and not tr.station and (r.still or 0) + 1 or 0
    if not tr.valid or tr.station == r.to or game.tick - r.t0 > 10800 or r.still > 1800 -- (standing out on the line: off)
      or tr.station == r.from and game.tick - r.t0 > 3600 then -- (a minute aboard and it hasn't left: off again)
      if tr.valid and tr.station ~= r.to then m.no_ride = game.tick + 3600 end
      leave(m)
    end
    return
  end
  local car = v
  if r.repath then car_path(m) end
  local d2 = dist2(car.position, r.goal)
  if d2 < 12 * 12 or r.failed then
    if math.abs(car.speed) > 0.02 then
      e.riding_state = { acceleration = R.acceleration.braking, direction = R.direction.straight }
      return
    end
    if r.failed then m.no_ride = game.tick + 3600 end
    return leave(m)
  end
  if not r.path then
    e.riding_state = { acceleration = R.acceleration.braking, direction = R.direction.straight }
    return
  end
  local wp = r.path[r.i]
  while wp and dist2(car.position, wp.position) < 16 do
    r.i = r.i + 1
    wp = r.path[r.i]
  end
  local to = wp and wp.position or r.goal
  local want = (math.atan2(to.x - car.position.x, -(to.y - car.position.y)) / (2 * math.pi)) % 1
  local diff = (want - car.orientation + 0.5) % 1 - 0.5
  local dir = diff > 0.01 and R.direction.right or diff < -0.01 and R.direction.left or R.direction.straight
  if r.back_until and game.tick < r.back_until then -- (backing out of something, wheel the other way)
    e.riding_state = { acceleration = R.acceleration.reversing,
      direction = dir == R.direction.right and R.direction.left or dir == R.direction.left and R.direction.right or dir }
    return
  end
  r.slow = math.abs(car.speed) < 0.01 and (r.slow or 0) + 1 or 0
  if r.slow > 120 then
    r.slow, r.backs = 0, (r.backs or 0) + 1
    if r.backs > 2 then r.failed = true return end
    r.back_until = game.tick + 45
    return
  end
  local braking = (math.abs(diff) > 0.2 and car.speed > 0.12) or (d2 < 30 * 30 and car.speed > 0.2)
  e.riding_state = { acceleration = braking and R.acceleration.braking or R.acceleration.accelerating, direction = dir }
end

-- ------------------------------------------------------------------------------------------------------------- shared
-- what the other files use of this one, and its link: control.lua calls it once all files are loaded
return {
  share = { flight = flight, fly = fly, go = go, JET = JET, riding = riding, spot = spot, stop_mining = stop_mining,
    stop_walk = stop_walk, walk = walk },
  link = function(A)
    any_player, CREW, crew, D, DIRS, dist2 = A.any_player, A.CREW, A.crew, A.D, A.DIRS, A.dist2
    fuel_available, player_setting, refuel = A.fuel_available, A.player_setting, A.refuel
  end,
}
