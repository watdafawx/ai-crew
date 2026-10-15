-- Real client: the crew cards in the bottom right. python test/run_cards.py [--scale 2] (single player through the fse
-- launcher: the cards are the web page, screenshots composited by the runner); in a game without the web plugin
-- (multiplayer, the factorio MCP's client) the game's GUI cards are checked the same way.
-- Four crew, Rook armed, hurt and carrying fish: a card each, centre left, Rook's with his gear and health.
-- Then Mara talks, Rook fights, Juno is down: the cards say so. Cards clicked: Rook's (out of reach) his pockets,
-- Mara's (in reach) her inventory. The "Crew
-- cards" setting (and its checkbox in the window's gear panel): off, no cards; on, back. Bolt fired: three.
-- The corner card's Follow me: all of them follow. Centre left by default; "Bottom right" moves them there.
-- Web only (the runner checks these): another shell over the cards hides them, the pause menu hides them.
-- The runner answers ac-cards-want-<n>.txt ("shot <name>" / "click <member>") within a second.
script.on_init(function()
  local fp = remote.interfaces["freeplay"]
  if fp then
    if fp.set_skip_intro then remote.call("freeplay", "set_skip_intro", true) end
    if fp.set_disable_crashsite then remote.call("freeplay", "set_disable_crashsite", true) end
  end
end)

local out = {}
local function log(s) out[#out + 1] = s helpers.write_file("ac-cards-result.txt", table.concat(out, "\n") .. "\n") end
local function check(ok, what)
  storage.failed = (storage.failed or 0) + (ok and 0 or 1)
  log((ok and "PASS " or "FAIL ") .. what)
end
local function want(text)  -- (the runner: a screenshot composited with the page, a click in the page)
  storage.wants = (storage.wants or 0) + 1
  helpers.write_file("ac-cards-want-" .. storage.wants .. ".txt", text)
end
local function shot(name)
  game.take_screenshot({ player = 1, path = "ac-cards-lua-" .. name .. ".png", show_gui = true })
  want("shot " .. name)
end
local function state() return remote.call("ai-crew", "cards", 1) end
local function by_name(st)
  local t = {}
  for _, c in ipairs(st.sent or {}) do t[c.name] = c end
  return t
end
local function count(st)
  if st.web then return st.open and #(st.sent or {}) or 0 end
  return table_size(st.lua)
end
local function find(el, name)
  if el.name == name then return el end
  for _, c in pairs(el.children) do local r = find(c, name) if r then return r end end
end
local function member(name)
  local p = game.get_player(1)
  local st = remote.call("ai-crew", "status", name)
  return st and p.surface.find_entities_filtered({ name = "crew-character", position = st.position, radius = 0.3 })[1]
end

local steps = {
  [60] = function()
    local p = game.get_player(1)
    p.insert({ name = "raw-fish", count = 50 })  -- (no fishing trips: they stay in sight)
    for i, n in ipairs({ "Rook", "Mara", "Juno", "Bolt" }) do
      remote.call("ai-crew", "hire", n, p.surface.name, { x = p.position.x + i * 3, y = p.position.y + 2 }, p.force.name, 1)
    end
  end,
  [70] = function()
    local rook = member("Rook")
    storage.rook = rook
    rook.get_inventory(defines.inventory.character_armor).insert({ name = "heavy-armor", count = 1 })
    rook.get_inventory(defines.inventory.character_guns).insert({ name = "submachine-gun", count = 1 })
    rook.get_inventory(defines.inventory.character_ammo).insert({ name = "firearm-magazine", count = 40 })
    rook.insert({ name = "raw-fish", count = 12 })
  end,
  [100] = function() storage.rook.health = storage.rook.max_health * 0.6 end,  -- (he eats a fish now: hurt a while)
  [130] = function()
    local p = game.get_player(1)
    local st = state()
    log("shown as: " .. (st.web and "the web page" or "the game's GUI"))
    check(count(st) == 4, "a card for each of the four (" .. count(st) .. ")")
    local res = p.display_resolution
    if st.web then
      local r = st.rect or { 0, 0, 0, 0 }
      check(r[1] >= 0 and r[1] <= 40 * p.display_scale and math.abs(r[2] + r[4] / 2 - res.height / 2) <= 4
        and r[1] + r[3] <= res.width, "the page in the middle of the left edge (" .. serpent.line(r) .. " of "
        .. res.width .. "x" .. res.height .. ")")
      local rook = by_name(st).Rook or { slots = {} }
      local gun, ammo = rook.slots[2] or {}, rook.slots[3] or {}
      check(gun.item == "submachine-gun" and gun.icon and ammo.item == "firearm-magazine" and ammo.n == 40,
        "Rook's card: his gun and 40 rounds, with icons (" .. serpent.line(rook.slots) .. ")")
      check(rook.hp and rook.hp < rook.max, "Rook's card: hurt (" .. tostring(rook.hp) .. "/" .. tostring(rook.max) .. ")")
    else
      local f = p.gui.screen.aic_hud_Rook
      check(f and f.location.x < res.width / 2 and f.location.y < res.height / 2 + 200, "on the left")
      local gun, ammo, bar = f and find(f, "aic_gun"), f and find(f, "aic_ammo"), f and find(f, "aic_hp")
      check(gun and gun.sprite == "item/submachine-gun" and ammo and ammo.number == 40, "Rook's card: his gun and 40 rounds")
      check(bar and bar.value < 1, "Rook's card: hurt (" .. tostring(bar and bar.value) .. ")")
    end
    shot("four")
  end,
  -- (the runner: another shell over the cards, then the pause menu; web only)
  [135] = function() if state().web then want("cover") end end,
  [145] = function() if state().web then want("pause") end end,
  -- talking, fighting, down
  [200] = function()
    remote.call("ai-crew", "order", 1, "Mara stay")
    member("Juno").die()
    local r = storage.rook
    for i = 1, 3 do r.surface.create_entity({ name = "medium-biter", position = { r.position.x + 9, r.position.y + i }, force = "enemy" }) end
  end,
  [250] = function()
    local st = state()
    if st.web then
      local c = by_name(st)
      check(c.Mara and c.Mara.talk ~= nil, "Mara's card: what she says (" .. tostring(c.Mara and c.Mara.talk) .. ")")
      check(c.Rook and (c.Rook.state == "fight" or c.Rook.state == "retreat"), "Rook's card: fighting (" .. tostring(c.Rook and c.Rook.state) .. ")")
      check(c.Juno and c.Juno.state == "down" and (c.Juno.back or 0) > 0, "Juno's card: down, back in " .. tostring(c.Juno and c.Juno.back) .. " s")
    else
      local l = st.lua
      check(l.Mara and l.Mara.style:find("ring") ~= nil, "Mara's card: a ring while she talks")
      check(l.Rook and l.Rook.style == "aic_card_ring_fight", "Rook's card: red while he fights (" .. tostring(l.Rook and l.Rook.style) .. ")")
      check(l.Juno and l.Juno.down == true, "Juno's card: down")
    end
    shot("states")
  end,
  -- the corner card's "Follow me": all of them follow (Mara was told to stay)
  [305] = function() if state().web then want("cmd follow") else remote.call("ai-crew", "press", 1, "follow") end end,
  -- a click on Rook's card: his pockets (a window: the game can't open his inventory for a script)
  [320] = function()  -- (Rook out of reach: his pockets)
    local p = game.get_player(1)
    storage.rook.teleport({ p.position.x + 60, p.position.y })
    if state().web then want("click Rook") else remote.call("ai-crew", "card_click", 1, "Rook") end
  end,
  [480] = function()
    local w = game.get_player(1).gui.screen.aic_pockets
    if not w and (storage.waited or 0) < 600 then return "wait" end
    local gun = w and find(w, "aic_pockets_body")
    local has = false
    for _, t in pairs(gun and gun.children or {}) do
      for _, b in pairs(t.children) do if b.sprite == "item/submachine-gun" then has = true end end
    end
    check(w and w.tags.aic_who == "Rook" and has, "Rook's card clicked, out of reach: his pockets, his gun in them")
    shot("pockets")
    if w then w.destroy() end
    -- Mara's (following: in reach): her own inventory, as clicking her does
    if state().web then want("click Mara") else remote.call("ai-crew", "card_click", 1, "Mara") end
  end,
  [500] = function()
    local p = game.get_player(1)
    if p.opened_gui_type ~= defines.gui_type.entity and (storage.waited or 0) < 1200 then return "wait" end
    check(p.opened_gui_type == defines.gui_type.entity and p.opened == member("Mara"),
      "Mara's card clicked, in reach: her inventory (" .. tostring(p.opened and p.opened.name) .. ")")
    shot("inventory")
  end,
  [510] = function() game.get_player(1).opened = nil end,
  [520] = function()
    local w = game.get_player(1).gui.screen.aic_pockets
    if w then w.destroy() end
    local mara = remote.call("ai-crew", "status", "Mara")
    check(mara and mara.mode == "follow", "the corner card's Follow me: Mara follows (" .. tostring(mara and mara.mode) .. ")")
    for _, e in pairs(game.surfaces[1].find_entities_filtered({ force = "enemy", type = "unit" })) do e.destroy() end
    remote.call("ai-crew", "panel", 1, 4)  -- (the window, its gear panel open)
  end,
  [560] = function()
    local screen = game.get_player(1).gui.screen
    local menu = screen.aic_window__menu or screen.aic_window
    check(menu and find(menu, "aic_set_cards") ~= nil, "\"Crew cards\" in the window's gear panel")
    shot("settings")
  end,
  [600] = function()
    for _, c in pairs(game.get_player(1).gui.screen.children) do
      if c.name:find("^aic_window") then c.destroy() end
    end
    remote.call("ai-crew", "setting", 1, "cards", false)
  end,
  [660] = function()
    check(count(state()) == 0, "the setting off: no cards")
    remote.call("ai-crew", "setting", 1, "cards", true)
  end,
  [720] = function()
    check(count(state()) == 4, "on again: back (" .. count(state()) .. ")")
    remote.call("ai-crew", "setting", 1, "cards-side", "bottom-right")  -- (the other side)
  end,
  [760] = function()
    local p, st = game.get_player(1), state()
    local res = p.display_resolution
    if st.web then
      local r = st.rect or { 0, 0, 0, 0 }
      check(r[1] + r[3] >= res.width - 40 * p.display_scale and r[2] > res.height / 2 and r[1] >= 0
        and r[2] + r[4] <= res.height, "\"Bottom right\": the page there (" .. serpent.line(r) .. ")")
    else
      local f = p.gui.screen.aic_hud_Rook
      check(f and f.location.x > res.width / 2 and f.location.y > res.height / 2, "\"Bottom right\": the cards there")
    end
    shot("right")
    remote.call("ai-crew", "order", 1, "crew fire Bolt")
  end,
  [820] = function()
    local st = state()
    check(count(st) == 3 and not (st.web and by_name(st).Bolt or st.lua.Bolt), "Bolt fired: his card gone, three left")
    shot("three")
  end,
  [880] = function()
    log((storage.failed or 0) == 0 and "ALL PASS" or (storage.failed .. " FAILED"))
    helpers.write_file("ac-cards-done.txt", "done")
  end,
}
-- (a step answering "wait" runs again next tick, the later ones held back as long)
script.on_event(defines.events.on_tick, function(e)
  local t = e.tick - (storage.held or 0)
  if steps[t] and steps[t]() == "wait" then
    storage.held, storage.waited = (storage.held or 0) + 1, (storage.waited or 0) + 1
  end
end)
