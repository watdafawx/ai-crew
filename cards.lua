-- AI Crew: the crew cards, one per crew member of yours in the bottom right of the screen: name and manner, how they
-- go about (roam, follow, stay), what they're doing, health, armor, gun, ammo and fish, and their record. Kept current
-- twice a second (control.lua's on_tick). Hidden with the "Crew cards" setting (also in the window's gear panel).
-- One of control.lua's files.

-- (the other files' that this one uses: set by link, at the end)
local act, COLORS, fstd, gun_range, members_of, player_setting, status_text, theme, trait

local cards = {}
local PREFIX = "aic_hud_"
local W, H, GAP, EDGE = 196, 124, 4, 10  -- (a card's size, the room between them and to the screen's edges, at 100 %)
-- (the game's toolbar, centred along the bottom: its half width and height at 100 %. Cards that would reach it sit
-- above it)
local BAR_HALF, BAR_H = 380, 108

local function L(key, ...) return { "ai-crew-gui." .. key, ... } end

local function first(e, inv_id)
  local inv = e.get_inventory(inv_id)
  for i = 1, inv and #inv or 0 do if inv[i].valid_for_read then return inv[i].name, inv[i].count end end
end

-- the cards shown now, by member name
local function shown(player)
  local out = {}
  for _, c in pairs(player.gui.screen.children) do
    if c.name:sub(1, #PREFIX) == PREFIX and c.get_mod() == script.mod_name then out[c.name:sub(#PREFIX + 1)] = c end
  end
  return out
end

function cards.hide(player)
  for _, c in pairs(shown(player)) do c.destroy() end
end

local function label(parent, name, role, t)
  local l = parent.add({ type = "label", name = name })
  if theme then theme.apply(l, role, t) end
  return l
end

local function slot(parent, name)
  local b = parent.add({ type = "sprite-button", name = name, style = "slot_button" })
  if theme then theme.apply(b, "slot", { size = 28 }) else b.style.size = 28 end
  return b
end

-- (the ring a card gets while its crew member talks: in their colour, data.lua's styles; red while they fight)
local function ring_of(m)
  for i, c in ipairs(COLORS) do
    if c[1] == m.color[1] and c[2] == m.color[2] and c[3] == m.color[3] then return "aic_card_ring_" .. i end
  end
  return "aic_card_ring_1"
end

-- a card's parts, made once; fill puts what's current in them. The card: a ring (shown while they talk or fight)
-- round the themed panel; down: the panel darker
local function build(player, m, down)
  local c = m.color
  local f = player.gui.screen.add({ type = "frame", name = PREFIX .. m.name, style = "aic_card_plain",
    direction = "vertical", tags = { aic_card_of = m.name, aic_down = down or false } })
  f.style.width, f.style.height = W, H
  local panel = f.add({ type = "frame", name = "aic_card", direction = "vertical",
    style = not theme and down and "inside_deep_frame" or nil })
  if theme then
    theme.apply(panel, down and "deep" or "toast", { horizontally_stretchable = true, vertically_stretchable = true, padding = 6 })
  else
    panel.style.horizontally_stretchable, panel.style.vertically_stretchable = true, true
    panel.style.padding = 6
  end
  local body = panel.add({ type = "flow", name = "aic_body", direction = "vertical" })
  body.style.vertical_spacing = 2
  local head = body.add({ type = "flow", name = "aic_head", direction = "horizontal" })
  head.style.vertical_align = "center"
  head.style.horizontal_spacing = 4
  local name = head.add({ type = "label", caption = string.format("[font=default-bold][color=%g,%g,%g]%s[/color][/font]",
    c[1], c[2], c[3], m.name) })
  name.style.font_color = { c[1], c[2], c[3] }  -- (themes colour labels: the name keeps its own)
  label(head, "aic_trait", "dim").caption = trait(m)
  head.add({ type = "empty-widget" }).style.horizontally_stretchable = true
  label(head, "aic_mode", "dim")
  local status = label(body, "aic_doing", "text")
  status.style.maximal_width = W - 18
  status.style.horizontally_squashable = true
  local hp = body.add({ type = "flow", name = "aic_hp_row", direction = "horizontal" })
  hp.style.vertical_align = "center"
  hp.style.horizontal_spacing = 6
  local bar = hp.add({ type = "progressbar", name = "aic_hp", value = 1 })
  if theme then theme.apply(bar, "progress", { horizontally_stretchable = true, height = 8 })
  else bar.style.horizontally_stretchable, bar.style.height = true, 8 end
  label(hp, "aic_hp_text", "dim").style.font = "default-small"
  local gear = body.add({ type = "flow", name = "aic_gear", direction = "horizontal" })
  gear.style.vertical_align = "center"
  gear.style.horizontal_spacing = 2
  for _, n in ipairs({ "armor", "gun", "ammo", "fish" }) do slot(gear, "aic_" .. n) end
  label(gear, "aic_range", "dim").style.left_margin = 4
  label(body, "aic_record", "dim").style.font = "default-small"
  return f
end

-- what's current, into a card's parts
local function fill(f, m)
  local e = m.entity
  local body = f.aic_card.aic_body
  local function find(name)
    return body[name] or body.aic_head[name] or body.aic_hp_row[name] or body.aic_gear[name]
  end
  local ring = (m.retreat or m.target and m.target.valid) and "aic_card_ring_fight"
    or m.bubble and m.bubble.valid and ring_of(m) or "aic_card_plain"
  if f.style.name ~= ring then
    f.style = ring
    f.style.width, f.style.height = W, H
  end
  local doing = status_text(m)
  local busy = m.retreat or (m.target and m.target.valid)
  local st = find("aic_doing")
  st.caption = busy and ("[color=1,0.45,0.35]" .. doing .. "[/color]") or doing
  st.tooltip = doing
  find("aic_mode").caption = L(m.roam and "card-roam" or m.follow and "card-follow" or "card-stay")
  local hp = e.health / e.max_health
  local bar = find("aic_hp")
  bar.value = hp
  bar.style.color = theme and theme.ramp(hp) or (hp > 0.5 and { 0.3, 0.85, 0.3 } or { 0.9, 0.3, 0.2 })
  find("aic_hp_text").caption = L("card-health", math.floor(e.health + 0.5), math.floor(e.max_health + 0.5))
  local armor = first(e, defines.inventory.character_armor)
  local gun = first(e, defines.inventory.character_guns)
  local ammo, rounds = first(e, defines.inventory.character_ammo)
  local fish = e.get_main_inventory().get_item_count("raw-fish")
  local function put(name, item, count, none)
    local b = find(name)
    local sprite = item and ("item/" .. item) or nil
    if b.sprite ~= (sprite or "") then
      b.sprite = sprite
      b.tooltip = item and prototypes.item[item].localised_name or L(none)
    end
    b.number = item and count and count > 1 and count or nil
  end
  put("aic_armor", armor, nil, "card-no-armor")
  put("aic_gun", gun, nil, "card-no-gun")
  put("aic_ammo", ammo, rounds, "card-no-ammo")
  put("aic_fish", prototypes.item["raw-fish"] and fish > 0 and "raw-fish" or nil, fish, "card-no-fish")
  find("aic_range").caption = gun and L("card-range", gun_range(m)) or L("card-unarmed")
  local rec = find("aic_record")
  rec.caption = L("card-record", m.kills or 0, m.built or 0, m.deaths or 0)
  rec.tooltip = L("card-record-tip", m.kills or 0, m.built or 0, (m.rides or 0) + (m.flights or 0), m.deaths or 0)
end

-- a fallen crew member's card, dimmed: grey, an empty bar and slots, when they're back (control.lua's storage.fallen)
local function fill_down(f, d)
  local body = f.aic_card.aic_body
  local function find(name)
    return body[name] or body.aic_head[name] or body.aic_hp_row[name] or body.aic_gear[name]
  end
  if f.style.name ~= "aic_card_plain" then
    f.style = "aic_card_plain"
    f.style.width, f.style.height = W, H
  end
  local doing = L("card-down", math.max(0, math.ceil((d.at - game.tick) / 60)))
  find("aic_doing").caption, find("aic_doing").tooltip = doing, doing
  find("aic_mode").caption = ""
  find("aic_hp").value = 0
  find("aic_hp_text").caption = ""
  for _, n in ipairs({ "aic_armor", "aic_gun", "aic_ammo", "aic_fish" }) do
    local b = find(n)
    b.sprite, b.number, b.tooltip = nil, nil, doing
  end
  find("aic_range").caption = ""
  local s = d.stats or {}
  local rec = find("aic_record")
  rec.caption = L("card-record", s.kills or 0, s.built or 0, s.deaths or 0)
  rec.tooltip = L("card-record-tip", s.kills or 0, s.built or 0, (s.rides or 0) + (s.flights or 0), s.deaths or 0)
end

-- where the cards go: two to a row from the bottom right, the first in the corner; above the game's toolbar when they'd
-- reach it
local function place(player, list)
  local res, s = player.display_resolution, player.display_scale
  local cols = math.min(#list, 2)
  local left = res.width - (EDGE + cols * W + (cols - 1) * GAP) * s
  local lift = left < res.width / 2 + BAR_HALF * s and BAR_H or 0
  for i, f in ipairs(list) do
    local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
    f.location = { x = math.floor(res.width - (EDGE + (col + 1) * W + col * GAP) * s),
      y = math.floor(res.height - (EDGE + lift + (row + 1) * H + row * GAP) * s) }
  end
end

-- ------------------------------------------------------------------------------------------------------------ pockets
-- A card clicked: that crew member's pockets in a window (a script can't open another character's inventory): their
-- armor, gun and ammo, then what they carry, a slot a stack. A stack clicked comes to you; Take all takes everything
-- they carry (not their gear). Kept current while open.
local POCKETS = "aic_pockets"

local function member_named(player, name)
  for _, m in ipairs(members_of(player.index)) do
    if m.name == name and m.entity and m.entity.valid then return m end
  end
end

-- the stacks they have: {inventory id, slot, name, count, quality}, gear first
local function stacks(m)
  local out = {}
  for _, id in ipairs({ defines.inventory.character_armor, defines.inventory.character_guns,
    defines.inventory.character_ammo, defines.inventory.character_main }) do
    local inv = m.entity.get_inventory(id)
    for i = 1, inv and #inv or 0 do
      local s = inv[i]
      if s.valid_for_read then
        out[#out + 1] = { inv = id, slot = i, name = s.name, count = s.count, quality = s.quality and s.quality.name }
      end
    end
  end
  return out
end

local function pockets_body(el)
  if el.name == "aic_pockets_body" then return el end
  for _, c in pairs(el.children) do
    local r = pockets_body(c)
    if r then return r end
  end
end

local function fill_pockets(player, frame)
  local body = frame and pockets_body(frame)
  if not body then return end
  local who = frame.tags.aic_who
  local m = member_named(player, who)
  local list = m and stacks(m) or {}
  local sig = helpers.table_to_json(list)
  if body.tags.sig == sig then return end
  body.tags = { sig = sig }
  body.clear()
  if not m then
    label(body, nil, "dim").caption = L("pockets-gone", who)
    return
  end
  local gear, main = {}, {}
  for _, s in ipairs(list) do
    if s.inv == defines.inventory.character_main then main[#main + 1] = s else gear[#gear + 1] = s end
  end
  local function slots(these)
    local t = body.add({ type = "table", column_count = 10 })
    t.style.horizontal_spacing, t.style.vertical_spacing = 0, 0
    for _, s in ipairs(these) do
      local b = t.add({ type = "sprite-button", style = "slot_button", sprite = "item/" .. s.name, number = s.count,
        quality = s.quality, tags = { aic_take = who, inv = s.inv, slot = s.slot },
        tooltip = { "", prototypes.item[s.name].localised_name, "\n", L("pockets-tip") } })
      if theme then theme.apply(b, "slot") end
    end
  end
  label(body, nil, "dim").caption = L("pockets-gear")
  if #gear > 0 then slots(gear) else label(body, nil, "dim").caption = L("pockets-none") end
  label(body, nil, "dim").caption = L("pockets-carrying")
  if #main > 0 then slots(main) else label(body, nil, "dim").caption = L("pockets-none") end
end

function cards.pockets(player, name)
  local m = member_named(player, name)
  if not m then return end
  local screen = player.gui.screen
  if screen[POCKETS] then screen[POCKETS].destroy() end
  local frame, content
  local title = L("pockets-title", m.name)
  if fstd then
    frame, content = fstd.create(player, { name = POCKETS, title = title, width = 440, height = 340, themed = theme ~= nil })
  else
    frame = screen.add({ type = "frame", name = POCKETS, caption = title, direction = "vertical" })
    frame.auto_center = true
    content = frame.add({ type = "frame", style = "inside_shallow_frame_with_padding", direction = "vertical" })
  end
  local tags = frame.tags
  tags.aic_who = m.name
  frame.tags = tags
  local scroll = content.add({ type = "scroll-pane", horizontal_scroll_policy = "never" })
  scroll.style.vertically_stretchable, scroll.style.horizontally_stretchable = true, true
  local body = scroll.add({ type = "flow", name = "aic_pockets_body", direction = "vertical" })
  body.style.vertical_spacing = 4
  local foot = content.add({ type = "flow", direction = "horizontal" })
  foot.style.top_margin = 6
  foot.add({ type = "empty-widget" }).style.horizontally_stretchable = true
  if not fstd then
    foot.add({ type = "button", caption = L("pockets-close"), tags = { aic_pockets_close = true } })
  end
  local all = foot.add({ type = "button", caption = L("pockets-take-all"), tags = { aic_take = m.name, all = true },
    tooltip = L("pockets-take-all-tip") })
  if theme then theme.apply(all, "ok") end
  fill_pockets(player, frame)
  if theme then theme.adopt(frame) end
end

-- a stack (or all they carry) to the player: what fits in their pockets
local function take(player, el)
  local t = el.tags
  local m = member_named(player, t.aic_take)
  if not m then return end
  local moved = 0
  local function give(s)
    if not s.valid_for_read then return end
    local n = player.insert({ name = s.name, count = s.count, quality = s.quality and s.quality.name })
    if n > 0 then
      moved = moved + n
      if n >= s.count then s.clear() else s.count = s.count - n end
    end
  end
  if t.all then
    local inv = m.entity.get_main_inventory()
    for i = 1, #inv do give(inv[i]) end
  else
    local inv = m.entity.get_inventory(t.inv)
    if inv and t.slot <= #inv then give(inv[t.slot]) end
  end
  if moved == 0 then player.create_local_flying_text({ text = L("pockets-full"), create_at_cursor = true }) end
  local f = player.gui.screen[POCKETS]
  if f then fill_pockets(player, f) end
end

-- a click on a card (any part of it): that crew member's pockets; in the pockets window, a stack taken
function cards.click(player, el)
  if not (el and el.valid) then return false end
  if el.tags and el.tags.aic_take then take(player, el) return true end
  if el.tags and el.tags.aic_pockets_close then
    if player.gui.screen[POCKETS] then player.gui.screen[POCKETS].destroy() end
    return true
  end
  while el and el.valid do
    local who = el.tags and el.tags.aic_card_of
    if who then
      if not el.tags.aic_down then cards.pockets(player, who) end
      return true
    end
    if el.parent == nil or el.parent == player.gui.screen then return false end
    el = el.parent
  end
  return false
end

-- (kept current with the cards)
local function refresh_pockets(player)
  local f = player.gui.screen[POCKETS]
  if f and f.get_mod() == script.mod_name then fill_pockets(player, f) end
end

-- ------------------------------------------------------------------------------------------------------------- web
-- With the fse loader's web plugin (single player), the cards are a web page over the game (fse-std's shells,
-- web/cards.html): anchored in the bottom right, see-through between the cards, a ring in their colour while they
-- talk, red while they fight, grey while they're down. The game's GUI cards above are the fallback (no loader,
-- multiplayer). The page gets a snapshot whenever one differs from the last it got.
local shell
if script.active_mods["fse-std"] then
  local ok, s = pcall(require, "__fse-std__/shell")
  if ok and type(s) == "table" and s.open then shell = s end
end
local SHELL, PAGE = "aic_cards", "__ai-crew__/web/cards.html"
-- (the orders the corner card gives, as the window's dock: act's actions)
local ORDERS = { build = true, deconstruct = true, upgrade = true, deliver = true, follow = true, roam = true, stop = true,
  attack = true }
local WEB_W, WEB_H, WEB_GAP = 124, 200, 6  -- (cards.css's card and gap, GUI units)
local sent, sized = {}, {}  -- (this session, per player: the last snapshot sent, the shell's size)
local icon_map

local function icon_of(item)
  if icon_map == nil then
    local ok, md = pcall(function() return prototypes.mod_data["ai-crew-icons"] end)
    icon_map = ok and md and md.data or false
  end
  return item and icon_map and icon_map[item] or nil
end

local function web_slot(item, count, none)
  local tip = item and prototypes.item[item] and prototypes.item[item].name or none
  return { item = item, n = count, icon = icon_of(item), tip = item and tip:gsub("-", " ") or none }
end

local function snapshot(it)
  local m, d = it.m, it.d
  if d then
    local s = d.stats or {}
    return { name = it.name, color = { 0.6, 0.6, 0.6 }, trait = trait({ name = it.name }), state = "down",
      back = math.max(0, math.ceil((d.at - game.tick) / 60)), hp = 0, max = 1,
      slots = { web_slot(), web_slot(), web_slot(), web_slot() }, kills = s.kills or 0, built = s.built or 0,
      trips = (s.rides or 0) + (s.flights or 0), deaths = s.deaths or 0 }
  end
  local e = m.entity
  local armor = first(e, defines.inventory.character_armor)
  local gun = first(e, defines.inventory.character_guns)
  local ammo, rounds = first(e, defines.inventory.character_ammo)
  local fish = e.get_main_inventory().get_item_count("raw-fish")
  local talk = m.bubble and m.bubble.valid and m.bubble.text
  local state = m.retreat and "retreat" or (m.target and m.target.valid) and "fight" or m.jobs[1] and "work" or "idle"
  return { name = m.name, color = m.color, trait = trait(m), mode = m.roam and "roam" or m.follow and "follow" or "stay",
    doing = status_text(m), state = state, talk = type(talk) == "string" and talk or nil,
    hp = math.floor(e.health + 0.5), max = math.floor(e.max_health + 0.5),
    slots = { web_slot(armor, 1, "No armor"), web_slot(gun, 1, "No gun"), web_slot(ammo, rounds, "No ammo"),
      web_slot(fish > 0 and prototypes.item["raw-fish"] and "raw-fish" or nil, fish, "No fish to heal with") },
    range = gun and gun_range(m) or 0, kills = m.kills or 0, built = m.built or 0,
    trips = (m.rides or 0) + (m.flights or 0), deaths = m.deaths or 0 }
end

local function web_update(player, all)
  local i = player.index
  if #all == 0 then
    if shell.is_open(player, SHELL) then shell.close(player, SHELL) end
    sent[i], sized[i] = nil, nil
    return
  end
  -- (its size: side by side in a row, the orders' card in the corner; above the game's toolbar when they'd reach it)
  local cols, rows = #all + 1, 1
  local w, h = cols * WEB_W + (cols - 1) * WEB_GAP, rows * WEB_H + (rows - 1) * WEB_GAP
  local own = theme and theme.setting_scale and theme.setting_scale(player) or 1
  local res, ds = player.display_resolution, player.display_scale
  local left = res.width - (EDGE + w) * ds * own
  local lift = left < res.width / 2 + BAR_HALF * ds and math.floor(BAR_H / own) or 0
  local key = w .. "x" .. h .. "+" .. lift .. "@" .. res.width .. "x" .. res.height .. "/" .. ds .. "/" .. own
  if not shell.is_open(player, SHELL) or sized[i] ~= key then
    shell.open(player, { name = SHELL, page = PAGE, size = { w, h }, anchor = "bottom-right", margin = EDGE,
      offset = { 0, -lift }, esc = false, yield = true })
    sized[i] = key
  end
  local list = {}
  for k, it in ipairs(all) do list[k] = snapshot(it) end
  local json = helpers.table_to_json(list)
  if sent[i] ~= json then
    sent[i] = json
    shell.send(player, SHELL, { cards = list })
  end
end

if shell then
  shell.on_message(function(player, name, data)
    if name ~= SHELL or type(data) ~= "table" then return end
    if data.cmd == "ready" then  -- (loaded, or again: the cards now)
      sent[player.index] = nil
      cards.update(player)
    elseif data.cmd == "order" and ORDERS[data.act] then  -- (the corner card: an order for everyone)
      act(player, data.act)
    elseif data.cmd == "open" then
      cards.pockets(player, data.name)
    end
  end)
end

-- the same orders as keys (data.lua's custom inputs, unbound until the player binds them)
for k in pairs(ORDERS) do
  script.on_event("ai-crew-order-" .. k, function(ev)
    local player = game.get_player(ev.player_index)
    if player then act(player, k) end
  end)
end

-- the cards are the web page here (the setting on, the loader's web plugin, single player)
local function use_web() return shell ~= nil and shell.available() end

local GREY = { 0.5, 0.5, 0.5 }

-- the cards made, kept current, put in place, or taken down (the setting off, or no crew): the living and the fallen
-- (dimmed until they're back), by name
function cards.update(player)
  refresh_pockets(player)
  local on = player_setting(player, "ai-crew-cards") ~= false
  local all = {}
  if on then
    for _, m in ipairs(members_of(player.index)) do
      if m.entity and m.entity.valid then all[#all + 1] = { name = m.name, m = m } end
    end
    for name, d in pairs(storage.fallen or {}) do
      if d.owner == player.index then all[#all + 1] = { name = name, d = d } end
    end
    table.sort(all, function(a, b) return a.name < b.name end)
  end
  if use_web() then
    cards.hide(player)  -- (the game's GUI ones, from before)
    return web_update(player, all)
  end
  local have = shown(player)
  local list = {}
  for _, it in ipairs(all) do
    local f = have[it.name]
    have[it.name] = nil
    local down = it.d ~= nil
    if f and f.tags.aic_down ~= down then  -- (fallen, or back: a card of the other kind)
      f.destroy()
      f = nil
    end
    local who = it.m or { name = it.name, color = GREY }
    if not f then
      f = build(player, who, down)
    end
    local ok = pcall(down and fill_down or fill, f, it.d or it.m)
    if not ok then  -- (a card from an older version: made again)
      f.destroy()
      f = build(player, who, down);
      (down and fill_down or fill)(f, it.d or it.m)
    end
    list[#list + 1] = f
  end
  for _, f in pairs(have) do f.destroy() end
  place(player, list)  -- (every time: a new resolution or scale too)
end

-- (tests) how the cards are shown: the web page (open, where, the last snapshot it got) or the game's GUI ones
function cards.state(player)
  local lua = {}
  for name, f in pairs(shown(player)) do lua[name] = { style = f.style.name, down = f.tags.aic_down } end
  return { web = use_web(), open = shell ~= nil and shell.is_open(player, SHELL), rect = shell and shell.rect(player, SHELL),
    sent = sent[player.index] and helpers.json_to_table(sent[player.index]), lua = lua }
end

-- (tests) a click on a member's card, as the player's: the page's message, or the game's GUI card's click
function cards.test_click(player, name)
  local f = shown(player)[name]
  if f then return cards.click(player, f.aic_card.aic_body) end
  cards.pockets(player, name)
end

-- ------------------------------------------------------------------------------------------------------------- shared
return {
  share = { cards = cards },
  link = function(A)
    act, COLORS, gun_range, members_of, player_setting, status_text = A.act, A.COLORS, A.gun_range, A.members_of, A.player_setting, A.status_text
    fstd, theme, trait = A.fstd, A.theme, A.trait
  end,
}
