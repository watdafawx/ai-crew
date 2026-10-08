-- Real client (through the fnative launcher): three crew, the window on each tab, a screenshot of each, the AI test.
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
  [1290] = function()
    local key = game.get_player(1).mod_settings["ai-crew-api-key"].value
    local a = remote.call("ai-crew", "ai_status", 1) or {}
    helpers.write_file("ac-gui-result.txt", string.format("key saved: %s | provider from it: %s | key shown: %s | error: %s",
      tostring(key == "gsk_test0123456789abcd"), tostring(a.provider), tostring(a.key), tostring(a.error)))
    helpers.write_file("ac-gui-done.txt", "done")
  end,
}
script.on_event(defines.events.on_tick, function(e) if steps[e.tick] then steps[e.tick]() end end)
