-- Real client (through the fnative launcher): three crew, the window on each tab, a screenshot of each, the AI test,
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
    find(w, "aic_set_key").text = "gsk_test0123456789abcd"
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
  [1310] = function()
    local key = game.get_player(1).mod_settings["ai-crew-api-key"].value
    local a = remote.call("ai-crew", "ai_status", 1) or {}
    helpers.write_file("ac-gui-result.txt", string.format("key saved: %s | provider from it: %s | key shown: %s | error: %s",
      tostring(key == "gsk_test0123456789abcd"), tostring(a.provider), tostring(a.key), tostring(a.error))
      .. " | hover: " .. (game.get_player(1).gui.screen.aic_card and "card"
        or native and (native.call("entityinfo", "status", "") or ""):find('"shown":[1-9]') and "rows in the game's panel" or "nothing"))
    helpers.write_file("ac-gui-done.txt", "done")
  end,
}
script.on_event(defines.events.on_tick, function(e) if steps[e.tick] then steps[e.tick]() end end)
