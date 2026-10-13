-- Real client (through the fse launcher): three crew, the window on each tab, a screenshot of each, the AI test,
-- and the card shown hovering a crew member. Then fse-std's window scale at 150 % (0.8): drawn bigger, still on the
-- screen with its rail and dock, put back on it from the bottom right, and by the left edge with its rail showing.
-- (no crash-site intro: it pauses the game and waits for the player to press Tab)
script.on_init(function()
  local fp = remote.interfaces["freeplay"]
  if fp then
    if fp.set_skip_intro then remote.call("freeplay", "set_skip_intro", true) end
    if fp.set_disable_crashsite then remote.call("freeplay", "set_disable_crashsite", true) end
  end
end)

local function shot(name) game.take_screenshot({ player = 1, path = "ac-gui-" .. name .. ".png", show_gui = true }) end
local function tab(i)
  remote.call("ai-crew", "panel", 1, i)
  -- (by the screen's left edge, as a drag puts it: the rail is kept on the screen)
  remote.call("ai-crew", "place", 1, 40, 120)
end
-- (a frame's rectangle in pixels from the sizes fse-std keeps in its tags, at 100 %, times the scales)
local function rect(el)
  local p = game.get_player(1)
  local t = el.tags
  local w, h
  if t.fstd_attach then w, h = t.fstd_attach.w, t.fstd_attach.h
  elseif type(t.fstd_tweak) == "table" and t.fstd_tweak.width then w, h = t.fstd_tweak.width, t.fstd_tweak.height
  else w, h = 640, 470 end
  local sc = p.display_scale * (t.fstd_scale or (t.fstd_attach and p.gui.screen.aic_window.tags.fstd_scale) or 1)
  return el.location.x, el.location.y, w * sc, h * sc
end
-- "on screen" or what sticks out: the window, its rail and dock
local function on_screen(full)
  local p = game.get_player(1)
  local res = p.display_resolution
  local out = {}
  for _, n in ipairs({ "aic_window", "aic_window__left", "aic_window__bottom" }) do
    local el = p.gui.screen[n]
    if el and el.location then
      local x, y, w, h = rect(el)
      local bottom = full and (y + h) or (y + 30 * p.display_scale)
      if x < 0 or y < 0 or x + w > res.width + 1 or bottom > res.height + 1 then
        out[#out + 1] = string.format("%s %d,%d %dx%d", n, x, y, w, h)
      end
    end
  end
  return #out == 0 and "on screen" or ("OFF " .. table.concat(out, "; "))
end
local function scale_line(what)
  local p = game.get_player(1)
  local w = p.gui.screen.aic_window
  storage.scale = (storage.scale or "") .. string.format(" | %s: scale %s, %s (%dx%d at ui %s)", what,
    tostring(w and w.tags.fstd_scale), on_screen(what ~= "left edge"), p.display_resolution.width,
    p.display_resolution.height, p.display_scale)
end
local steps = {
  [60] = function()
    local p = game.get_player(1)
    for i, n in ipairs({ "Juno", "Mara", "Rook" }) do
      remote.call("ai-crew", "hire", n, p.surface.name, { x = p.position.x + i * 3, y = p.position.y }, p.force.name, 1)
    end
    tab(1)
  end,
  [150] = function() shot("crew") end,
  [180] = function() tab(2) end,
  [210] = function() shot("orders") end,
  [240] = function() tab(3) end,
  [270] = function() shot("goal") end,
  [300] = function()
    tab(4)
    local w = game.get_player(1).gui.screen.aic_window
    local function find(el, name) if el.name == name then return el end for _, c in pairs(el.children) do local r = find(c, name) if r then return r end end end
    -- (the settings are behind the gear by the close button now: a panel of their own on the screen)
    local menu = game.get_player(1).gui.screen.aic_window__menu
    find(menu or w, "aic_set_key").text = "gsk_test0123456789abcd"
    remote.call("ai-crew", "press", 1, "set_save")
  end,
  [1200] = function() shot("ai") end, -- (after the AI test came back)
  [1230] = function() tab(1) end,
  [1260] = function() shot("crew2") end,
  [1265] = function() -- the hover card: Rook armed and carrying a few things, the cursor on him
    local p = game.get_player(1)
    local st = remote.call("ai-crew", "status", "Rook")
    local rook = p.surface.find_entities_filtered({ name = "crew-character", position = st.position, radius = 0.3 })[1]
    rook.get_inventory(defines.inventory.character_armor).insert({ name = "heavy-armor", count = 1 })
    rook.get_inventory(defines.inventory.character_guns).insert({ name = "submachine-gun", count = 1 })
    rook.get_inventory(defines.inventory.character_ammo).insert({ name = "firearm-magazine", count = 40 })
    for _, it in ipairs({ { "raw-fish", 12 }, { "iron-plate", 80 }, { "coal", 25 }, { "stone-furnace", 3 } }) do rook.insert({ name = it[1], count = it[2] }) end
    p.selected = rook
  end,
  [1300] = function() shot("card") end,
  -- the window's layout: its settings behind the gear, Docked off (all inside), Fire asking first
  [1302] = function() game.get_player(1).selected = nil remote.call("ai-crew", "press", 1, "settings") end,
  [1330] = function()
    shot("settings")
    -- the settings' controls, the newer ones too: which are there
    local screen = game.get_player(1).gui.screen
    if not screen.aic_window__menu then remote.call("ai-crew", "press", 1, "settings") end -- (opened, if it was shut)
    local menu = screen.aic_window__menu or screen.aic_window
    local function find(el, name) if el.name == name then return el end for _, c in pairs(el.children) do local r = find(c, name) if r then return r end end end
    local missing = {}
    for _, n in ipairs({ "aic_set_voice-volume", "aic_set_ada-volume", "aic_set_lines-llm", "aic_set_machines",
      "aic_set_back-after-orders", "aic_set_tier-upgrades", "aic_set_new_mode", "aic_set_ada_voice" }) do
      if not (menu and find(menu, n)) then missing[#missing + 1] = n end
    end
    storage.controls = #missing == 0 and "all there" or ("missing " .. table.concat(missing, ","))
  end,
  [1332] = function()
    local screen = game.get_player(1).gui.screen
    if screen.aic_window__menu then screen.aic_window__menu.destroy() end
    remote.call("ai-crew", "docked", 1, false)
  end,
  [1360] = function() shot("inside") end,
  [1362] = function()
    remote.call("ai-crew", "docked", 1, true)
    -- (as the player's press: a question first)
    local w = game.get_player(1).gui.screen.aic_window
    local function find(el) if el.tags and el.tags.aic == "fire" then return el end for _, c in pairs(el.children) do local r = find(c) if r then return r end end end
    local b = find(w)
    if b then remote.call("ai-crew", "press", 1, "fire", b.tags.who, true) end
  end,
  [1390] = function() shot("fire") end,
  -- the window scale: from the bottom right at 100 % (half off the screen), then 150 %: brought back on the screen
  [1392] = function()
    local screen = game.get_player(1).gui.screen
    storage.fire_asks = screen.fstd_confirm_aic_fire ~= nil
    if screen.fstd_confirm_aic_fire then screen.fstd_confirm_aic_fire.destroy() end
    remote.call("ai-crew", "place", 1, 9999, 9999)
  end,
  [1394] = function()
    if remote.interfaces["fse-std"].set_window_scale then remote.call("fse-std", "set_window_scale", 1, 150) end
  end,
  [1400] = function() scale_line("150 %") remote.call("ai-crew", "press", 1, "settings") end,
  [1420] = function() shot("scale150") end,  -- (with its settings: Size after Docked)
  [1440] = function()
    local screen = game.get_player(1).gui.screen
    local function find(el, t) if el.type == t and el.tags.fstd_scale_pick then return el end for _, c in pairs(el.children) do local r = find(c, t) if r then return r end end end
    storage.size = screen.aic_window__menu and find(screen.aic_window__menu, "drop-down") and "there" or "missing"
    if screen.aic_window__menu then screen.aic_window__menu.destroy() end
    remote.call("ai-crew", "place", 1, 0, 120)  -- (by the left edge: the rail kept on the screen)
  end,
  [1445] = function() scale_line("left edge") end,
  [1470] = function() shot("scale150-left") end,
  [1500] = function()
    local key = game.get_player(1).mod_settings["ai-crew-api-key"].value
    local a = remote.call("ai-crew", "ai_status", 1) or {}
    helpers.write_file("ac-gui-result.txt", string.format("key saved: %s | provider from it: %s | key shown: %s | error: %s",
      tostring(key == "gsk_test0123456789abcd"), tostring(a.provider), tostring(a.key), tostring(a.error))
      .. " | layout: rail " .. tostring(game.get_player(1).gui.screen.aic_window__left ~= nil) .. ", dock "
      .. tostring(game.get_player(1).gui.screen.aic_window__bottom ~= nil) .. " (width "
      .. tostring(game.get_player(1).gui.screen.aic_window__bottom and game.get_player(1).gui.screen.aic_window__bottom.tags.fstd_attach.w)
      .. " under a 640 window), fire asks "
      .. tostring(storage.fire_asks)
      .. " | settings controls: " .. tostring(storage.controls) .. ", Size " .. tostring(storage.size)
      .. tostring(storage.scale)
      .. " | rail x " .. tostring(game.get_player(1).gui.screen.aic_window__left and game.get_player(1).gui.screen.aic_window__left.location.x)
      .. " | hover: " .. (game.get_player(1).gui.screen.aic_card and "card"
        or native and (native.call("entityinfo", "status", "") or ""):find('"shown":[1-9]') and "rows in the game's panel" or "nothing"))
    helpers.write_file("ac-gui-done.txt", "done")
  end,
}
script.on_event(defines.events.on_tick, function(e) if steps[e.tick] then steps[e.tick]() end end)
