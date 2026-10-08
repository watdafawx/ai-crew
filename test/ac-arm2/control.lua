-- Headless check of what was reported: magazines in stock, no guns; shotgun and submachine gun researched, shells not.
-- Mara starts as reported: a shotgun in gun slot 1 and magazines in ammo slot 3. Both must end with a submachine gun
-- and magazines beside it, no shotgun made, nothing stray.
local out = {}
local function log(s) out[#out + 1] = s helpers.write_file("ac-arm2.txt", table.concat(out, "\n") .. "\n") end
local G, A = defines.inventory.character_guns, defines.inventory.character_ammo

local function body(name)
  local st = remote.call("ai-crew", "status", name)
  return st and game.surfaces.nauvis.find_entities_filtered({ name = "character", position = st.position, radius = 0.3 })[1]
end

script.on_nth_tick(5, function(ev)
  if ev.tick ~= 5 then return end
  local s, f = game.surfaces.nauvis, game.forces.player
  s.always_day = true
  for _, e in pairs(s.find_entities_filtered({ area = { { -60, -60 }, { 60, 60 } } })) do e.destroy() end
  local tiles = {}
  for x = -60, 60 do for y = -60, 60 do tiles[#tiles + 1] = { name = "lab-dark-1", position = { x, y } } end end
  s.set_tiles(tiles)
  for _, r in pairs({ "submachine-gun", "shotgun", "firearm-magazine" }) do f.recipes[r].enabled = true end
  f.recipes["shotgun-shell"].enabled = false
  local chest = s.create_entity({ name = "iron-chest", position = { 0.5, 0.5 }, force = f })
  chest.insert({ name = "iron-plate", count = 200 })
  chest.insert({ name = "copper-plate", count = 50 })
  chest.insert({ name = "firearm-magazine", count = 310 })
  remote.call("ai-crew", "hire", "Rook", "nauvis", { x = 3, y = 2 })
  remote.call("ai-crew", "hire", "Mara", "nauvis", { x = -3, y = 2 })
  remote.call("ai-crew", "hire", "Juno", "nauvis", { x = 0, y = 5 })
  local mara = body("Mara")
  mara.get_inventory(G)[1].set_stack({ name = "shotgun", count = 1 })
  mara.get_inventory(A)[3].set_stack({ name = "firearm-magazine", count = 40 })
end)

script.on_nth_tick(1800, function(ev)
  if storage.done or ev.tick == 0 then return end
  local function kit(name)
    local b = body(name)
    if not b then return "gone" end
    local g, a = b.get_inventory(G), b.get_inventory(A)
    local parts = {}
    for i = 1, #g do
      parts[#parts + 1] = (g[i].valid_for_read and g[i].name or "-") .. "/" .. (a[i].valid_for_read and (a[i].name .. " " .. a[i].count) or "-")
    end
    return table.concat(parts, ", ")
  end
  -- (hand-crafting by scripted characters isn't in the production stats: count the guns that exist)
  local function count(item)
    local n = game.surfaces.nauvis.find_entities_filtered({ name = "iron-chest" })[1].get_item_count(item)
    for _, who in ipairs({ "Rook", "Mara", "Juno" }) do
      local b = body(who)
      for _, i in ipairs({ G, defines.inventory.character_main }) do n = n + (b and b.get_inventory(i).get_item_count(item) or 0) end
    end
    return n
  end
  local smg, shot = count("submachine-gun"), count("shotgun")
  log(string.format("t=%d Rook [%s] Mara [%s] Juno [%s]; smgs %d shotguns %d", ev.tick, kit("Rook"), kit("Mara"), kit("Juno"), smg, shot))
  local ok_r = kit("Rook"):find("^submachine%-gun/firearm%-magazine") ~= nil
  local ok_m = kit("Mara"):find("^submachine%-gun/firearm%-magazine") ~= nil
  local ok_j = kit("Juno"):find("^submachine%-gun/firearm%-magazine %d+, %-/%-, %-/%-$") ~= nil
  -- (three crew, idle: each its own spot, none on top of another)
  local near = math.huge
  local names = { "Rook", "Mara", "Juno" }
  for i = 1, 3 do for j = i + 1, 3 do
    local a, b = body(names[i]), body(names[j])
    if a and b then
      local d = math.sqrt((a.position.x - b.position.x) ^ 2 + (a.position.y - b.position.y) ^ 2)
      near = math.min(near, d)
    end
  end end
  local stray = kit("Mara"):find("%-/firearm") or kit("Rook"):find("%-/firearm")
  if not (ok_r and ok_m and ok_j) and ev.tick < 36000 then return end
  local checks = {
    { "Rook: submachine gun, magazines beside it", ok_r },
    { "Mara: swapped the shellless shotgun for a submachine gun", ok_m },
    { "no ammo beside an empty gun slot", not stray },
    { "no shotgun made (Mara's one still about)", shot == 1 },
    { "Juno: one submachine gun, the other gun slots empty", ok_j },
    { "one submachine gun each, no more (3)", smg == 3 },
    { "no two crew on one spot (closest " .. string.format("%.1f", near) .. " tiles)", near > 1.5 },
  }
  local fails = 0
  for _, k in ipairs(checks) do log((k[2] and "PASS " or "FAIL ") .. k[1]) if not k[2] then fails = fails + 1 end end
  log(fails == 0 and "ALL PASS" or (fails .. " FAILED"))
  storage.done = true
end)
