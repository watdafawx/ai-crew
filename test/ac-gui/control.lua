-- Real client (through the fse launcher): three crew, the window on each tab, a screenshot of each, the AI test,
-- and the card shown hovering a crew member.
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
  local w = game.get_player(1).gui.screen.aic_window
  if w then w.location = { 40, 120 } end
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
  [1400] = function()
    local key = game.get_player(1).mod_settings["ai-crew-api-key"].value
    local a = remote.call("ai-crew", "ai_status", 1) or {}
    helpers.write_file("ac-gui-result.txt", string.format("key saved: %s | provider from it: %s | key shown: %s | error: %s",
      tostring(key == "gsk_test0123456789abcd"), tostring(a.provider), tostring(a.key), tostring(a.error))
      .. " | layout: rail " .. tostring(game.get_player(1).gui.screen.aic_window__left ~= nil) .. ", dock "
      .. tostring(game.get_player(1).gui.screen.aic_window__bottom ~= nil) .. ", fire asks "
      .. tostring(game.get_player(1).gui.screen.fstd_confirm_aic_fire ~= nil)
      .. " | settings controls: " .. tostring(storage.controls)
      .. " | hover: " .. (game.get_player(1).gui.screen.aic_card and "card"
        or native and (native.call("entityinfo", "status", "") or ""):find('"shown":[1-9]') and "rows in the game's panel" or "nothing"))
    helpers.write_file("ac-gui-done.txt", "done")
  end,
}
script.on_event(defines.events.on_tick, function(e) if steps[e.tick] then steps[e.tick]() end end)
