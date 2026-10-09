-- Real client (fse launcher): rows of our own in the game's entity info panel (fse plugin "entityinfo").
-- Rook is hired, armed and hovered; the runner grabs the game window (ac-info-screen.png): the panel under the minimap
-- with AI Crew's rows. Without the fse loader this test can't run (the Lua card is ac-gui's).
script.on_init(function()
  local fp = remote.interfaces["freeplay"]
  if fp then
    if fp.set_skip_intro then remote.call("freeplay", "set_skip_intro", true) end
    if fp.set_disable_crashsite then remote.call("freeplay", "set_disable_crashsite", true) end
  end
end)

local out = {}
local function log(s) out[#out + 1] = s helpers.write_file("ac-info-result.txt", table.concat(out, "\n") .. "\n") end

script.on_event(defines.events.on_tick, function(ev)
  local t = ev.tick
  local p = game.get_player(1)
  if not p then return end
  if storage.hover and storage.hover.valid then p.selected = storage.hover end -- (the real mouse is elsewhere: held)
  if t == 60 then
    p.insert({ name = "raw-fish", count = 50 }) -- (no fishing trip: Rook stays put to be hovered)
    remote.call("ai-crew", "hire", "Rook", p.surface.name, { x = p.position.x + 3, y = p.position.y }, p.force.name, 1)
  elseif t == 90 then
    local rook = p.surface.find_entities_filtered({ name = "crew-character", position = p.position, radius = 8 })[1]
    storage.rook = rook
    rook.get_inventory(defines.inventory.character_guns).insert({ name = "submachine-gun", count = 1 })
    rook.get_inventory(defines.inventory.character_ammo).insert({ name = "firearm-magazine", count = 40 })
    rook.get_inventory(defines.inventory.character_armor).insert({ name = "heavy-armor", count = 1 })
    rook.insert({ name = "iron-plate", count = 80 })
  elseif t == 120 then
    storage.chest = p.surface.create_entity({ name = "iron-chest", position = { p.position.x - 3, p.position.y }, force = p.force })
    storage.hover = storage.chest
  elseif t == 140 then
    game.take_screenshot({ player = 1, path = "ac-info-chest.png", show_gui = true })
    log("selected chest: " .. tostring(p.selected and p.selected.name))
    storage.hover = storage.rook
  elseif t == 160 then
    game.take_screenshot({ player = 1, path = "ac-info-panel.png", show_gui = true })
    log("selected rook: " .. tostring(p.selected and p.selected.name))
    helpers.write_file("ac-info-grab.txt", "now") -- (the runner grabs the real screen: the panel isn't in screenshots)
  elseif t == 400 then
    local st = helpers.json_to_table(native.call("entityinfo", "status", "") or "{}") or {}
    log("status: " .. serpent.line(st))
    local ok = (st.shown or 0) > 0 and p.gui.screen.aic_card == nil
    log((ok and "PASS" or "FAIL") .. " the crew's rows went into the game's info panel (" .. tostring(st.shown) .. " times), no card of our own")
    log(ok and "ALL PASS" or "1 FAILED")
    helpers.write_file("ac-info-done.txt", "done")
  end
end)
