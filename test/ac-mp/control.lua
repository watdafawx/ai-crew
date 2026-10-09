-- AI Crew in multiplayer (fse/test/run_mp.py runs it: a headless server and one client). The joining player gets
-- two crew members and (typed into the window) a fake API key, who then work and think; an LLM order goes out. AI jobs run only on the
-- player's own peer and their answers reach every peer through native.sync: each peer writes the crew's state every
-- 5 seconds (the harness compares them at the same ticks and checks for desyncs).
script.on_init(function()
  local fp = remote.interfaces["freeplay"]
  if fp then
    if fp.set_skip_intro then remote.call("freeplay", "set_skip_intro", true) end
    if fp.set_disable_crashsite then remote.call("freeplay", "set_disable_crashsite", true) end
  end
end)

script.on_event(defines.events.on_player_joined_game, function(e)
  local p = game.get_player(e.player_index)
  for i, n in ipairs({ "Juno", "Rook" }) do
    remote.call("ai-crew", "hire", n, p.surface.name, { x = p.position.x + i * 3, y = p.position.y }, p.force.name, p.index)
  end
  storage.ask_at = e.tick + 120
end)

script.on_nth_tick(60, function(e)
  if storage.ask_at and e.tick >= storage.ask_at then
    storage.ask_at = nil
    -- (the key typed into the window's Settings tab and saved, as a player would: that tests the AI again)
    remote.call("ai-crew", "panel", 1, 4)
    local function find(el, name)
      if el.name == name then return el end
      for _, c in pairs(el.children) do local r = find(c, name) if r then return r end end
    end
    find(game.get_player(1).gui.screen.aic_window, "aic_set_key").text = "gsk_test0123456789abcd"
    remote.call("ai-crew", "press", 1, "set_save")
    remote.call("ai-crew", "order", 1, "Rook what do you think of this base?") -- (not a simple order: the LLM)
  end
  if e.tick % 300 ~= 0 then return end
  local a = remote.call("ai-crew", "ai_status", 1) or {}
  local text = ("tick %d crew %d ai %s %s"):format(e.tick, #game.surfaces[1].find_entities_filtered({ name = "crew-character" }),
    tostring(a.provider), tostring(a.error or a.testing):sub(1, 60))
  helpers.write_file("mp-server.txt", text .. "\n", true, 0)
  for _, p in pairs(game.connected_players) do helpers.write_file("mp-player-" .. p.index .. ".txt", text .. "\n", true, p.index) end
end)
