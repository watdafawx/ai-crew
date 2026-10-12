-- AI Crew: the window (the crew button, top left), its settings, the hover card, and their GUI events. One of
-- control.lua's files.

-- (the other files' that this one uses: set by link, at the end)
local ai_state, CREW, crew, DOING_WORD, find_member, goal_have, gun_range, jobs, llm_settings, MAX_CREW, members_of,
  needs, order, player_setting, pretty, py, speak, trait

-- ------------------------------------------------------------------------------------------------------------ panel
-- The crew button (top left) opens a window: movable and resizable with the fse-std library, a plain movable one
-- without. The chat box, then tabs: Crew, Orders, Goal, AI.

local mod_gui = require("mod-gui")
local fstd = script.active_mods["fse-std"] and require("__fse-std__/window") or nil
-- themes (fse-std 0.6+): the window in the player's theme from fse-std's theme window
local theme = fstd and (function()
  local ok, t = pcall(require, "__fse-std__/theme")
  return ok and t.adopt and t or nil
end)()
local WIN = "aic_window"
local PROVIDER_CHOICES, TOGGLES
local ADA_VOICES = { "heart", "sarah", "nova", "sky", "alice", "lily" } -- (aicrew.py's ADA_VOICES: Kokoro's)

local function goal_text(owner)
  local nd = needs(owner)[1]
  if nd then
    return string.format("Working for: %s %s%s%s%s", nd.count and (goal_have(owner, nd.item) .. " / " .. nd.count) or nd.more,
      pretty(nd.item), nd.reason and (" (for " .. nd.reason .. ")") or "", nd.step and (" - " .. nd.step) or "",
      #needs(owner) > 1 and (", then " .. (#needs(owner) - 1) .. " more") or "")
  end
  local g = storage.goals and storage.goals[owner]
  if not g then return "No goal. Pick an item and how many you want to have: the crew mine, smelt, craft and build towards it." end
  return string.format("Goal: %d / %d %s%s%s", goal_have(owner, g.item), g.count, pretty(g.item),
    g.line and (g.line.state == "asked" and " - bpgen is planning a line" or " (line)") or "",
    g.why and (" - " .. g.why) or (g.step and (" - " .. g.step) or ""))
end

local function status_text(m)
  if m.retreat then return "falling back, hurt" end
  if m.target and m.target.valid then return "fighting " .. pretty(m.target.name) end
  local j = m.jobs[1]
  if not j then return m.roam and "roaming" or m.follow and "following you" or "waiting here" end
  local s = DOING_WORD[j.kind] or j.kind
  if j.kind == "mine" then s = s .. " " .. pretty(j.item) .. " " .. (j.n or 0) .. "/" .. j.count
  elseif j.kind == "craft" or j.kind == "fetch" then s = s .. " " .. j.count .. " " .. pretty(j.recipe or j.item)
  elseif j.kind == "smelt" or j.kind == "feed" or j.kind == "place" then s = s .. " " .. pretty(j.item or j.recipe or "")
  elseif j.auto then s = s .. " (auto)" end
  if #m.jobs > 1 then s = s .. " +" .. (#m.jobs - 1) end
  return s
end

local function ui(player)
  storage.ui = storage.ui or {}
  storage.ui[player.index] = storage.ui[player.index] or { count = "50", who = 1 }
  return storage.ui[player.index]
end

-- the AI tab's lines: loader, provider and key, the last test, voices
local function ai_lines(player)
  local a = ai_state()[player.index]
  local llm = llm_settings(player)
  local out = {}
  if not py() then
    out[1] = "[color=1,0.4,0.4]Not started through the fse loader:[/color] chat, voices and bpgen lines are off. Orders, goals and building work."
    return out
  end
  if llm.provider == "off" then out[1] = "Chat AI is off (provider above). Plain orders still work." return out end
  if not a then out[1] = "Not tested yet: press Test." return out end
  if a.provider then
    out[#out + 1] = "Provider: " .. a.provider .. (a.key and ("   key " .. a.key) or "") .. (a.source and ("  (from " .. a.source .. ")") or "")
  end
  if a.model then out[#out + 1] = "Model: " .. a.model end
  out[#out + 1] = a.ok and string.format("[color=0.4,1,0.4]Connected[/color]: answered in %.1f s.", a.seconds or 0)
    or ("[color=1,0.4,0.4]Not working[/color]: " .. tostring(a.error))
  out[#out + 1] = "Voices: " .. tostring(a.tts or "-")
  return out
end

PROVIDER_CHOICES = { "auto", "openrouter", "groq", "gemini", "cerebras", "mistral", "pollinations", "ollama", "off" }
TOGGLES = {
  { "voices", "Crew speak out loud", "Text to speech for the crew's lines: Kokoro's voices, made on your computer" },
  { "ada", "ADA announces milestones", "Research done, first science, rocket launches, deaths" },
  { "ada-llm", "ADA words her lines with the AI", "One AI request per announcement" },
  { "lines-llm", "Crew word their lines with the AI", "Their news (biters, a nest, research, fishing...) in their own words: one AI request per line said out loud. Without an AI that answers, the stock lines" },
  { "chatter", "Crew chatter while you're away", "After 2 minutes without input, every minute or so" },
  { "hints", "Crew give hints", "Research to start, starved or backed-up machines, power, oversupply, what to do next when nothing's happened for 5 minutes" },
  { "machines", "Crew build machines", "When something they need is only made in a machine (plates in a furnace) and none is free, they may put one down. Off: never; they use your machines and fetch what's made from chests and belts first either way" },
  { "back-after-orders", "Back where they stood after orders", "Sent off to get, mine, craft, build or deliver something, they go back to where they stood once it's done and there's nothing more to do (when more than 16 tiles away, and unless they roam or follow you). Off: they stay where the work ended" },
  { "jetpack", "Crew jetpacks", "They fly over what's in their way (and to a fight); off: they step through it a few tiles at a time" },
  { "tier-upgrades", "Crew upgrade to better tiers", "Roaming, they swap machines, inserters and furnaces for the next tier when it's already in your pockets, chests or network (never made for it). Not belts" },
}

local function ai_short(player)
  local a = ai_state()[player.index]
  if not py() then return "[color=0.7,0.7,0.7]AI chat off (no fse loader)[/color]" end
  if not a then return "[color=0.7,0.7,0.7]AI chat not tested (settings: the gear by the close button)[/color]" end
  return a.ok and ("[color=0.4,1,0.4]AI chat: " .. tostring(a.provider) .. "[/color]") or "[color=1,0.4,0.4]AI chat not working (settings: the gear by the close button)[/color]"
end

local function check_ai(player)
  if not py() then return end
  if jobs.start(player.index, "aicrew:check", helpers.table_to_json({ llm = llm_settings(player) }),
         { kind = "check", owner = player.index }) then
    ai_state()[player.index] = ai_state()[player.index] or {}
    ai_state()[player.index].testing = true
  end
end

local function add_button(player)
  local flow = mod_gui.get_button_flow(player)
  if not flow.aic_toggle then
    flow.add({ type = "sprite-button", name = "aic_toggle", sprite = "entity/" .. CREW, style = mod_gui.button_style,
      tooltip = "AI Crew" })
  end
end

local function btn(parent, caption, action, who, tooltip, width)
  local b = parent.add({ type = "button", caption = caption, tags = { aic = action, who = who }, tooltip = tooltip })
  b.style.minimal_width = 0
  b.style.width = width or 72
  return b
end

local function find_el(root, name)
  if root.name == name then return root end
  for _, c in pairs(root.children) do
    local r = find_el(c, name)
    if r then return r end
  end
  if root.name == WIN then  -- (and in the frames stuck to the window: its rail, dock, settings)
    for _, c in pairs(game.get_player(root.player_index).gui.screen.children) do
      local a = c.tags.fstd_attach
      if a and a.owner == WIN and c.get_mod() == script.mod_name then
        local r = find_el(c, name)
        if r then return r end
      end
    end
  end
end

local function new_window(player)
  if fstd then
    return fstd.create(player, { name = WIN, title = "AI Crew", width = 640, height = 470, min_width = 520, min_height = 320,
      themed = theme ~= nil, settings = theme ~= nil and theme.menu ~= nil })
  end
  local screen = player.gui.screen
  if screen[WIN] then screen[WIN].destroy() end
  local frame = screen.add({ type = "frame", name = WIN, direction = "vertical" })
  local bar = frame.add({ type = "flow", direction = "horizontal" })
  bar.drag_target = frame
  bar.add({ type = "label", caption = "AI Crew", style = "frame_title", ignored_by_interaction = true })
  local filler = bar.add({ type = "empty-widget", style = "draggable_space_header", ignored_by_interaction = true })
  filler.style.height = 24
  filler.style.horizontally_stretchable = true
  bar.add({ type = "sprite-button", style = "frame_action_button", sprite = "utility/close", tags = { aic = "close" } })
  frame.style.width = 640
  frame.style.height = 470
  if ui(player).loc then frame.location = ui(player).loc else frame.force_auto_center() end
  local content = frame.add({ type = "frame", style = "inside_shallow_frame_with_padding", direction = "vertical" })
  content.style.horizontally_stretchable = true
  content.style.vertically_stretchable = true
  return frame, content
end

local function row(parent)
  local r = parent.add({ type = "flow", direction = "horizontal" })
  r.style.vertical_align = "center"
  r.style.horizontal_spacing = 6
  return r
end

local function note(parent, text, name)
  local l = parent.add({ type = "label", caption = text, name = name })
  l.style.single_line = false
  l.style.horizontally_stretchable = true
  return l
end

-- The window as bpgen's (fse/README.md, "A window's layout"): the pages (Crew, Orders, Goal) on a rail out of the
-- window's left edge, the crew-wide orders on a dock below it, the chat box pinned at the bottom, the settings behind
-- the gear by the close button. "Docked" off in the gear's panel, or without fse-std's layouts: all inside.
local function build_panel(player)
  for _, a in pairs(player.gui.screen.children) do  -- (the rail and dock it had: made again below, or not at all)
    local t = a.tags.fstd_attach
    if t and t.owner == WIN and a.name ~= WIN .. "__menu" and a.get_mod() == script.mod_name then a.destroy() end
  end
  local frame, c = new_window(player)
  local st = ui(player)
  local members = members_of(player.index)
  local docked = theme ~= nil and theme.dock ~= nil and not st.inside
  local pages = { "Crew", "Orders", "Goal" }
  st.tab = math.min(st.tab or 1, #pages)  -- (the Settings page went behind the gear)
  local sel
  if docked then
    local rail = theme.attach(frame, "left", { size = { 112, #pages * 34 + 8 }, along = 40, overlap = 6, role = "inset",
      direction = "vertical", padding = 4 })
    sel = rail.add({ type = "flow", name = "aic_tabs", direction = "vertical" })
    sel.style.vertical_spacing = 4
  else
    sel = c.add({ type = "flow", name = "aic_tabs", direction = "horizontal" })
    sel.style.horizontal_spacing = 4
    sel.style.bottom_margin = 6
  end
  for i, n in ipairs(pages) do
    local b = sel.add({ type = "button", caption = n, toggled = i == st.tab, tags = { aic = "tab", who = i } })
    if theme then
      theme.apply(b, docked and "rtab" or "tab", docked and { width = 104, height = 30 } or { minimal_width = 80, height = 30 })
    else
      b.style.minimal_width = 80
    end
  end
  local scroll = c.add({ type = "scroll-pane", name = "aic_pages", horizontal_scroll_policy = "never",
    vertical_scroll_policy = "auto" })
  scroll.style.vertically_stretchable = true
  scroll.style.horizontally_stretchable = true
  local function page(i)
    local body = scroll.add({ type = "flow", direction = "vertical", visible = i == st.tab })
    body.style.vertical_spacing = 8
    body.style.horizontally_stretchable = true
    return body
  end

  -- Crew: a few numbers, a row each (Fire asks first), hiring; the orders for everyone (on the dock when docked)
  local crew_tab = page(1)
  local top = row(crew_tab)
  if theme then
    local jobs_n = 0
    for _, m in pairs(members) do jobs_n = jobs_n + #m.jobs end
    local fixed = { horizontally_stretchable = false, minimal_width = 110 }
    theme.apply(theme.stat(top, #members .. " / " .. MAX_CREW, "crew"), "stat", fixed)
    theme.apply(theme.stat(top, tostring(jobs_n), "jobs queued"), "stat", fixed)
  end
  note(crew_tab, ai_short(player), "aic_ai_short")
  local t = crew_tab.add({ type = "table", name = "aic_crew", column_count = 7 })
  t.style.vertical_align = "center"
  t.style.horizontal_spacing = 6
  for _, m in pairs(members) do
    local col = m.color
    local n = t.add({ type = "label", caption = string.format("[font=default-bold][color=%g,%g,%g]%s[/color][/font]", col[1], col[2], col[3], m.name) })
    n.style.width = 56
    local l = t.add({ type = "label", name = "aic_status_" .. m.name, caption = status_text(m) })
    l.style.width = 190
    t.add({ type = "checkbox", caption = "Fight", state = m.defend ~= false, tags = { aic = "defend", who = m.name },
      tooltip = "Arms itself (best armor and gun from your stock, or makes them), shoots enemies in range, falls back to you when hurt" })
    t.add({ type = "checkbox", caption = "Auto", state = m.auto ~= false, tags = { aic = "auto", who = m.name },
      tooltip = "Clears deconstruction marks and builds ghosts near you on its own, making what's missing" })
    btn(t, m.roam and "Roam" or m.follow and "Follow" or "Stay", "mode", m.name,
      "Follow: stays with you. Roam: wanders round you on its own, dealing with what it finds. Stay: holds here. Click to switch.", 64)
    btn(t, "Stop", "stop", m.name, "Drop all its jobs", 56)
    btn(t, "Fire", "fire", m.name, "Dismiss (it hands over what it carries)", 52)
  end
  if #members == 0 then note(crew_tab, "No crew yet. Hire someone: they spawn next to you.") end
  local r = row(crew_tab)
  btn(r, "Hire", "hire", nil, "Up to " .. MAX_CREW, 64).enabled = #members < MAX_CREW
  r.add({ type = "textfield", name = "aic_name", tooltip = "Name (optional)" }).style.width = 120
  if #members > 0 then
    local function everyone(parent, label)
      local e = row(parent)
      if label then e.add({ type = "label", caption = "Everyone:" }) end
      btn(e, "Build", "build", nil, "Place the ghosts near you now (making what's missing)", 64)
      btn(e, "Clear", "deconstruct", nil, "Remove what's marked for deconstruction near you", 64)
      btn(e, "Upgrade", "upgrade", nil, "Carry out the upgrade planner's marks near you (making the new pieces); recipes and contents kept", 76)
      btn(e, "Deliver", "deliver", nil, "Bring you everything they carry", 72)
      if label then
        e = row(parent)
        e.add({ type = "label", caption = "Everyone:" }).style.font_color = { 0, 0, 0, 0 } -- (lines up with the row above)
      end
      btn(e, "Come", "follow", nil, "Follow you", 64)
      btn(e, "Roam", "roam", nil, "Wander round you on their own, dealing with what they find", 64)
      btn(e, "Stop", "stop", nil, "Drop all jobs", 56)
      btn(e, "Clear nests", "attack", nil, "Destroy the enemy spawners and worms within 96 tiles of you", 100)
    end
    if docked then  -- (a toolbar hanging below the window: orders for everyone, whichever page is open)
      local d = theme.dock(frame, { size = { 660, 44 } })
      local e = d.add({ type = "flow", direction = "horizontal" })
      e.style.horizontally_stretchable, e.style.horizontal_align = true, "center"
      everyone(e, false)
    else
      crew_tab.add({ type = "line" })
      everyone(crew_tab, true)
    end
  end

  -- Orders
  local orders = page(2)
  local names = { "Anyone" }
  for _, m in pairs(members) do names[#names + 1] = m.name end
  st.who = math.min(st.who or 1, #names)
  r = row(orders)
  r.add({ type = "drop-down", name = "aic_who", items = names, selected_index = st.who, tooltip = "Who gets the order or the message" })
  r.add({ type = "choose-elem-button", name = "aic_item", elem_type = "item", item = st.item, tooltip = "Item" })
  r.add({ type = "textfield", name = "aic_count", text = st.count, numeric = true, allow_decimal = false,
    allow_negative = false, tooltip = "How many" }).style.width = 60
  btn(r, "Get", "get", nil, "From chests or the network if there; else mined, crafted or made in a machine; brought to you", 56)
  btn(r, "Mine", "mine", nil, "Mine it by hand (ore, stone, coal, wood...)", 56)
  btn(r, "Craft", "craft", nil, "Hand-craft it", 60)
  note(orders, "Get works for anything: what isn't around they mine, craft or make in a machine (building the machine and its power if need be). Or type it in the box below: \"get 50 iron plate\", \"craft 10 gears\", \"attack\".")

  -- Goal: what to have, how far it is (a bar red to green), what they're working for
  local goal = page(3)
  r = row(goal)
  r.add({ type = "choose-elem-button", name = "aic_goal_item", elem_type = "item", item = st.goal_item,
    tooltip = "What to have: the crew work towards it whenever there's nothing to build or clear" })
  r.add({ type = "textfield", name = "aic_goal_count", text = st.goal_count or "100", numeric = true,
    allow_decimal = false, allow_negative = false, tooltip = "How many to have (your pockets, chests near you, the network, the crew)" }).style.width = 60
  local bp = remote.interfaces["bpgen"] and remote.interfaces["bpgen"].plan_line
  r.add({ type = "checkbox", name = "aic_goal_line", caption = "Production line", state = bp and st.goal_line ~= false or false,
    enabled = bp ~= nil, tooltip = bp and "bpgen plans a line next to your base for it; the crew build, power, feed and empty it"
      or "Needs bpgen (zzz-bpgen) and the fse loader" })
  r.add({ type = "textfield", name = "aic_goal_rate", text = st.goal_rate or "30", numeric = true,
    allow_decimal = false, allow_negative = false, tooltip = "The line's rate, per minute" }).style.width = 45
  r.add({ type = "label", caption = "/min" })
  btn(r, "Set", "goal_set", nil, "Start on it", 56)
  btn(r, "Clear", "goal_clear", nil, "Drop the goal and what they're working for", 60)
  local g = storage.goals and storage.goals[player.index]
  if theme and g then
    local have = goal_have(player.index, g.item)
    theme.progress(goal, math.min(1, have / math.max(1, g.count)), { caption = pretty(g.item), auto = true,
      text = have .. " / " .. g.count }).name = "aic_goal_bar"
  end
  note(goal, goal_text(player.index), "aic_goal_status")

  -- the chat box, pinned under the pages: always in sight
  if #members > 0 then
    local cr = row(c)
    cr.style.top_margin = 6
    local chat = cr.add({ type = "textfield", name = "aic_chat",
      tooltip = "Talk to the crew (to whoever the Orders page picks). Plain orders run as is; the rest goes to the AI. Enter sends." })
    chat.style.horizontally_stretchable = true
    chat.style.maximal_width = 1000
    local send = btn(cr, "Send", "send", nil, "Enter also sends", 90)
    if theme then theme.apply(send, "ok", { width = 90, minimal_width = 0 }) end
  end
  if theme then
    theme.adopt(frame)
    for _, a in pairs(player.gui.screen.children) do
      if a.tags.fstd_attach and a.tags.fstd_attach.owner == WIN and a.get_mod() == script.mod_name then theme.adopt(a) end
    end
  end

  if py() and not ai_state()[player.index] then check_ai(player) end
end

local function open_frame(player) return player.gui.screen[WIN] end

local function refresh(player)
  local f = open_frame(player)
  if not f then return end
  local members = members_of(player.index)
  local t = find_el(f, "aic_crew")
  if not t or #t.children ~= #members * 7 then return build_panel(player) end
  for _, m in pairs(members) do
    local l = find_el(t, "aic_status_" .. m.name)
    if not l then return build_panel(player) end
    l.caption = status_text(m)
  end
  local g = find_el(f, "aic_goal_status")
  if g then g.caption = goal_text(player.index) end
  local gb, goal = find_el(f, "aic_goal_bar"), storage.goals and storage.goals[player.index]
  if gb and goal and theme then
    local have = goal_have(player.index, goal.item)
    theme.set_progress(gb, math.min(1, have / math.max(1, goal.count)), have .. " / " .. goal.count)
  end
  local s = find_el(f, "aic_ai_short")
  if s then s.caption = ai_short(player) end
  local lines = ai_lines(player)
  for i = 1, 6 do
    local l = find_el(f, "aic_ai_" .. i)
    if l then l.caption = lines[i] or "" end
  end
  -- (the AI's lines are in the settings: all of them shown again when those are opened)
end

-- the drop-down's pick: a member's name, or "crew" for anyone
local function who_of(f)
  local dd = f and find_el(f, "aic_who")
  local i = dd and dd.selected_index or 1
  return i > 1 and dd.items[i] or "crew"
end

local function act(player, action, who, scripted)
  local f = open_frame(player)
  local st = ui(player)
  local function tell(text)  -- (a toast with the theme library, else the chat)
    if theme and theme.toast then theme.toast(player, text) else player.print(text) end
  end
  if action == "close" then
    for _, c in pairs(player.gui.screen.children) do
      if c.tags.fstd_attach and c.tags.fstd_attach.owner == WIN and c.get_mod() == script.mod_name then c.destroy() end
    end
    if f then f.destroy() end
    return
  elseif action == "tab" then
    st.tab = who
  elseif action == "theme" then
    local menu = player.gui.screen[WIN .. "__menu"]
    if menu then menu.destroy() end
    return remote.call("fse-std", "open_theme", player.index)
  elseif action == "reset_size" then
    if storage.fstd_windows and storage.fstd_windows[player.index] then storage.fstd_windows[player.index][WIN] = nil end
    st.loc = nil
  elseif action == "settings" then
    -- the window's settings, behind the gear by its close button (fse-std's theme.menu): the AI (provider, key,
    -- model, its test), ADA and the voices, what the crew do on their own, and the window's own (docked, theme, size)
    local m = f and theme and theme.menu and theme.menu(f, { size = { 460, 470 } })
    if not m then return end
    local head = row(m)
    head.add({ type = "label", caption = "AI Crew" }).style.font = "default-bold"
    head.add({ type = "empty-widget" }).style.horizontally_stretchable = true
    if theme.dock then
      head.add({ type = "checkbox", name = "aic_docked", caption = "Docked", state = not ui(player).inside,
        tooltip = "The pages on the window's left edge and the orders for everyone below it; unticked, all inside it" })
    end
    local scroll = m.add({ type = "scroll-pane", horizontal_scroll_policy = "never", vertical_scroll_policy = "auto" })
    scroll.style.vertically_stretchable, scroll.style.horizontally_stretchable = true, true
    local ai = theme.fold(scroll, "AI chat", true)
    local set = ai.add({ type = "table", column_count = 2 })
    set.style.vertical_align = "center"
    set.style.horizontal_spacing = 12
    set.style.vertical_spacing = 6
    set.add({ type = "label", caption = "Provider" })
    local cur = player_setting(player, "ai-crew-provider") or "auto"
    local sel = 1
    for i, v in ipairs(PROVIDER_CHOICES) do if v == cur then sel = i end end
    set.add({ type = "drop-down", name = "aic_set_provider", items = PROVIDER_CHOICES, selected_index = sel,
      tooltip = "auto: picked from the key (sk-or- OpenRouter, gsk_ Groq, AIza Gemini, csk- Cerebras, sk_ Pollinations). off: plain orders only." })
    set.add({ type = "label", caption = "API key" })
    local key = set.add({ type = "textfield", name = "aic_set_key", text = player_setting(player, "ai-crew-api-key") or "",
      tooltip = "Free keys: openrouter.ai/keys, console.groq.com/keys, aistudio.google.com/apikey, cloud.cerebras.ai. Saved in your mod settings." })
    key.style.width = 300
    key.is_password = true
    set.add({ type = "label", caption = "Model" })
    set.add({ type = "textfield", name = "aic_set_model", text = player_setting(player, "ai-crew-model") or "",
      tooltip = "Blank: picked for you (on OpenRouter, a current free model)" }).style.width = 300
    local r = row(ai)
    btn(r, "Save & test", "set_save", nil, "Save the provider, key and model, then ask the AI one short question", 110).enabled = py()
    btn(r, "Test", "ai_test", nil, "Ask the AI one short question now", 64).enabled = py()
    for i, line in ipairs(ai_lines(player)) do note(ai, line, "aic_ai_" .. i).style.maximal_width = 400 end
    local voice = theme.fold(scroll, "ADA and voices", false)
    r = row(voice)
    r.add({ type = "label", caption = "ADA voice" })
    local cur_v = player_setting(player, "ai-crew-ada-voice") or "heart"
    local vi = 1
    for i, v in ipairs(ADA_VOICES) do if v == cur_v then vi = i end end
    r.add({ type = "drop-down", name = "aic_set_ada_voice", items = ADA_VOICES, selected_index = vi,
      tooltip = "ADA's Kokoro voice (alice and lily British) under her effects (chorus and a detuned echo; they need ffmpeg)" })
    btn(r, "Hear", "ada_hear", nil, "ADA says a line in this voice", 60).enabled = py()
    for _, v in ipairs({ { "voice-volume", "Crew volume" }, { "ada-volume", "ADA volume" } }) do -- (0 to 100 %)
      r = row(voice)
      local cur = player_setting(player, "ai-crew-" .. v[1]) or 100
      r.add({ type = "label", caption = v[2] }).style.minimal_width = 90
      r.add({ type = "slider", name = "aic_set_" .. v[1], minimum_value = 0, maximum_value = 100, value = cur, value_step = 5,
        tooltip = "How loud " .. (v[1] == "ada-volume" and "ADA (and her chime) is" or "the crew's voices are") })
      r.add({ type = "label", name = "aic_vol_" .. v[1], caption = cur .. "%" })
    end
    local own = theme.fold(scroll, "What the crew do", false)
    r = row(own)
    r.add({ type = "label", caption = "New crew" })
    local modes, cur_m, mi = { "roam", "follow", "stay" }, player_setting(player, "ai-crew-new-mode") or "roam", 1
    for i, v in ipairs(modes) do if v == cur_m then mi = i end end
    r.add({ type = "drop-down", name = "aic_set_new_mode", items = modes, selected_index = mi,
      tooltip = "What a crew member you hire does: roam the base (and come to you when you're attacked), follow, or stay" })
    for i, c in ipairs(TOGGLES) do
      local parent = (c[1] == "voices" or c[1] == "lines-llm" or c[1] == "ada" or c[1] == "ada-llm") and voice or own
      parent.add({ type = "checkbox", name = "aic_set_" .. c[1], caption = c[2], state = player_setting(player, "ai-crew-" .. c[1]) and true or false,
        tooltip = c[3] })
    end
    r = row(m)
    if remote.interfaces["fse-std"] and remote.interfaces["fse-std"].open_theme then
      btn(r, "Theme...", "theme", nil, "How every window using fse-std looks to you (/fse-theme)", 100)
    end
    btn(r, "Reset size and place", "reset_size", nil, "The window back to its first size, in the middle of the screen", 170)
    theme.adopt(m)
    return

  elseif action == "set_save" then
    local function val(name) local e = f and find_el(f, name) return e and e.text end
    local dd = f and find_el(f, "aic_set_provider")
    if dd then player.mod_settings["ai-crew-provider"] = { value = PROVIDER_CHOICES[dd.selected_index] or "auto" } end
    if val("aic_set_key") then player.mod_settings["ai-crew-api-key"] = { value = val("aic_set_key"):gsub("%s", "") } end
    if val("aic_set_model") then player.mod_settings["ai-crew-model"] = { value = val("aic_set_model"):gsub("%s", "") } end
    check_ai(player)
    local l = f and find_el(f, "aic_ai_1")
    if l then l.caption = "Saved. Testing..." end
    return
  elseif action == "ada_hear" then
    return speak("Research complete. Please return to the HUB to select your next milestone, pioneer.", "ada", player)
  elseif action == "ai_test" then
    check_ai(player)
    local l = f and find_el(f, "aic_ai_1")
    if l then l.caption = "Testing..." end
    return
  elseif action == "hire" then
    local name = f and find_el(f, "aic_name")
    order(player.index, "crew hire " .. (name and name.text:match("^%s*(%S+)") or ""))
  elseif action == "fire" then
    if theme and theme.confirm and not scripted then  -- (asks first: the answer comes to theme.on_confirm, below)
      return theme.confirm(player, { name = "aic_fire", title = "Fire " .. tostring(who) .. "?",
        text = tostring(who) .. " leaves the crew and hands over what they carry.", yes = "Fire", no = "Keep",
        data = { who = who } })
    end
    order(player.index, "crew fire " .. who)
  elseif action == "mode" then -- follow, roam, stay, follow...
    local m = find_member(who, player.index)
    if m then order(player.index, m.name .. " " .. (m.roam and "stay" or m.follow and "roam" or "follow")) end
  elseif action == "get" or action == "mine" or action == "craft" then
    if not st.item then return tell("Pick an item first.") end
    order(player.index, who_of(f) .. " " .. action .. " " .. (tonumber(st.count) or 50) .. " " .. st.item)
  elseif action == "goal_set" then
    if not st.goal_item then return tell("Pick the goal's item first.") end
    order(player.index, "crew goal " .. (tonumber(st.goal_count) or 100) .. " " .. st.goal_item)
    local g = storage.goals and storage.goals[player.index]
    local bp = remote.interfaces["bpgen"]
    if g and bp and bp.plan_line and st.goal_line ~= false then g.use_line, g.rate = true, tonumber(st.goal_rate) or 30 end
  elseif action == "goal_clear" then
    if storage.goals then storage.goals[player.index] = nil end
    if storage.needs then storage.needs[player.index] = nil end
  elseif action == "send" then
    local box = f and find_el(f, "aic_chat")
    local text = box and box.text:gsub("^%s+", ""):gsub("%s+$", "")
    if not text or text == "" then return end
    box.text = ""
    order(player.index, who_of(f) .. " " .. text)
    return
  else
    order(player.index, (who or "crew") .. " " .. action)
  end
  if open_frame(player) then build_panel(player) end
end


-- ------------------------------------------------------------------------------------------------------ hover card
-- Hovering a crew member: a card under the minimap (where the game shows what's under the cursor), like the game's
-- own: name and manner, what they're doing, health, how they go about (follow, roam, stay; fight, auto), armor, gun and
-- ammo, fish, what's in their pockets, and their record (kills, built, trips, deaths). Updated twice a second while
-- hovered; gone when the cursor leaves them.
local hover = { CARD = "aic_card" }

function hover.member_of(ent)
  if not (ent and ent.valid and ent.name == CREW) then return end
  for _, m in pairs(crew()) do if m.entity == ent then return m end end
end

function hover.slot(parent, item, count, tip)
  local b = parent.add({ type = "sprite-button", style = "slot_button", sprite = item and ("item/" .. item) or nil,
    number = count and count > 1 and count or nil, tooltip = tip or (item and prototypes.item[item].localised_name or "") })
  b.style.size = 32
  b.ignored_by_interaction = false
  return b
end

function hover.card(player, m)
  local old = player.gui.screen[hover.CARD]
  if old then old.destroy() end
  if not (m and m.entity.valid) then return end
  local e = m.entity
  local c = m.color
  local f = player.gui.screen.add({ type = "frame", name = hover.CARD, direction = "vertical", tags = { who = m.name },
    caption = string.format("[color=%g,%g,%g]%s[/color]  [font=default-small][color=0.7,0.7,0.7]%s crew member[/color][/font]",
      c[1], c[2], c[3], m.name, trait(m)) })
  f.ignored_by_interaction = true
  f.style.width = 300
  local box = f.add({ type = "frame", style = "inside_shallow_frame_with_padding", direction = "vertical" })
  box.style.horizontally_stretchable = true
  local inner = box.add({ type = "flow", direction = "vertical" })
  inner.style.vertical_spacing = 4
  inner.add({ type = "label", caption = "[font=default-semibold]" .. status_text(m) .. "[/font]" }).style.single_line = false
  local hp = inner.add({ type = "flow", direction = "horizontal" })
  hp.style.vertical_align = "center"
  local bar = hp.add({ type = "progressbar", value = e.health / e.max_health })
  bar.style.horizontally_stretchable = true
  bar.style.color = e.health / e.max_health > 0.5 and { 0.3, 0.85, 0.3 } or { 0.9, 0.3, 0.2 }
  hp.add({ type = "label", caption = string.format("%d / %d", e.health, e.max_health) })
  -- (how it goes about it; the mode only when it's busy: idle, the line above says it already)
  local mode = not m.jobs[1] and "" or ((m.roam and "Roaming" or m.follow and "Following you" or "Staying put") .. " · ")
  inner.add({ type = "label", caption = string.format("[color=0.75,0.75,0.75]%sFight %s · Auto %s%s[/color]", mode,
    m.defend ~= false and "on" or "off", m.auto ~= false and "on" or "off", m.retreat and " · [color=1,0.4,0.3]falling back[/color]" or "") })
  -- what they carry into a fight
  local gear = inner.add({ type = "flow", direction = "horizontal" })
  gear.style.vertical_align = "center"
  local function first(inv_id)
    local inv = e.get_inventory(inv_id)
    if not inv then return end
    for i = 1, #inv do if inv[i].valid_for_read then return inv[i].name, inv[i].count end end
  end
  local armor = first(defines.inventory.character_armor)
  local gun = first(defines.inventory.character_guns)
  local ammo, rounds = first(defines.inventory.character_ammo)
  hover.slot(gear, armor, nil, armor and nil or "No armor")
  hover.slot(gear, gun, nil, gun and nil or "No gun")
  hover.slot(gear, ammo, rounds, ammo and nil or "No ammo")
  local fish = e.get_main_inventory().get_item_count("raw-fish")
  hover.slot(gear, prototypes.item["raw-fish"] and "raw-fish" or nil, fish, fish .. " fish to heal with")
  local range = gun and gun_range(m) or 0
  gear.add({ type = "label", caption = gun and string.format("  range %d", range) or "  unarmed" })
  -- pockets
  local items = e.get_main_inventory().get_contents()
  table.sort(items, function(a, b) return a.count > b.count end)
  if #items > 0 then
    local t = inner.add({ type = "table", column_count = 8 })
    t.style.horizontal_spacing, t.style.vertical_spacing = 0, 0
    for i = 1, math.min(#items, 16) do hover.slot(t, items[i].name, items[i].count) end
  else
    inner.add({ type = "label", caption = "[color=0.6,0.6,0.6]Pockets empty[/color]" })
  end
  local queued = #m.jobs > 1 and string.format(" · %d jobs queued", #m.jobs - 1) or ""
  inner.add({ type = "label", caption = string.format("[color=0.75,0.75,0.75]Kills %d · Built %d · Trips %d · Flights %d · Down %d%s[/color]",
    m.kills or 0, m.built or 0, m.rides or 0, m.flights or 0, m.deaths or 0, queued) })
  -- under the minimap, right side (where the game's own info for what's under the cursor goes)
  local res, scale = player.display_resolution, player.display_scale
  f.location = { x = res.width - (300 + 12) * scale, y = math.floor(380 * scale) }
end

-- With the fse loader's "entityinfo" plugin the same goes into the game's own info panel as rows, and no card
function hover.native_panel()
  if hover.native == nil then
    local ok, r = pcall(function() return native and native.call("entityinfo", "status", "") end)
    hover.native = ok and type(r) == "string" and r:find('"hooked":%[%s*"') ~= nil
  end
  return hover.native
end

function hover.rows(m)
  local e = m.entity
  local function first(inv_id)
    local inv = e.get_inventory(inv_id)
    for i = 1, inv and #inv or 0 do if inv[i].valid_for_read then return inv[i].name, inv[i].count end end
  end
  local armor = first(defines.inventory.character_armor)
  local gun = first(defines.inventory.character_guns)
  local ammo, rounds = first(defines.inventory.character_ammo)
  local carry = {}
  local items = e.get_main_inventory().get_contents()
  table.sort(items, function(a, b) return a.count > b.count end)
  for i = 1, math.min(#items, 8) do carry[#carry + 1] = "[item=" .. items[i].name .. "]" .. items[i].count end
  local c = m.color
  local how = string.format("fight %s · auto %s", m.defend ~= false and "on" or "off", m.auto ~= false and "on" or "off")
  if m.jobs[1] then how = (m.roam and "roaming" or m.follow and "following you" or "staying put") .. " · " .. how end
  return {
    { "Name", string.format("[color=%g,%g,%g]%s[/color] (%s)", c[1], c[2], c[3], m.name, trait(m)) },
    { "Doing", status_text(m) .. (m.retreat and " [color=1,0.4,0.3](falling back)[/color]" or "") },
    { "Settings", how },
    { "Weapon", gun and string.format("[item=%s] range %d  %s", gun, gun_range(m), ammo and string.format("[item=%s]%d", ammo, rounds)
      or "no ammo") or "unarmed" },
    { "Armor", armor and ("[item=" .. armor .. "]") or "none" },
    { "Fish", "[item=raw-fish]" .. e.get_main_inventory().get_item_count("raw-fish") },
    { "Carrying", #carry > 0 and table.concat(carry, " ") or "nothing" },
    { "Record", string.format("%d kills · %d built · %d trips · %d down", m.kills or 0, m.built or 0, (m.rides or 0) + (m.flights or 0),
      m.deaths or 0) },
  }
end

hover.shown = {} -- player index -> unit number in the native panel (not saved)
function hover.show(player, m)
  if hover.native_panel() then
    if player.gui.screen[hover.CARD] then player.gui.screen[hover.CARD].destroy() end
    local was = hover.shown[player.index]
    if was and not (m and m.entity.unit_number == was) then
      native.call("entityinfo", "clear", helpers.table_to_json({ unit = was }))
      hover.shown[player.index] = nil
    end
    if m and m.entity.valid then
      native.call("entityinfo", "set", helpers.table_to_json({ name = CREW, unit = m.entity.unit_number, rows = hover.rows(m) }))
      hover.shown[player.index] = m.entity.unit_number
    end
    return
  end
  hover.card(player, m)
end

script.on_event(defines.events.on_selected_entity_changed, function(ev)
  local player = game.get_player(ev.player_index)
  if player then hover.show(player, hover.member_of(player.selected)) end
end)


script.on_event(defines.events.on_gui_click, function(ev)
  local el, player = ev.element, game.get_player(ev.player_index)
  if not (el.valid and player) then return end
  if el.name == "aic_toggle" then
    if open_frame(player) then act(player, "close") else build_panel(player) end
  elseif el.tags and el.tags.fstd_settings == WIN then
    act(player, "settings")
  elseif el.tags and el.tags.aic and (el.type == "button" or el.type == "sprite-button") then
    act(player, el.tags.aic, el.tags.who)
  end
end)

script.on_event(defines.events.on_gui_checked_state_changed, function(ev)
  local el = ev.element
  if el.name == "aic_goal_line" then ui(game.get_player(ev.player_index)).goal_line = el.state return end
  if el.name == "aic_docked" then
    local player = game.get_player(ev.player_index)
    ui(player).inside = (not el.state) or nil
    return build_panel(player)
  end
  local setting = el.name:match("^aic_set_(.+)$")
  if setting then
    game.get_player(ev.player_index).mod_settings["ai-crew-" .. setting] = { value = el.state }
    return
  end
  local m = el.tags and find_member(el.tags.who, ev.player_index)
  if not m then return end
  if el.tags.aic == "auto" then m.auto = el.state end
  if el.tags.aic == "defend" then m.defend = el.state end
end)

script.on_event(defines.events.on_gui_confirmed, function(ev)
  local player = game.get_player(ev.player_index)
  if ev.element.name == "aic_chat" then act(player, "send")
  elseif ev.element.name == "aic_set_key" or ev.element.name == "aic_set_model" then act(player, "set_save")
  elseif ev.element.name == "aic_name" then act(player, "hire") end
end)

script.on_event(defines.events.on_gui_elem_changed, function(ev)
  if ev.element.name == "aic_item" then ui(game.get_player(ev.player_index)).item = ev.element.elem_value end
  if ev.element.name == "aic_goal_item" then ui(game.get_player(ev.player_index)).goal_item = ev.element.elem_value end
end)

script.on_event(defines.events.on_gui_text_changed, function(ev)
  if ev.element.name == "aic_count" then ui(game.get_player(ev.player_index)).count = ev.element.text end
  if ev.element.name == "aic_goal_count" then ui(game.get_player(ev.player_index)).goal_count = ev.element.text end
  if ev.element.name == "aic_goal_rate" then ui(game.get_player(ev.player_index)).goal_rate = ev.element.text end
end)

script.on_event(defines.events.on_gui_selection_state_changed, function(ev)
  if ev.element.name == "aic_set_ada_voice" then
    game.get_player(ev.player_index).mod_settings["ai-crew-ada-voice"] = { value = ADA_VOICES[ev.element.selected_index] or "heart" }
  end
  if ev.element.name == "aic_set_new_mode" then
    local v = ev.element.items[ev.element.selected_index]
    game.get_player(ev.player_index).mod_settings["ai-crew-new-mode"] = { value = type(v) == "string" and v or "roam" }
  end
  if ev.element.name == "aic_who" then ui(game.get_player(ev.player_index)).who = ev.element.selected_index end
end)

script.on_event(defines.events.on_gui_value_changed, function(ev)
  local name = ev.element.name:match("^aic_set_(.+%-volume)$")
  if not name then return end
  local v = math.floor(ev.element.slider_value + 0.5)
  game.get_player(ev.player_index).mod_settings["ai-crew-" .. name] = { value = v }
  local l = ev.element.parent["aic_vol_" .. name]
  if l then l.caption = v .. "%" end
end)

script.on_event(defines.events.on_gui_selected_tab_changed, function(ev)
  if ev.element.name == "aic_tabs" then ui(game.get_player(ev.player_index)).tab = ev.element.selected_tab_index end
end)

script.on_event(defines.events.on_gui_location_changed, function(ev)
  if ev.element.name == WIN then ui(game.get_player(ev.player_index)).loc = ev.element.location end
end)

script.on_event(defines.events.on_player_created, function(ev) add_button(game.get_player(ev.player_index)) end)
-- (multiplayer: a joining player's AI is tested by their own peer; every peer marks it as testing)
script.on_event(defines.events.on_player_joined_game, function(ev)
  local p = game.get_player(ev.player_index)
  if game.is_multiplayer() and p and py() and llm_settings(p).provider ~= "off" then check_ai(p) end
end)

-- ------------------------------------------------------------------------------------------------------------- shared
-- what the other files use of this one, and its link: control.lua calls it once all files are loaded
return {
  share = { act = act, add_button = add_button, build_panel = build_panel, check_ai = check_ai, fstd = fstd,
    hover = hover, mod_gui = mod_gui, open_frame = open_frame, refresh = refresh, theme = theme, ui = ui },
  link = function(A)
    ai_state, CREW, crew, DOING_WORD, find_member = A.ai_state, A.CREW, A.crew, A.DOING_WORD, A.find_member
    goal_have, gun_range, jobs, llm_settings, MAX_CREW = A.goal_have, A.gun_range, A.jobs, A.llm_settings, A.MAX_CREW
    members_of, needs, order, player_setting, pretty = A.members_of, A.needs, A.order, A.player_setting, A.pretty
    py, speak, trait = A.py, A.speak, A.trait
  end,
}
