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
local NEW_MODES = { "roam", "follow", "stay" } -- (the "New crew" setting's values; the drop-down shows them localised)

-- the window's words (locale/en/locale.cfg, [ai-crew-gui]), as a LocalisedString with its parameters
local function L(key, ...) return { "ai-crew-gui." .. key, ... } end

local function goal_text(owner)
  local nd = needs(owner)[1]
  if nd then
    return string.format("Working for: %s %s%s%s%s", nd.count and (goal_have(owner, nd.item) .. " / " .. nd.count) or nd.more,
      pretty(nd.item), nd.reason and (" (for " .. nd.reason .. ")") or "", nd.step and (" - " .. nd.step) or "",
      #needs(owner) > 1 and (", then " .. (#needs(owner) - 1) .. " more") or "")
  end
  local g = storage.goals and storage.goals[owner]
  if not g then return L("no-goal") end
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
    out[1] = L("ai-no-loader")
    return out
  end
  if llm.provider == "off" then out[1] = L("ai-provider-off") return out end
  if not a then out[1] = L("ai-untested") return out end
  if a.provider then
    out[#out + 1] = { "", L("ai-provider", a.provider), a.key and L("ai-key", a.key) or "",
      a.source and L("ai-source", a.source) or "" }
  end
  if a.model then out[#out + 1] = L("ai-model", a.model) end
  out[#out + 1] = a.ok and L("ai-connected", string.format("%.1f", a.seconds or 0)) or L("ai-broken", tostring(a.error))
  out[#out + 1] = L("ai-voices", tostring(a.tts or "-"))
  return out
end

PROVIDER_CHOICES = { "auto", "openrouter", "groq", "gemini", "cerebras", "mistral", "pollinations", "ollama", "off" }
-- (the settings' checkboxes: worded as the mod settings they set, locale [mod-setting-name] / -description)
TOGGLES = { "voices", "ada", "ada-llm", "lines-llm", "chatter", "hints", "machines", "back-after-orders", "jetpack",
  "tier-upgrades" }

local function ai_short(player)
  local a = ai_state()[player.index]
  if not py() then return L("ai-off-no-loader") end
  local gear = theme and theme.menu and "" or "-plain"  -- (the gear's picture: only where there is one)
  if not a then return L("ai-not-tested" .. gear) end
  return a.ok and L("ai-chat-ok", tostring(a.provider)) or L("ai-chat-broken" .. gear)
end

local function check_ai(player)
  if not py() then return end
  if jobs.start(player.index, "aicrew:check", helpers.table_to_json({ llm = llm_settings(player) }),
         { kind = "check", owner = player.index }) then
    ai_state()[player.index] = ai_state()[player.index] or {}
    ai_state()[player.index].testing = true
  end
end

-- (GUI Unifyer reskins the mod button bar but knows only its own list of buttons: ours take its button style, its
-- "_selected" one while on, so they match the others, and toggled as well)
local function gu_style(button, on)
  local base
  if script.active_mods["GUI_Unifyer"] or script.active_mods["GUI_Unifyer_Unified"] then
    local ok, s = pcall(function() return game.get_player(button.player_index).mod_settings["gu_button_style_setting"] end)
    base = ok and s and s.value
  end
  local styles = prototypes.style
  if not (base and styles[base]) then
    button.style = mod_gui.button_style
    button.toggled = on == true
    return
  end
  local selected = base .. "_selected"
  if on and styles[selected] then
    button.style = selected
    button.toggled = true  -- (also lit: some of its "_selected" styles draw the same art as the plain one)
  else
    button.style = base
    button.toggled = on == true
  end
end

-- (lit while the window is open)
local function add_button(player)
  local flow = mod_gui.get_button_flow(player)
  gu_style(flow.aic_toggle or flow.add({ type = "sprite-button", name = "aic_toggle", sprite = "entity/" .. CREW,
    style = mod_gui.button_style, tooltip = L("title") }), player.gui.screen[WIN] ~= nil)
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
    return fstd.create(player, { name = WIN, title = L("title"), width = 640, height = 470, min_width = 520, min_height = 320,
      themed = theme ~= nil, settings = theme ~= nil and theme.menu ~= nil,
      esc = false })  -- (stays open while the player opens chests, the inventory, ...)
  end
  local screen = player.gui.screen
  if screen[WIN] then screen[WIN].destroy() end
  local frame = screen.add({ type = "frame", name = WIN, direction = "vertical" })
  local bar = frame.add({ type = "flow", direction = "horizontal" })
  bar.drag_target = frame
  bar.add({ type = "label", caption = L("title"), style = "frame_title", ignored_by_interaction = true })
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

-- the orders for everyone, two rows of them: {caption, action, tooltip, width}
local EVERYONE = {
  { { "build", "build", "build-tip", 64 }, { "deconstruct", "deconstruct", "deconstruct-tip", 104 },
    { "upgrade", "upgrade", "upgrade-tip", 76 }, { "deliver", "deliver", "deliver-tip", 72 } },
  { { "mode-follow", "follow", "follow-all-tip", 100 }, { "mode-roam", "roam", "roam-all-tip", 64 },
    { "stop-all", "stop", "stop-all-tip", 72 }, { "attack", "attack", "attack-tip", 100 } },
}
local function everyone(parent, i)
  for _, b in ipairs(EVERYONE[i]) do btn(parent, L(b[1]), b[2], nil, L(b[3]), b[4]) end
end
local function row_width(i)
  local w = 0
  for _, b in ipairs(EVERYONE[i]) do w = w + b[4] + 6 end
  return w - 6
end

-- (a size changed on an attached frame, given at 100 %: fse-std 0.8 writes it at the window's scale (theme.style) and
-- keeps it as its tweak; an older one takes it as it is)
local function set_size(el, key, v)
  if theme.style then return theme.style(el, { [key] = v }) end
  local tags = el.tags
  if tags.fstd_tweak then tags.fstd_tweak[key] = v end
  el.tags = tags
  el.style[key] = v
end

-- (the scale the window is drawn at, on top of the game's: fse-std 0.8's per-window scale, else 1)
local function win_scale(frame)
  return theme and theme.scale_of and frame and frame.valid and theme.scale_of(frame) or 1
end

-- the dock: as wide as the window (less its borders), the orders in one row when they fit, else in two
local function dock_size(player)
  local w = (fstd and fstd.size(player, WIN) or 640) - 24
  local rows = w >= row_width(1) + row_width(2) + 6 + 16 and 1 or 2
  return w, rows
end

local function make_dock(player, frame)
  local w, rows = dock_size(player)
  local d = theme.dock(frame, { size = { w, rows == 1 and 44 or 80 } })
  local v = d.add({ type = "flow", name = "aic_dock_rows", direction = "vertical", tags = { rows = rows } })
  v.style.horizontally_stretchable, v.style.vertical_spacing = true, 4
  local e
  for i = 1, 2 do
    if i == 1 or rows == 2 then
      e = row(v)
      e.style.horizontally_stretchable, e.style.horizontal_align = true, "center"
    end
    everyone(e, i)
  end
  return d
end

-- (the window resized: the dock follows its width, in one row or two)
local function fit_dock(player)
  local frame, d = player.gui.screen[WIN], player.gui.screen[WIN .. "__bottom"]
  if not (frame and d and d.get_mod() == script.mod_name and d.aic_dock_rows) then return end
  local w, rows = dock_size(player)
  if rows ~= d.aic_dock_rows.tags.rows then
    theme.adopt(make_dock(player, frame))
    return
  end
  local tags = d.tags
  tags.fstd_attach.w = w
  d.tags = tags
  set_size(d, "width", w)
  theme.follow(frame)
end

-- the settings panel hangs from under the title bar: no taller than the window, so it doesn't cover the dock
local RAIL_W, MENU_TOP = 112, 38
local function menu_height(player)
  local _, h = fstd and fstd.size(player, WIN)
  return math.max(200, (h or 470) - MENU_TOP - 18)
end

-- (the window resized with its settings open: they follow its height)
local function fit_menu(player)
  local m = player.gui.screen[WIN .. "__menu"]
  if not (m and m.get_mod() == script.mod_name and m.tags.fstd_attach) then return end
  local h = menu_height(player)
  local tags = m.tags
  tags.fstd_attach.h, tags.fstd_attach.overlap = h, h + MENU_TOP
  m.tags = tags
  set_size(m, "height", h)
  theme.follow(player.gui.screen[WIN])
end

-- Keeps the window where all of it can be seen: the rail out of its left edge too (on the screen's left edge it
-- went off it), its title bar on the screen. On create, after a move, and when the resolution or scale changes.
local function keep_on_screen(player, frame)
  frame = frame or player.gui.screen[WIN]
  if not (frame and frame.valid and frame.location) then return end
  local sc, res = player.display_scale * win_scale(frame), player.display_resolution  -- (sizes below at 100 %)
  local w = fstd and fstd.size(player, WIN) or 640
  local docked = theme ~= nil and theme.dock ~= nil and not ui(player).inside
  local left = docked and math.ceil((RAIL_W - 6) * sc) or 0
  local loc = frame.location
  local x = math.max(left, math.min(loc.x, math.floor(res.width - w * sc)))
  local y = math.max(0, math.min(loc.y, math.floor(res.height - 60 * sc)))
  if x == loc.x and y == loc.y then return end
  frame.location = { x, y }
  ui(player).loc = frame.location
  local s = storage.fstd_windows and storage.fstd_windows[player.index]  -- (fse-std remembers the place it's given)
  if s and s[WIN] then s[WIN].location = frame.location end
  if theme then theme.follow(frame) end
end

-- (tests) the window put at x, y as a drag puts it
local function place_window(player, x, y)
  local f = player.gui.screen[WIN]
  if not f then return end
  f.location = { x, y }
  ui(player).loc = f.location
  keep_on_screen(player, f)
  local s = storage.fstd_windows and storage.fstd_windows[player.index]
  if s and s[WIN] then s[WIN].location = f.location end
  if theme then theme.follow(f) end
end

-- the Crew page's numbers: how many (of how many), jobs queued, how many busy (working or fighting)
local function stat_values(player)
  local members = members_of(player.index)
  local jobs_n, busy = 0, 0
  for _, m in pairs(members) do
    jobs_n = jobs_n + #m.jobs
    if m.jobs[1] or (m.target and m.target.valid) then busy = busy + 1 end
  end
  return { crew = #members .. " / " .. MAX_CREW, jobs = tostring(jobs_n), busy = busy .. " / " .. #members }
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
  local pages = { L("tab-crew"), L("tab-orders"), L("tab-goal") }
  st.tab = math.min(st.tab or 1, #pages)  -- (the Settings page went behind the gear)
  local sel
  if docked then
    local rail = theme.attach(frame, "left", { size = { RAIL_W, #pages * 34 + 8 }, along = 40, overlap = 6, role = "inset",
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
    body.style.right_padding = 10  -- (off the scroll bar when there is one)
    return body
  end

  -- Crew: a few numbers, a row each (Fire asks first), hiring; the orders for everyone (on the dock when docked)
  local crew_tab = page(1)
  if theme then  -- (three to a row, across it)
    local top = row(crew_tab)
    top.style.horizontally_stretchable = true
    local wide = { horizontally_stretchable = true, minimal_width = 100 }
    local v = stat_values(player)
    for _, k in ipairs({ "crew", "jobs", "busy" }) do
      local tile = theme.stat(top, v[k], L("stat-" .. k))
      tile.name = "aic_stat_" .. k
      if k == "busy" then tile.tooltip = L("stat-busy-tip") end
      theme.apply(tile, "stat", wide)
    end
  end
  note(crew_tab, ai_short(player), "aic_ai_short")
  local t = crew_tab.add({ type = "table", name = "aic_crew", column_count = 7 })
  t.style.vertical_align = "center"
  t.style.horizontal_spacing = 6
  for _, m in pairs(members) do
    local col = m.color
    local n = t.add({ type = "label", caption = string.format("[font=default-bold][color=%g,%g,%g]%s[/color][/font]", col[1], col[2], col[3], m.name) })
    n.style.width = 56
    -- (the status takes the room left over, cut short when there's none: the whole of it in the tooltip)
    local status = status_text(m)
    local l = t.add({ type = "label", name = "aic_status_" .. m.name, caption = status, tooltip = status })
    l.style.minimal_width = 80
    l.style.horizontally_stretchable, l.style.horizontally_squashable = true, true
    t.add({ type = "checkbox", caption = L("fight"), state = m.defend ~= false, tags = { aic = "defend", who = m.name },
      tooltip = L("fight-tip") })
    t.add({ type = "checkbox", caption = L("auto"), state = m.auto ~= false, tags = { aic = "auto", who = m.name },
      tooltip = L("auto-tip") })
    btn(t, L(m.roam and "mode-roam" or m.follow and "mode-follow" or "mode-stay"), "mode", m.name, L("mode-tip"), 100)
    btn(t, L("stop"), "stop", m.name, L("stop-tip"), 56)
    btn(t, L("fire"), "fire", m.name, L("fire-tip"), 52)
  end
  if #members == 0 then note(crew_tab, L("no-crew")) end
  local r = row(crew_tab)
  r.add({ type = "label", caption = L("name"), tooltip = L("name-tip") })
  r.add({ type = "textfield", name = "aic_name", tooltip = L("name-tip") }).style.width = 120
  btn(r, L("hire"), "hire", nil, L("hire-tip", MAX_CREW), 64).enabled = #members < MAX_CREW
  if #members > 0 then
    if docked then  -- (a toolbar hanging below the window: orders for everyone, whichever page is open)
      make_dock(player, frame)
    else  -- (a table: "Everyone:" as wide as its words, both rows of buttons lined up after it)
      crew_tab.add({ type = "line" })
      local e = crew_tab.add({ type = "table", column_count = 2 })
      e.style.horizontal_spacing, e.style.vertical_spacing = 6, 4
      e.style.vertical_align = "center"
      e.add({ type = "label", caption = L("everyone") })
      everyone(row(e), 1)
      e.add({ type = "empty-widget" })
      everyone(row(e), 2)
    end
  end

  -- Orders
  local orders = page(2)
  local names = { L("anyone") }
  for _, m in pairs(members) do names[#names + 1] = m.name end
  st.who = math.min(st.who or 1, #names)
  r = row(orders)
  r.add({ type = "drop-down", name = "aic_who", items = names, selected_index = st.who, tooltip = L("who-tip") })
  r.add({ type = "label", caption = L("item"), tooltip = L("item-tip") })
  r.add({ type = "choose-elem-button", name = "aic_item", elem_type = "item", item = st.item, tooltip = L("item-tip") })
  r.add({ type = "label", caption = L("times"), tooltip = L("count-tip") })
  r.add({ type = "textfield", name = "aic_count", text = st.count, numeric = true, allow_decimal = false,
    allow_negative = false, tooltip = L("count-tip") }).style.width = 60
  btn(r, L("get"), "get", nil, L("get-tip"), 56)
  btn(r, L("mine"), "mine", nil, L("mine-tip"), 56)
  btn(r, L("craft"), "craft", nil, L("craft-tip"), 60)
  note(orders, L("orders-note"))

  -- Goal: what to have, how far it is (a bar red to green), what they're working for
  local goal = page(3)
  r = row(goal)
  r.add({ type = "label", caption = L("goal-have"), tooltip = L("goal-item-tip") })
  r.add({ type = "choose-elem-button", name = "aic_goal_item", elem_type = "item", item = st.goal_item,
    tooltip = L("goal-item-tip") })
  r.add({ type = "label", caption = L("times"), tooltip = L("goal-count-tip") })
  r.add({ type = "textfield", name = "aic_goal_count", text = st.goal_count or "100", numeric = true,
    allow_decimal = false, allow_negative = false, tooltip = L("goal-count-tip") }).style.width = 60
  -- (a production line: only with bpgen, which plans it; its rate only while it's ticked)
  local bp = remote.interfaces["bpgen"] and remote.interfaces["bpgen"].plan_line
  if bp then
    local on = st.goal_line ~= false
    r.add({ type = "checkbox", name = "aic_goal_line", caption = L("goal-line"), state = on, tooltip = L("goal-line-tip") })
    r.add({ type = "textfield", name = "aic_goal_rate", text = st.goal_rate or "30", numeric = true, enabled = on,
      allow_decimal = false, allow_negative = false, tooltip = L("goal-rate-tip") }).style.width = 45
    r.add({ type = "label", caption = L("per-minute"), tooltip = L("goal-rate-tip") })
  end
  btn(r, L("goal-set"), "goal_set", nil, L("goal-set-tip"), 56)
  btn(r, L("goal-drop"), "goal_clear", nil, L("goal-drop-tip"), 84)
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
    cr.add({ type = "label", caption = L("say"), tooltip = L("chat-tip") })
    local chat = cr.add({ type = "textfield", name = "aic_chat",
      tooltip = L("chat-tip") })
    chat.style.horizontally_stretchable = true
    chat.style.maximal_width = 1000
    local send = btn(cr, L("send"), "send", nil, L("send-tip"), 90)
    if theme then theme.apply(send, "ok", { width = 90, minimal_width = 0 }) end
  end
  if theme then
    theme.adopt(frame)
    for _, a in pairs(player.gui.screen.children) do
      if a.tags.fstd_attach and a.tags.fstd_attach.owner == WIN and a.get_mod() == script.mod_name then theme.adopt(a) end
    end
  end
  -- (a remembered place: kept on the screen, the rail too. A new window is centred, which is)
  local saved = fstd and storage.fstd_windows and storage.fstd_windows[player.index]
  if (fstd and saved and saved[WIN] and saved[WIN].location) or (not fstd and st.loc) then keep_on_screen(player, frame) end

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
    local status = status_text(m)
    l.caption, l.tooltip = status, status
  end
  for k, value in pairs(stat_values(player)) do
    local tile = find_el(f, "aic_stat_" .. k)
    if tile and tile.fstd_stat_value then tile.fstd_stat_value.caption = value end
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
    add_button(player)
    return
  elseif action == "tab" then
    st.tab = who
  elseif action == "theme" then
    local menu = player.gui.screen[WIN .. "__menu"]
    if menu then menu.destroy() end
    return remote.call("fse-std", "open_theme", player.index)
  elseif action == "reset_size" then
    if fstd and fstd.reset_place then fstd.reset_place(player, WIN)
    elseif storage.fstd_windows and storage.fstd_windows[player.index] then storage.fstd_windows[player.index][WIN] = nil end
    st.loc = nil
  elseif action == "settings" then
    -- the window's settings, behind the gear by its close button (fse-std's theme.menu): the AI (provider, key,
    -- model, its test), ADA and the voices, what the crew do on their own, and the window's own (docked, theme, size)
    local m = f and theme and theme.menu and theme.menu(f, { size = { 460, menu_height(player) } })
    if not m then return end
    local head = row(m)
    theme.apply(head.add({ type = "label", caption = L("title") }), "caption")
    head.add({ type = "empty-widget" }).style.horizontally_stretchable = true
    if theme.dock then
      head.add({ type = "checkbox", name = "aic_docked", caption = { "fstd.docked" }, state = not ui(player).inside,
        tooltip = { "fstd.docked-tooltip" } })
    end
    if fstd.size_setting then fstd.size_setting(head, WIN) end  -- (the window's own Size: fse-std 0.8)
    local scroll = m.add({ type = "scroll-pane", horizontal_scroll_policy = "never", vertical_scroll_policy = "auto" })
    scroll.style.vertically_stretchable, scroll.style.horizontally_stretchable = true, true
    local function fold(title, open)  -- (each as wide as the panel, open or folded)
      local body = theme.fold(scroll, title, open)
      theme.apply(body.parent, "section", { horizontally_stretchable = true })
      return body
    end
    local ai = fold(L("fold-ai"), true)
    local set = ai.add({ type = "table", column_count = 2 })
    set.style.vertical_align = "center"
    set.style.horizontal_spacing = 12
    set.style.vertical_spacing = 6
    set.add({ type = "label", caption = L("provider") })
    local cur = player_setting(player, "ai-crew-provider") or "auto"
    local sel = 1
    for i, v in ipairs(PROVIDER_CHOICES) do if v == cur then sel = i end end
    set.add({ type = "drop-down", name = "aic_set_provider", items = PROVIDER_CHOICES, selected_index = sel,
      tooltip = L("provider-tip") })
    set.add({ type = "label", caption = L("api-key") })
    local key = set.add({ type = "textfield", name = "aic_set_key", text = player_setting(player, "ai-crew-api-key") or "",
      tooltip = L("api-key-tip") })
    key.style.width = 300
    key.is_password = true
    set.add({ type = "label", caption = L("model") })
    set.add({ type = "textfield", name = "aic_set_model", text = player_setting(player, "ai-crew-model") or "",
      tooltip = L("model-tip") }).style.width = 300
    local r = row(ai)
    btn(r, L("save-test"), "set_save", nil, L("save-test-tip"), 110).enabled = py()
    btn(r, L("test"), "ai_test", nil, L("test-tip"), 64).enabled = py()
    for i, line in ipairs(ai_lines(player)) do note(ai, line, "aic_ai_" .. i).style.maximal_width = 400 end
    local voice = fold(L("fold-voices"), false)
    r = row(voice)
    r.add({ type = "label", caption = L("ada-voice") })
    local cur_v = player_setting(player, "ai-crew-ada-voice") or "heart"
    local vi = 1
    for i, v in ipairs(ADA_VOICES) do if v == cur_v then vi = i end end
    r.add({ type = "drop-down", name = "aic_set_ada_voice", items = ADA_VOICES, selected_index = vi,
      tooltip = L("ada-voice-tip") })
    btn(r, L("hear"), "ada_hear", nil, L("hear-tip"), 60).enabled = py()
    for _, v in ipairs({ { "voice-volume", "crew-volume" }, { "ada-volume", "ada-volume" } }) do -- (0 to 100 %)
      r = row(voice)
      local cur = player_setting(player, "ai-crew-" .. v[1]) or 100
      r.add({ type = "label", caption = L(v[2]) }).style.minimal_width = 90
      r.add({ type = "slider", name = "aic_set_" .. v[1], minimum_value = 0, maximum_value = 100, value = cur, value_step = 5,
        tooltip = L(v[2] .. "-tip") })
      r.add({ type = "label", name = "aic_vol_" .. v[1], caption = cur .. "%" })
    end
    local own = fold(L("fold-crew"), false)
    r = row(own)
    r.add({ type = "label", caption = L("new-crew") })
    local cur_m, mi, items = player_setting(player, "ai-crew-new-mode") or "roam", 1, {}
    for i, v in ipairs(NEW_MODES) do
      if v == cur_m then mi = i end
      items[i] = L("mode-" .. v)
    end
    r.add({ type = "drop-down", name = "aic_set_new_mode", items = items, selected_index = mi, tooltip = L("new-crew-tip") })
    for _, c in ipairs(TOGGLES) do
      local parent = (c == "voices" or c == "lines-llm" or c == "ada" or c == "ada-llm") and voice or own
      parent.add({ type = "checkbox", name = "aic_set_" .. c, caption = { "mod-setting-name.ai-crew-" .. c },
        state = player_setting(player, "ai-crew-" .. c) and true or false, tooltip = { "mod-setting-description.ai-crew-" .. c } })
    end
    r = row(m)
    if remote.interfaces["fse-std"] and remote.interfaces["fse-std"].open_theme then
      btn(r, { "fstd.theme-button" }, "theme", nil, { "fstd.theme-button-tooltip" }, 100)
    end
    btn(r, { "fstd.reset-place" }, "reset_size", nil, { "fstd.reset-place-tooltip" }, 170)
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
    if l then l.caption = L("ai-saved-testing") end
    return
  elseif action == "ada_hear" then
    return speak("Research complete. Please return to the HUB to select your next milestone, pioneer.", "ada", player)
  elseif action == "ai_test" then
    check_ai(player)
    local l = f and find_el(f, "aic_ai_1")
    if l then l.caption = L("ai-testing") end
    return
  elseif action == "hire" then
    local name = f and find_el(f, "aic_name")
    order(player.index, "crew hire " .. (name and name.text:match("^%s*(%S+)") or ""))
  elseif action == "fire" then
    if theme and theme.confirm and not scripted then  -- (asks first: the answer comes to theme.on_confirm, below)
      return theme.confirm(player, { name = "aic_fire", title = L("fire-title", tostring(who)),
        text = L("fire-text", tostring(who)), yes = L("fire"), no = L("fire-keep"),
        danger = true, data = { who = who } })  -- (danger: a red yes, with an fse-std that has it)
    end
    order(player.index, "crew fire " .. who)
  elseif action == "mode" then -- follow, roam, stay, follow...
    local m = find_member(who, player.index)
    if m then order(player.index, m.name .. " " .. (m.roam and "stay" or m.follow and "roam" or "follow")) end
  elseif action == "get" or action == "mine" or action == "craft" then
    if not st.item then return tell(L("pick-item")) end
    order(player.index, who_of(f) .. " " .. action .. " " .. (tonumber(st.count) or 50) .. " " .. st.item)
  elseif action == "goal_set" then
    if not st.goal_item then return tell(L("pick-goal-item")) end
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
    add_button(player)
  elseif el.tags and el.tags.fstd_settings == WIN then
    act(player, "settings")
  elseif el.tags and el.tags.aic and (el.type == "button" or el.type == "sprite-button") then
    act(player, el.tags.aic, el.tags.who)
  end
end)

script.on_event(defines.events.on_gui_checked_state_changed, function(ev)
  local el = ev.element
  if el.name == "aic_goal_line" then
    ui(game.get_player(ev.player_index)).goal_line = el.state
    if el.parent.aic_goal_rate then el.parent.aic_goal_rate.enabled = el.state end
    return
  end
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
    game.get_player(ev.player_index).mod_settings["ai-crew-new-mode"] = { value = NEW_MODES[ev.element.selected_index] or "roam" }
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
  if ev.element.name ~= WIN or ev.element.get_mod() ~= script.mod_name then return end
  local player = game.get_player(ev.player_index)
  ui(player).loc = ev.element.location
  keep_on_screen(player, ev.element)  -- (before fse-std's handlers, which remember the place and move the rail)
end)

script.on_event({ defines.events.on_player_display_resolution_changed, defines.events.on_player_display_scale_changed },
  function(ev)
    local player = game.get_player(ev.player_index)
    if player then keep_on_screen(player) end
  end)

script.on_event(defines.events.on_player_created, function(ev) add_button(game.get_player(ev.player_index)) end)
script.on_event(defines.events.on_runtime_mod_setting_changed, function(ev)
  if ev.setting == "gu_button_style_setting" and ev.player_index then add_button(game.get_player(ev.player_index)) end
end)
-- (multiplayer: a joining player's AI is tested by their own peer; every peer marks it as testing)
script.on_event(defines.events.on_player_joined_game, function(ev)
  local p = game.get_player(ev.player_index)
  if game.is_multiplayer() and p and py() and llm_settings(p).provider ~= "off" then check_ai(p) end
  -- (GUI Unifyer's own join handler, after this one, takes "_selected" off every button in the bar: the crew
  -- button lit again on the next tick, control.lua's on_tick calling resync_buttons)
  storage.aic_resync = storage.aic_resync or {}
  storage.aic_resync[ev.player_index] = ev.tick + 1
end)

local function resync_buttons(tick)
  for i, at in pairs(storage.aic_resync) do
    if tick >= at then
      storage.aic_resync[i] = nil
      local p = game.get_player(i)
      if p and p.valid then add_button(p) end
    end
  end
  if not next(storage.aic_resync) then storage.aic_resync = nil end
end

if fstd then
  -- (closed by the title bar's X, which fse-std handles: the crew button unlit)
  fstd.on_close(function(player, name) if name == WIN then add_button(player) end end)
  -- (resized by its grip: the dock as wide as the window)
  fstd.on_resize(function(player, name)
    if name ~= WIN or not theme then return end
    if theme.dock then fit_dock(player) end
    fit_menu(player)
  end)
end

-- ------------------------------------------------------------------------------------------------------------- shared
-- what the other files use of this one, and its link: control.lua calls it once all files are loaded
return {
  share = { act = act, add_button = add_button, build_panel = build_panel, check_ai = check_ai, fstd = fstd,
    hover = hover, mod_gui = mod_gui, open_frame = open_frame, place_window = place_window, refresh = refresh, resync_buttons = resync_buttons,
    theme = theme, ui = ui },
  link = function(A)
    ai_state, CREW, crew, DOING_WORD, find_member = A.ai_state, A.CREW, A.crew, A.DOING_WORD, A.find_member
    goal_have, gun_range, jobs, llm_settings, MAX_CREW = A.goal_have, A.gun_range, A.jobs, A.llm_settings, A.MAX_CREW
    members_of, needs, order, player_setting, pretty = A.members_of, A.needs, A.order, A.player_setting, A.pretty
    py, speak, trait = A.py, A.speak, A.trait
  end,
}
