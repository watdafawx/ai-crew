-- Real client: three crew hired; a screenshot with the GUI (the minimap shows their map markers).
script.on_init(function()
  local fp = remote.interfaces["freeplay"]
  if fp then
    if fp.set_skip_intro then remote.call("freeplay", "set_skip_intro", true) end
    if fp.set_disable_crashsite then remote.call("freeplay", "set_disable_crashsite", true) end
  end
end)
script.on_event(defines.events.on_tick, function(e)
  local p = game.get_player(1)
  if e.tick == 60 then
    for i, n in ipairs({ "Rook", "Mara", "Juno" }) do
      remote.call("ai-crew", "hire", n, p.surface.name, { x = p.position.x + i * 3, y = p.position.y + 2 }, p.force.name, 1)
    end
  elseif e.tick == 180 then
    game.take_screenshot({ player = 1, path = "ac-map-minimap.png", show_gui = true })
  elseif e.tick == 240 then
    helpers.write_file("ac-map-done.txt", "done")
  end
end)
