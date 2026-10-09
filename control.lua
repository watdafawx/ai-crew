-- AI Crew: helper characters that build, clear, mine, hand-craft and fetch, run from a panel (the crew button, top left).
-- Idle, each one works like a construction bot near you: clears deconstruction marks, then places ghosts, hand-crafting
-- what it can't take from your pockets or nearby chests. Orders: get / mine / craft an item, build, clear, deliver,
-- follow, stay, stop. The panel's chat box goes to an LLM through the fse loader (aicrew.py), which answers in
-- character and may queue the same jobs; plain orders typed there ("get 50 iron ore") run without it.
--
-- remote.call("ai-crew", ...): hire(name, surface, position, force?, owner_index?), order(owner_index, text), status(name)

local D = defines.direction
local DIRS = { D.north, D.northeast, D.east, D.southeast, D.south, D.southwest, D.west, D.northwest }
local NAMES = { "Rook", "Mara", "Juno", "Bolt", "Pip", "Sable", "Tess", "Orin" }
local COLORS = { { 1, 0.55, 0.2 }, { 0.3, 0.8, 1 }, { 0.6, 1, 0.4 }, { 1, 0.4, 0.7 }, { 1, 0.9, 0.3 }, { 0.7, 0.5, 1 },
  { 0.4, 1, 0.9 }, { 1, 0.6, 0.5 } }
local ADA_COLOR = "1,0.62,0.2"
local RADIUS = 48 -- the work area around the owner (or home)
local MAX_CREW = 4
-- the crew's own body (data-final-fixes.lua): the same character, half as wide and shorter, so they fit where a
-- player does not
local CREW = "crew-character"
local ALIASES = { gear = "iron-gear-wheel", gears = "iron-gear-wheel", belt = "transport-belt", belts = "transport-belt",
  ["green-circuit"] = "electronic-circuit", ["green-circuits"] = "electronic-circuit", circuit = "electronic-circuit",
  circuits = "electronic-circuit", ["red-circuit"] = "advanced-circuit", ["red-circuits"] = "advanced-circuit",
  ["blue-circuit"] = "processing-unit", ["blue-circuits"] = "processing-unit", pipe = "pipe", pipes = "pipe",
  furnace = "stone-furnace", furnaces = "stone-furnace", drill = "burner-mining-drill", drills = "burner-mining-drill",
  pole = "small-electric-pole", poles = "small-electric-pole", ammo = "firearm-magazine", bricks = "stone-brick" }
local ACKS = { build = { "On it.", "Building.", "Let's get it up." }, deconstruct = { "Clearing it.", "Tearing it down." },
  mine = { "Heading out to mine.", "Pickaxe ready." }, craft = { "Crafting.", "Coming right up." },
  fetch = { "I'll grab it.", "Fetching." }, deliver = { "Bringing it over." }, follow = { "Right behind you." },
  stay = { "Holding here." }, stop = { "Stopping." }, goal = { "New goal. We're on it.", "Got it, working towards that." },
  need = { "None to hand. I'll work for it.", "We'll have to make some. On it." },
  attack = { "Locked and loaded.", "Let's clear them out.", "Time to burn some nests." },
  upgrade = { "Upgrading.", "Swapping them out." } }

-- each one's manner: picks their stock lines, and the AI is told it (aicrew.py has the same names)
local TRAITS = { Rook = "gruff", Mara = "upbeat", Juno = "precise", Bolt = "eager", Pip = "cheerful", Sable = "laconic",
  Tess = "precise", Orin = "gruff" }
local TRAIT_ORDER = { "gruff", "upbeat", "precise", "eager", "cheerful", "laconic" }
-- stock lines by event, then manner ("any" is everyone's); {item}, {n} and {other} are filled in. A member goes
-- through every line of an event before one comes round again
local LINES = {
  hello = {
    gruff = { "Right. Where's the work.", "Another factory. Fine. Point me at it." },
    upbeat = { "Hi! Oh, this place has potential.", "Reporting in! Let's make it shine." },
    precise = { "Online. Checking the ratios already.", "Present. Show me the bottleneck." },
    eager = { "Here! What's first? Anything. Give me anything.", "Ready, ready, ready." },
    cheerful = { "Hello! Is that a furnace? I love furnaces.", "Hi! Wow, it's big out here." },
    laconic = { "Here.", "Ready when you are." },
    any = { "Reporting for duty.", "Where do you need me?" },
  },
  bye = {
    gruff = { "Fine. I'll be off." }, upbeat = { "Aw. It was fun! Bye!" }, precise = { "Logging off. Inventory handed over." },
    eager = { "Already? Okay. Call me back!" }, cheerful = { "Bye! Keep the belts tidy!" }, laconic = { "See you." },
  },
  ack = {
    gruff = { "Yeah, yeah. On it.", "Fine.", "Consider it done." },
    upbeat = { "You got it!", "Love it, on my way.", "Ooh, a job!" },
    precise = { "Understood.", "Queued.", "Acknowledged." },
    eager = { "Already going!", "Yes! Next after that?", "On it on it on it." },
    cheerful = { "Okay!", "Ooh, okay!", "Right away!" },
    laconic = { "Sure.", "Mm.", "On it." },
  },
  contact = {
    gruff = { "Biters. Of course.", "Here they come. Ugly as ever.", "Hostiles. Don't make me put down the wrench." },
    upbeat = { "Uh, company!", "Biters! Okay, okay, we've got this!" },
    precise = { "Contact, {item}.", "Hostile in range. Engaging." },
    eager = { "Biters! Finally, some action!", "Mine! I've got this one!" },
    cheerful = { "Eek! Biters!", "Ah! Shoo! Shoo!" },
    laconic = { "Contact.", "Biters." },
    any = { "Hostiles!", "Weapons free." },
  },
  hurt = {
    gruff = { "Took a bite. Pulling back.", "Ow. Right, that's enough of that." },
    upbeat = { "Okay, ouch, falling back!", "I'm hurt, back in a sec!" },
    precise = { "Below half health. Retreating.", "Armour's failing. Withdrawing." },
    eager = { "I'm fine! I'm not fine. Pulling back!", "Need a breather, then round two!" },
    cheerful = { "Ow ow ow. Coming back!", "That hurt! Retreating!" },
    laconic = { "Hit. Falling back.", "Need a minute." },
  },
  back = {
    gruff = { "Rebuilt. Still annoyed.", "Back. Who's buying the fish?" },
    upbeat = { "I'm back! Missed me?", "Good as new!" },
    precise = { "Reconstruction complete. Resuming.", "Back online. Picking up where I left off." },
    eager = { "Back! Round two!", "Rebuilt and ready, what did I miss?" },
    cheerful = { "I'm back! Everything's shiny!", "Hello again!" },
    laconic = { "Back.", "Round two." },
  },
  down = {
    gruff = { "{other}'s down. Biters'll pay for that.", "Lost {other}. Watch your backs." },
    upbeat = { "No! {other}! ...They'll be back, right?", "{other} went down. Sixty seconds, hang in there." },
    precise = { "{other} is down. Reconstruction in sixty seconds.", "We lost {other}. Their position was overextended." },
    eager = { "{other}! I'll cover for them!", "{other}'s down, I'll pick up their work!" },
    cheerful = { "Oh no, {other}!", "{other}! Come back soon!" },
    laconic = { "{other}'s down.", "Lost {other}." },
  },
  goal = {
    gruff = { "{item}, done. Don't get used to it.", "There. {item}. Next?" },
    upbeat = { "We did it! {item}, all there!", "Goal done! Look at that pile of {item}!" },
    precise = { "Goal met: {item}. On schedule, roughly.", "{item}: target reached." },
    eager = { "Done! What's the next goal? Bigger?", "{item}, finished! Give us another!" },
    cheerful = { "Yay! All the {item}!", "We made so much {item}!" },
    laconic = { "{item}. Done.", "That's the {item}." },
  },
  research = {
    gruff = { "{item}. About time.", "New toys. {item}." },
    upbeat = { "{item} is done! Ooh, what can we build now?", "Research! {item}! Love that." },
    precise = { "{item} unlocked. That changes the build order.", "{item} complete. Noted." },
    eager = { "{item}! Can we use it right now?", "Ooh, {item}! I want to build one!" },
    cheerful = { "{item}! So fancy!", "We learned {item}!" },
    laconic = { "{item}. Useful.", "Hm. {item}." },
  },
  roam = {
    gruff = { "Fine. I'll go find my own work.", "Going for a walk. Don't touch my stuff." },
    upbeat = { "Ooh, exploring! I'll see what needs doing.", "Off to have a look around!" },
    precise = { "Surveying the area. I'll report anything off.", "Patrolling. I'll flag problems." },
    eager = { "Free rein? Yes! I'll find things to fix!", "Going! I'll find work!" },
    cheerful = { "Adventure!", "I'm gonna look at all the machines!" },
    laconic = { "Having a look round.", "I'll wander." },
  },
  nest = {
    gruff = { "Nest out here. Burning it.", "Biter nest. Not on my watch." },
    upbeat = { "Found a nest! Going in!", "There's a nest over here, clearing it!" },
    precise = { "{item} spotted. Moving to clear it.", "Nest at the edge of the base. Engaging." },
    eager = { "A nest! Mine! I've got it!", "Nest! Going, going!" },
    cheerful = { "A biter house! Bye, biter house!", "Found a nest! Eek, okay, going!" },
    laconic = { "Nest. Handling it.", "Nest here." },
  },
  nest_unarmed = {
    any = { "There's a nest out here. I'd want a gun before I go near it.", "Nest spotted. Not going near it bare-handed." },
  },
  dark = {
    gruff = { "This {item} has no power. Running a pole to it.", "Dead {item} over here. Fixing it." },
    upbeat = { "This {item}'s sitting in the dark! I'll wire it up.", "Poor {item}, no power. On it!" },
    precise = { "Unpowered {item}. Extending the grid.", "{item} has no power. Connecting it." },
    eager = { "Dark {item}! I'll run poles!", "No power here, fixing it!" },
    cheerful = { "This {item} is sleeping! Waking it up.", "No power here! Poles, go!" },
    laconic = { "{item}'s dark. Poles.", "No power here. Fixing." },
  },
  dark_note = {
    gruff = { "This {item} is dark and I can't fix it from here.", "No power on this {item}. Not my mess." },
    precise = { "{item} without power. Grid needs work there.", "Unpowered {item} noted." },
    any = { "This {item} has no power.", "There's a {item} over here doing nothing. No power." },
  },
  starved = {
    gruff = { "This {item} is starving. Nothing coming in.", "Idle {item}. Someone forgot an input." },
    upbeat = { "This {item}'s waiting on ingredients.", "Hungry {item} over here!" },
    precise = { "{item} short of inputs. That line's underfed.", "Input shortage at this {item}." },
    eager = { "This {item} needs more stuff! Want me to feed it?", "Starved {item} here!" },
    cheerful = { "This {item} is hungry!", "The {item} has nothing to make!" },
    laconic = { "{item}'s starved.", "Nothing going into this {item}." },
  },
  backed = {
    gruff = { "This {item}'s backed up. Output's going nowhere.", "Full {item}. Nobody's taking from it." },
    precise = { "{item} output blocked. Downstream's not keeping up.", "Output full at this {item}." },
    any = { "This {item} is full up. Nothing's taking its output.", "{item} backed up over here." },
  },
  welcome = {
    gruff = { "There you are. Didn't touch anything. Much.", "Oh, you're back. Good, the belts missed you." },
    upbeat = { "Welcome back! We kept things running!", "Hey, you're back! So much happened. Okay, not much." },
    precise = { "Welcome back. Nothing critical while you were gone.", "You're back. Status: nominal." },
    eager = { "You're back! Can we do something big now?", "Finally! What are we building?" },
    cheerful = { "Yay, you're back!", "Hi again! I missed you!" },
    laconic = { "Back.", "Hey." },
  },
  noted = {
    gruff = { "Noted. Don't make me write it down twice.", "Fine. I'll remember." },
    upbeat = { "Got it, noted!", "Ooh, good to know!" },
    precise = { "Logged.", "Noted, with coordinates." },
    eager = { "Remembered! Anything else to remember?", "Got it!" },
    cheerful = { "I'll remember! Probably!", "Noted!" },
    laconic = { "Noted.", "Got it." },
  },
  keep_out = {
    gruff = { "Fine. Hands off. Your mess, your rules.", "Not touching it. Happy?" },
    upbeat = { "Hands off, promise!", "Got it, we'll leave this bit alone!" },
    precise = { "Keep-out zone logged. Radius twenty-four.", "Understood. We won't take from or touch anything here." },
    eager = { "Won't touch a thing! Not even a little.", "Hands off! Got it!" },
    cheerful = { "I won't touch! Even the shiny bits!", "Okay, no touching!" },
    laconic = { "Hands off. Got it.", "Leaving it be." },
  },
  propose = {
    gruff = { "We keep running out of {item}. Want me to make {n}?", "{item}'s always short. Shall I fix that?" },
    upbeat = { "Hey, we're always short on {item}! Want me to make a big batch?", "Ooh, idea: {n} {item}? Say yes!" },
    precise = { "{item} consumption outpaces production. Shall I make {n}?", "By my numbers we're short on {item}. Make {n}?" },
    eager = { "Can I make {item}? We need {n}! Can I? Yes?", "{item}! We're short! Let me make some?" },
    cheerful = { "We're out of {item} a lot. Should I make some?", "More {item}? I could make {n}!" },
    laconic = { "Short on {item}. Want {n}?", "{item}'s short. Make some?" },
  },
  propose_line = {
    gruff = { "{item} keeps running dry. Want me to put a proper line down?", "We're always short on {item}. Line for it?" },
    upbeat = { "We're always short on {item}! Want me to set up a line for it?", "Idea! A {item} line. Yes?" },
    precise = { "{item}: consumption exceeds production. Shall I build a line for it?", "The numbers say {item} needs a line. Build one?" },
    eager = { "Let me build a {item} line! Please? Yes?", "{item} line? I can start right now!" },
    cheerful = { "Ooh, can we build a {item} line? We need one!", "A {item} line would be so nice. Should I?" },
    laconic = { "{item}'s short. Line for it?", "Want a {item} line?" },
  },
  declined = {
    gruff = { "Suit yourself.", "Fine. Your factory." },
    upbeat = { "No worries!", "Okay, maybe later!" },
    precise = { "Understood. I'll leave it.", "Noted. Not now." },
    eager = { "Aw. Okay. Later then!", "Okay! Something else then!" },
    cheerful = { "Okay!", "Aw, okay." },
    laconic = { "Sure.", "Fine." },
  },
  alarm = {
    gruff = { "They're at the {item}. Moving.", "Biters on our stuff. Not today." },
    upbeat = { "They're hitting the {item}! On my way!", "Base under attack! Coming!" },
    precise = { "Attack on the {item}. Responding.", "Hostiles at the {item}. Engaging." },
    eager = { "Attack! I'm going! I'm already going!", "The {item}! Hold on, I'm coming!" },
    cheerful = { "Hey! Leave the {item} alone!", "Eek, they're attacking! Coming!" },
    laconic = { "Attack. Going.", "On it." },
  },
  fishing = {
    gruff = { "Out of fish. Going fishing. Don't laugh.", "No fish left. I'll catch some." },
    upbeat = { "Fishing trip! We're out of fish.", "Out of fish, off to the water!" },
    precise = { "Fish stock at zero. Restocking.", "No healing supplies. Fishing." },
    eager = { "Fishing! I love fishing! We need fish!", "Gone fishing, back soon!" },
    cheerful = { "Fishies! I'll get some!", "Going fishing!" },
    laconic = { "Fishing.", "Getting fish." },
  },
  hint_research = {
    gruff = { "Labs are sitting idle. {item} next, I'd say.", "Nobody's researching anything. Try {item}." },
    upbeat = { "Ooh, nothing's being researched! How about {item}?", "Labs are bored! {item} could be fun!" },
    precise = { "Research queue is empty. {item} is the cheapest next step.", "No research running. I'd queue {item}." },
    eager = { "Can we research {item}? Please? The labs are doing nothing!", "{item}! Let's research {item}!" },
    cheerful = { "The labs are napping! Maybe {item}?", "What about researching {item}?" },
    laconic = { "No research on. {item}?", "Labs idle. {item}." },
  },
  hint_stall = {
    any = { "Been a quiet few minutes. Want to pick something big to build next?",
      "We've not built anything in a while. A new line, maybe? Just say what.",
      "Things have gone a bit still. More smelting would never hurt." },
  },
  hint_starved = {
    any = { "{n} machines making {item} are waiting on {other}.", "The {item} machines are starved: no {other} coming in ({n} of them).",
      "Heads up: {n} {item} machines have run out of {other}." },
  },
  hint_power = {
    any = { "Power's running short: {n} machines on low power. More steam engines?", "We're browning out. {n} machines on low power.",
      "Not enough power for everything. {n} machines are slowed down." },
  },
  hint_dark = {
    any = { "{n} machines near you have no power at all. Want poles run to them?", "There are {n} dark machines round here." },
  },
  hint_backed = {
    any = { "{n} {item} machines are backed up: nothing takes what they make.", "The {item} output is full. {n} machines just sitting there." },
  },
  hint_over = {
    any = { "We made {n} {item} in ten minutes and hardly used any. Put it to work?",
      "Loads of {item} piling up: {n} in ten minutes, almost none used." },
  },
  idle = {
    gruff = { "Back in my day we carried ore by hand. Oh wait.", "If one more belt goes sideways I'm quitting.",
      "These biters chew through walls like they're paid to." },
    upbeat = { "I reorganised that chest. You're welcome.", "Honestly? This base is coming along.",
      "I love the sound of a furnace at full tilt." },
    precise = { "Iron's running about twelve percent short, by my count.", "Someone has to say it: that belt is half empty.",
      "I've been timing the inserters. Don't ask." },
    eager = { "Is there more to build? There's always more to build.", "I could hand-craft a whole factory. Probably.",
      "Can we build a train next? Please?" },
    cheerful = { "The big drills are my favourite. They go brrr.", "I waved at a biter. It didn't wave back.",
      "Do you think the trees mind?" },
    laconic = { "Quiet.", "Belts hum. Nice.", "Too many trees." },
    any = { "Quiet out here. You can hear the belts humming.", "Do you think the pioneer knows we talk when they're away?",
      "I named that iron chest Gerald. Don't tell anyone.", "Smelting is just cooking for rocks, if you think about it.",
      "If the pioneer asks, I was working the whole time.", "I counted the trees again. Still too many.",
      "Biters have been quiet. I don't like it.", "One day robots will do all this. Then what do we do?" },
  },
  reply = {
    gruff = { "Don't jinx it, {other}.", "Back to work, {other}.", "Mm. Sure." },
    upbeat = { "Hah, fair!", "I was about to say the same!", "Aw, {other}." },
    precise = { "Statistically, you're right.", "Noted, {other}.", "Debatable." },
    eager = { "Me too! Wait, what?", "Can we fix it? Let's fix it.", "Ooh, good point, {other}!" },
    cheerful = { "Hee. {other}, you're funny.", "Shh, they might hear you!" },
    laconic = { "Mm-hm.", "Sure, {other}. Sure.", "Hah." },
  },
}
local ROAM = 40 -- roaming: how far from the player (or home) they wander

-- AI jobs (Python: the LLM). Every peer records a job in storage the same way; only the peer of the player it is for
-- runs it (its Python, its key) and, in multiplayer, sends the answer to all with native.sync (fse-std raises
-- "fse-sync"), so every peer applies the same answer in the same tick. In single player the answer applies at once.
local jobs = { running = {} } -- running: native job id -> job number (only on the peer running it); on_answer: with
-- the panel; checked: the AI was tested this session (single player). One table: the main chunk's locals are full.
-- player index -> the last AI test (storage.ai_tests: the panel shows it, and every peer's panel must match)
local function ai_state()
  storage.ai_tests = storage.ai_tests or {}
  return storage.ai_tests
end
local source_names = {} -- item -> names of resources/trees/rocks that yield it

-- ---------------------------------------------------------------------------------------------------------------- util

local map_marker -- (with hire)
local react -- (with the chatter)

local function crew_built(e) -- (machines the crew put down: theirs to use)
  for _, b in pairs(storage.crew_built or {}) do if b == e then return true end end
  return false
end
local delayed = {} -- (tests: path answers held back, as a busy pathfinder in a big base would)
local path_finished -- (with the events)

local function crew()
  storage.crew = storage.crew or {}
  return storage.crew
end

local function dist2(a, b)
  local dx, dy = a.x - b.x, a.y - b.y
  return dx * dx + dy * dy
end

local function pick(list) return list[math.random(#list)] end

local function pretty(name) return (name:gsub("-", " ")) end
local function a_an(name) return (pretty(name):match("^[aeiou]") and "an " or "a ") .. pretty(name) end

local function py()
  if not native then return false end
  -- (multiplayer answers travel through fse-std's sync)
  if game.is_multiplayer() and not script.active_mods["fse-std"] then return false end
  local ok, p = pcall(native.plugins)
  return ok and p and p.py ~= nil
end

-- does this peer run the job for `owner`? (in single player: always)
function jobs.runs_here(owner)
  if not game.is_multiplayer() then return true end
  return owner ~= nil and native.local_player ~= nil and native.local_player() == owner
end

function jobs.answered(n, st, out)
  local p = storage.jobs and storage.jobs[n]
  if not p then return end
  storage.jobs[n] = nil
  if st == "done" then jobs.on_answer(p, out)
  elseif p.kind ~= "ask" then jobs.on_answer(p, "{}")
  else
    local player = p.owner and game.get_player(p.owner)
    if player then player.print("[ai-crew] AI error: " .. tostring(out):sub(1, 300)) end
  end
end

-- the answer of job n, to every peer
function jobs.deliver(n, st, out)
  if game.is_multiplayer() then
    native.sync("ai-crew:answer", helpers.table_to_json({ n = n, st = st, out = out }))
  else
    jobs.answered(n, st, out)
  end
end

-- a Python job for `owner` (p: what to do with the answer, plain data); false if there is no Python
function jobs.start(owner, fn, input, p)
  if not py() then return false end
  storage.jobs = storage.jobs or {}
  storage.job_n = (storage.job_n or 0) + 1
  local n = storage.job_n
  p.at = game.tick
  storage.jobs[n] = p
  if jobs.runs_here(owner) then
    local id, err = native.start("py", fn, input)
    if id then jobs.running[id] = n else jobs.deliver(n, "error", tostring(err)) end
  end
  return true
end

local function player_setting(player, name)
  local ok, v = pcall(function() return settings.get_player_settings(player)[name].value end)
  if ok then return v end
end

-- the single player, for settings when no one gave the order
local function any_player()
  for _, p in pairs(game.connected_players) do return p end
end

local function speak(text, voice, player)
  if game.is_multiplayer() then
    player = native and native.local_player and native.local_player() and game.get_player(native.local_player())
  end
  player = player or any_player()
  if not (player and py()) then return end
  if not player_setting(player, voice == "ada" and "ai-crew-ada" or "ai-crew-voices") then return end
  native.call("py", "aicrew:speak", helpers.table_to_json({ text = text, voice = voice,
    ada_voice = voice == "ada" and player_setting(player, "ai-crew-ada-voice") or nil }))
end

local function llm_settings(player)
  if not player then return {} end
  return { provider = player_setting(player, "ai-crew-provider"), key = player_setting(player, "ai-crew-api-key"),
    model = player_setting(player, "ai-crew-model") }
end

local function ada(text)
  local p = any_player()
  if p and not player_setting(p, "ai-crew-ada") then return end
  if p and py() and player_setting(p, "ai-crew-ada-llm") then
    if jobs.start(p.index, "aicrew:ada", helpers.table_to_json({ text = text, llm = llm_settings(p) }),
           { kind = "ada", text = text }) then
      return
    end
  end
  game.print("[color=" .. ADA_COLOR .. "][ADA][/color] " .. text)
  speak(text, "ada")
end

local function trait(m) return TRAITS[m.name] or TRAIT_ORDER[(m.voice or 0) % #TRAIT_ORDER + 1] end

-- a stock line for the event in m's manner, not one it said since it last went through them all
local function line(m, event, vars)
  local set = LINES[event]
  local pool = {}
  for _, l in ipairs(set[trait(m)] or {}) do pool[#pool + 1] = l end
  for _, l in ipairs(set.any or {}) do pool[#pool + 1] = l end
  if #pool == 0 then pool = set.upbeat or set.any end
  m.recent = m.recent or {}
  local used = m.recent[event] or {}
  local fresh = {}
  for _, l in ipairs(pool) do if not used[l] then fresh[#fresh + 1] = l end end
  if #fresh == 0 then used, fresh = {}, pool end
  local l = pick(fresh)
  used[l] = true
  m.recent[event] = used
  return (l:gsub("{(%w+)}", function(k) return vars and vars[k] ~= nil and tostring(vars[k]) or "" end))
end

-- what happened lately, the crew's memory: the AI gets it with every request (saved; the last 20 per player)
local function remember(owner, text)
  storage.events = storage.events or {}
  local k = owner or 0
  local list = storage.events[k] or {}
  storage.events[k] = list
  list[#list + 1] = { tick = game.tick, text = text }
  if #list > 20 then table.remove(list, 1) end
end

-- Your notes for the crew ("remember ...") and the places they keep out of ("keep out", "don't touch this", "hands
-- off", "leave this alone"), saved, the AI told them all. In a keep-out zone (24 tiles round where you said it) they take
-- nothing from chests, borrow or refuel no machine, put nothing down and don't roam; what you mark there yourself
-- (ghosts, deconstruction, upgrades) they still do. chisle: zones count for everyone's crew, not just yours
local ZONE = 24
local function notes(owner)
  storage.notes = storage.notes or {}
  local k = owner or 0
  storage.notes[k] = storage.notes[k] or {}
  return storage.notes[k]
end

local function kept_out(surface, pos)
  for _, list in pairs(storage.notes or {}) do
    for _, n in ipairs(list) do
      if n.keep_out and n.surface == surface.name and dist2(n.pos, pos) <= ZONE * ZONE then return true end
    end
  end
  return false
end

-- Who speaks, and how loud. how: nil = news (in chat and out loud, unless someone just spoke or this one has been
-- talking a lot: then in chat only), "quiet" = routine (a bubble over its head, nothing else), "talk" = conversation
-- (an answer to the player, chatter: always in chat and out loud). The same news twice within 5 minutes is a bubble.
-- turn to look at pos, standing still, as a player turns their character
local function face(m, pos)
  local e = m.entity
  if m.move or not e.valid then return end
  local d = math.floor(math.atan2(pos.x - e.position.x, -(pos.y - e.position.y)) / (math.pi / 4) + 0.5) % 8
  pcall(function() e.direction = DIRS[d + 1] end)
end

local function say(m, text, how)
  local e = m.entity
  local c = m.color
  local p = m.owner and game.get_player(m.owner) -- (they look at you when they talk, near you)
  local pc = p and p.valid and p.character
  if pc and pc.surface == e.surface and dist2(pc.position, e.position) < 900 then face(m, pc.position) end
  if m.bubble and m.bubble.valid then m.bubble.destroy() end
  m.bubble = rendering.draw_text({ text = text, surface = e.surface, target = { entity = e, offset = { 0, -2.9 } },
    color = c, scale = 1.1, alignment = "center", time_to_live = 300 })
  if how == "quiet" then return end
  local t = game.tick
  if how ~= "talk" then -- (any line it said in the last 5 minutes, not just the last one)
    m.news = m.news or {}
    if t - (m.news[text] or -18000) < 18000 then return end
    if table_size(m.news) > 40 then
      for k, at in pairs(m.news) do if t - at >= 18000 then m.news[k] = nil end end
    end
    m.news[text] = t
    storage.crew_news = storage.crew_news or {} -- (a teammate said just this a minute ago: no need to say it again)
    if t - (storage.crew_news[text] or -3600) < 3600 then return end
    storage.crew_news[text] = t
    if table_size(storage.crew_news) > 60 then
      for k, at in pairs(storage.crew_news) do if t - at >= 3600 then storage.crew_news[k] = nil end end
    end
  end
  game.print(string.format("[color=%g,%g,%g]%s:[/color] %s", c[1], c[2], c[3], m.name, text))
  m.lines = (m.lines or 0) + 1 -- (what reached the chat, the last few: for tests)
  m.last_lines = m.last_lines or {}
  table.insert(m.last_lines, t .. ": " .. text)
  if #m.last_lines > 8 then table.remove(m.last_lines, 1) end
  -- (3 s between any two voiced lines, 20 s between one member's voiced news)
  if how ~= "talk" and (t - (storage.voice_at or -180) < 180 or t - (m.voice_at or -1200) < 1200) then
    return
  end
  storage.voice_at, m.voice_at = t, t
  speak(text, m.voice, m.owner and game.get_player(m.owner))
end

-- ------------------------------------------------------------------------------------------------- items and sources

local function resolve_item(s)
  if type(s) ~= "string" then return end
  s = s:lower():gsub("^%s+", ""):gsub("%s+$", ""):gsub("^the%s+", ""):gsub("^some%s+", ""):gsub("[%s_]+", "-")
  if s == "" then return end
  local I = prototypes.item
  if ALIASES[s] and I[ALIASES[s]] then return ALIASES[s] end
  local one = (s:gsub("s$", ""))
  for _, c in ipairs({ s, s .. "-ore", one, (s:gsub("es$", "")), s .. "-plate", one .. "-plate" }) do
    if I[c] then return c end
  end
  if ALIASES[one] and I[ALIASES[one]] then return ALIASES[one] end
  local best
  for name in pairs(I) do
    if name:find(one, 1, true) and (not best or #name < #best) then best = name end
  end
  return best
end

-- names of the resources, trees and rocks a character can mine by hand for this item
local function sources_for(item)
  if source_names[item] then return source_names[item] end
  local names = {}
  for name, proto in pairs(prototypes.get_entity_filtered({ { filter = "type", type = { "resource", "tree", "simple-entity" } } })) do
    local mp = proto.mineable_properties
    if mp and mp.minable and not mp.required_fluid then
      for _, p in pairs(mp.products or {}) do
        if p.type == "item" and p.name == item then names[#names + 1] = name break end
      end
    end
  end
  source_names[item] = names
  return names
end

local HAND
local function hand_categories()
  HAND = HAND or (prototypes.entity[CREW] and prototypes.entity[CREW].crafting_categories) or { crafting = true }
  return HAND
end

local function handcraft_recipe(force, item)
  local HAND = hand_categories()
  local r = force.recipes[item]
  if r and r.enabled and not r.hidden and HAND[r.category] then return r end
end

local function owner_char(m)
  local p = m.owner and game.get_player(m.owner)
  local c = p and p.valid and p.character
  if c and c.valid and c.surface == m.entity.surface then return c end
end

local function anchor(m)
  local c = owner_char(m)
  return c and c.position or m.home
end

-- chests near the owner (or home); logistic chests only when they're in no network (the network counts those)
local function chests(m)
  local out = {}
  for _, ch in pairs(m.entity.surface.find_entities_filtered({ type = { "container", "logistic-container" },
    force = m.entity.force, position = anchor(m), radius = RADIUS })) do
    local inv = ch.get_inventory(defines.inventory.chest)
    if inv and not (ch.type == "logistic-container" and ch.logistic_network) and not kept_out(ch.surface, ch.position) then
      out[#out + 1] = inv
    end
  end
  return out
end

-- the logistic network where the owner (or home) is: its storage and provider chests, wherever they are
local function network(m)
  return m.entity.surface.find_logistic_network_by_position(anchor(m), m.entity.force)
end

-- inventories the crew may take from: the owner's pockets, then chests near the owner (or home)
local function sources(m, chests_only)
  local out = chests(m)
  local c = not chests_only and owner_char(m)
  if c then table.insert(out, 1, c.get_main_inventory()) end
  return out
end

local function available(m, item, quality, chests_only)
  local id = { name = item, quality = quality or "normal" }
  local n = 0
  for _, inv in pairs(sources(m, chests_only)) do n = n + inv.get_item_count(id) end
  local net = network(m)
  return net and n + net.get_item_count(id) or n
end

-- what it took from out of reach (a chest, your pockets) it walks over to, as a player would:
-- the items move at once and the walk comes before its next step (think). Once a minute a place and item: the
-- next few of the same it took along on the first trip.
-- chisle: the logistic network still hands items over directly, as if bots brought them
local function note_visit(m, ent, item)
  if not (ent and ent.valid) or ent == m.entity then return end
  local e = m.entity
  if dist2(ent.position, e.position) <= e.reach_distance * e.reach_distance then return end
  if not m.visited or table_size(m.visited) > 200 then m.visited = {} end
  local k = (ent.unit_number or 0) .. item
  if game.tick - (m.visited[k] or -3600) < 3600 then return end
  m.visited[k] = game.tick
  m.visits = m.visits or {}
  m.visits[#m.visits + 1] = ent
end

local function take(m, item, count, quality, chests_only)
  local inv = m.entity.get_main_inventory()
  local id = { name = item, quality = quality or "normal" }
  local got = 0
  for _, src in pairs(sources(m, chests_only)) do
    if got >= count then break end
    local n = math.min(count - got, src.get_item_count(id))
    if n > 0 then
      local ins = inv.insert({ name = item, count = n, quality = id.quality })
      if ins > 0 then
        src.remove({ name = item, count = ins, quality = id.quality })
        note_visit(m, src.entity_owner, item)
      end
      got = got + ins
    end
  end
  local net = got < count and network(m)
  if net then
    local n = math.min(count - got, net.get_item_count(id))
    local ins = n > 0 and inv.insert({ name = item, count = n, quality = id.quality }) or 0
    if ins > 0 then
      local out = net.remove_item({ name = item, count = ins, quality = id.quality })
      if out < ins then inv.remove({ name = item, count = ins - out, quality = id.quality }) end
      got = got + out
    end
  end
  return got
end

-- everything in its pockets goes to the owner, else chests near home; what doesn't fit stays
local function unload(m)
  local inv = m.entity.get_main_inventory()
  local dests = {}
  local c = owner_char(m)
  if c then dests[1] = c.get_main_inventory() else dests = chests(m) end
  local moved = 0
  for _, it in pairs(inv.get_contents()) do
    local left = it.count
    for _, d in pairs(dests) do
      if left <= 0 then break end
      local n = d.insert({ name = it.name, count = left, quality = it.quality })
      if n > 0 then
        inv.remove({ name = it.name, count = n, quality = it.quality })
        left, moved = left - n, moved + n
      end
    end
  end
  return moved
end

-- ----------------------------------------------------------------------------------------------------------- moving

-- its own place near pos: crew members spread round the owner instead of piling onto one point
local function spot(m, pos)
  local a = (m.phase or 0) * 2.4
  local want = { x = pos.x + math.cos(a) * 3, y = pos.y + math.sin(a) * 3 }
  return m.entity.surface.find_non_colliding_position(CREW, want, 5, 0.5) or want
end

local function stop_walk(m)
  m.move = nil
  if m.entity.valid then m.entity.walking_state = { walking = false, direction = D.north } end
end

local function stop_mining(m)
  m.mining = nil
  if m.entity.valid then m.entity.mining_state = { mining = false } end
end

local function request_path(m)
  local e, mv = m.entity, m.move
  -- its own body, not a player's: a slightly larger box than the crew's so a route through a tight gap is never a
  -- squeeze for them
  local id = e.surface.request_path({ bounding_box = { { -0.15, -0.15 }, { 0.15, 0.15 } },
    collision_mask = e.prototype.collision_mask, start = e.position, goal = mv.goal, force = e.force,
    radius = math.max(mv.radius - 0.5, 0.5), entity_to_ignore = e, pathfind_flags = { cache = false, no_break = true } })
  storage.paths = storage.paths or {}
  storage.paths[id] = m.name
  mv.path, mv.i, mv.final, mv.still = nil, 1, nil, 0
end

local TRIP = 80 -- longer than this: a car or train when there's one (vehicles, below)
local vehicle_trip, leave -- (with the vehicles)

-- true when already within radius of pos; else starts walking there (or driving, riding: a long trip)
local function go(m, pos, radius)
  local r = m.ride
  if r then -- in a car or on a train, or on the way to it: the goal moves along with it, else they get off
    if dist2(r.goal, pos) < 1 then return false end
    if dist2(m.entity.position, pos) > 40 * 40 then
      r.goal, r.radius, r.repath = { x = pos.x, y = pos.y }, radius, true
      return false
    end
    leave(m)
  end
  if dist2(m.entity.position, pos) <= radius * radius then
    if m.move then stop_walk(m) end
    return true
  end
  if not (m.move and dist2(m.move.goal, pos) < 1) then
    if vehicle_trip and dist2(m.entity.position, pos) > TRIP * TRIP and vehicle_trip(m, pos, radius) then return false end
    local near = m.move and dist2(m.move.goal, pos) < 64
    m.move = { goal = { x = pos.x, y = pos.y }, radius = radius, hops = near and m.move.hops or 0,
      still_total = near and m.move.still_total or 0 }
    request_path(m)
  end
  return false
end

-- no route at all (a machine's in the way, a wall of them, a whole line): step through it, a few tiles at a time, in
-- the direction of the goal. Slower than walking and only ever onto free ground, but it gets them there in the end
local function hop_along(m, step, tries)
  local mv, e = m.move, m.entity
  if mv.hop_tries and mv.hop_tries >= tries then return false end
  local dx, dy = mv.goal.x - e.position.x, mv.goal.y - e.position.y
  local d = math.sqrt(dx * dx + dy * dy)
  if d < 0.5 then return false end
  local tx, ty = e.position.x + dx / d * math.min(step, d), e.position.y + dy / d * math.min(step, d)
  local to = e.surface.find_non_colliding_position(CREW, { x = tx, y = ty }, step + 1, 0.5)
  if not to then return false end
  mv.hop_tries, mv.hop_at, mv.last = (mv.hop_tries or 0) + 1, game.tick, { x = to.x, y = to.y }
  e.teleport(to)
  return true
end

-- Jetpack: a short flight straight over whatever is in the way (machines, walls, water, cliffs), landing on free ground
-- near the goal, up to JET tiles at a time. Used when the pathfinder finds no route, when the route is far longer than
-- the way straight there, when walking gets stuck, and to rush to a fight. Off (the player's "Crew jetpacks"
-- setting): they step through blockages a few tiles at a time instead
local JET = 32
local function jets(m)
  local p = m.owner and game.get_player(m.owner) or any_player()
  return player_setting(p, "ai-crew-jetpack") ~= false
end

local function fly(m, to)
  local e = m.entity
  if m.fly or not jets(m) then return false end
  if m.move and m.move.flew and dist2(m.move.goal, to) < 4 then return false end -- (once per goal: no hopping about)
  local dx, dy = to.x - e.position.x, to.y - e.position.y
  local d = math.sqrt(dx * dx + dy * dy)
  if d < 2 then return false end
  if d > JET then to, d = { x = e.position.x + dx / d * JET, y = e.position.y + dy / d * JET }, JET end
  local land = e.surface.find_non_colliding_position(CREW, to, 8, 0.5)
  if not land then return false end
  d = math.sqrt(dist2(e.position, land))
  e.walking_state = { walking = false, direction = D.north }
  m.fly = { from = { x = e.position.x, y = e.position.y }, to = land, t0 = game.tick, ticks = math.max(math.ceil(d / 0.4), 12) }
  m.flights = (m.flights or 0) + 1
  if m.move then m.move.flew = true end
  return true
end

-- each tick of a flight: along the line, a trail of smoke; landed, the walk goes on from there
local function flight(m)
  local f, e = m.fly, m.entity
  local k = math.min((game.tick - f.t0) / f.ticks, 1)
  e.teleport({ x = f.from.x + (f.to.x - f.from.x) * k, y = f.from.y + (f.to.y - f.from.y) * k })
  if game.tick % 3 == 0 and prototypes.trivial_smoke["smoke-fast"] then e.surface.create_trivial_smoke({ name = "smoke-fast", position = e.position }) end
  if k >= 1 then
    m.fly = nil
    if m.move then
      m.move.still, m.move.still_total, m.move.hops, m.move.hop_tries = 0, 0, 0, nil
      request_path(m)
    end
  end
end

local function walk(m)
  local mv, e = m.move, m.entity
  if dist2(e.position, mv.goal) <= mv.radius * mv.radius then return stop_walk(m) end
  if not mv.path then
    -- waiting for the pathfinder (slow in a big base): stand still, not keep walking the old way into a machine
    if mv.walking ~= false then
      e.walking_state = { walking = false, direction = D.north }
      mv.walking = false
    end
    if mv.retry and game.tick >= mv.retry then mv.retry = nil request_path(m) end
    return
  end
  mv.walking = true
  -- path_finished answers "no route" with a straight line at the goal, which only works while nothing is in the way.
  -- Getting no closer to the goal than it has ever been for a couple of seconds means something is: step through it
  if mv.straight then
    local d2 = dist2(e.position, mv.goal)
    if not mv.closest or d2 < mv.closest then mv.closest, mv.closest_at = d2, game.tick end
    if game.tick - (mv.closest_at or 0) >= 150 then
      mv.closest, mv.closest_at = nil, nil
      if fly(m, mv.goal) or hop_along(m, 3, 20) then return end
    end
  end
  local wp = mv.path[mv.i]
  if wp and dist2(e.position, wp.position) < 0.25 then
    mv.i = mv.i + 1
    wp = mv.path[mv.i]
  end
  if not wp then
    if mv.final or not e.surface.can_place_entity({ name = CREW, position = mv.goal }) then return stop_walk(m) end
    mv.final = true
    mv.path[mv.i] = { position = mv.goal }
    wp = mv.path[mv.i]
  end
  local dx, dy = wp.position.x - e.position.x, wp.position.y - e.position.y
  local d = math.floor(math.atan2(dx, -dy) / (math.pi / 4) + 0.5) % 8
  if mv.slide and game.tick < mv.slide.until_tick then d = (d + mv.slide.turn) % 8 end -- (sliding round a corner)
  e.walking_state = { walking = true, direction = DIRS[d + 1] }
  -- stuck (hardly moved for 1.5 s): ask for a new path; after three tries hop next to the goal
  if mv.last and dist2(e.position, mv.last) < 0.0004 then
    mv.still, mv.still_total = mv.still + 1, (mv.still_total or 0) + 1
  else
    mv.still = 0
  end
  mv.last = { x = e.position.x, y = e.position.y }
  -- pushing against something: turn one step either way for a moment to slide along it
  if mv.still > 0 and mv.still % 12 == 0 then
    mv.flip = not mv.flip
    mv.slide = { turn = mv.flip and 1 or 7, until_tick = game.tick + 14 }
  end
  -- stuck a long while, even across small goal changes: hop to free ground near the goal
  if (mv.still_total or 0) > 240 then
    if fly(m, mv.goal) then return end
    local to = e.surface.find_non_colliding_position(e.name, mv.goal, 6, 0.5)
    if to then e.teleport(to) end
    return stop_walk(m)
  end
  if mv.still == 20 then -- (another crew member in the way: step aside)
    for _, o in pairs(crew()) do
      if o ~= m and o.entity.valid and dist2(o.entity.position, e.position) < 2.25 then
        local to = e.surface.find_non_colliding_position(e.name, { x = e.position.x + (m.phase % 2 == 0 and 1.2 or -1.2),
          y = e.position.y + 0.6 }, 2, 0.3)
        if to then e.teleport(to) end
        break
      end
    end
  end
  if mv.still > 90 then
    mv.hops = mv.hops + 1
    if mv.hops > 2 then
      if fly(m, mv.goal) then return end
      local to = e.surface.find_non_colliding_position(e.name, mv.goal, 6, 0.5)
      if to then e.teleport(to) end
      stop_walk(m)
    else
      request_path(m)
    end
  end
end

-- ------------------------------------------------------------------------------------------------------------- jobs

local JOBS = {}
local low_burners -- (defined with the fuel helpers)
local DOING_WORD = { drive = "driving", defend = "defending the base", fish = "fishing", build = "building", deconstruct = "clearing", mine = "mining", craft = "crafting",
  fetch = "fetching", deliver = "delivering", smelt = "making", place = "placing", tend = "refuelling",
  feed = "feeding", collect = "collecting", attack = "attacking nests", upgrade = "upgrading" }

local function claims()
  storage.claims = storage.claims or {}
  return storage.claims
end

-- what the crew has to work for (ghost items, a craft's ingredients, an order), ahead of the goal: {item, more, reason,
-- after = the job to run once it's there}; count is set when work on it starts (what was had then + more)
local function needs(owner)
  storage.needs = storage.needs or {}
  local k = owner or 0
  storage.needs[k] = storage.needs[k] or {}
  return storage.needs[k]
end

local function add_need(owner, item, more, reason, after)
  local list = needs(owner)
  for _, nd in pairs(list) do if nd.item == item then return false end end
  list[#list + 1] = { item = item, more = more, reason = reason, after = after }
  return true
end

local function place_item(g)
  local items = g.ghost_prototype.items_to_place_this
  local it = items and items[1]
  if not it then return end
  return { name = it.name, count = it.count or 1, quality = g.type == "tile-ghost" and "normal" or g.quality.name }
end

-- takes from the owner/chests what crafting `count` of recipe needs (own pockets first, intermediates hand-crafted);
-- returns {item = short} when it can't. dry: only checks
local function gather(m, recipe, count, dry)
  local e = m.entity
  local inv = e.get_main_inventory()
  local own, pool, need, missing = {}, {}, {}, {}
  local function want(item, n, depth)
    own[item] = own[item] or inv.get_item_count(item)
    local use = math.min(own[item], n)
    own[item], n = own[item] - use, n - use
    if n <= 0 then return end
    pool[item] = pool[item] or available(m, item)
    use = math.min(pool[item], n)
    pool[item], n = pool[item] - use, n - use
    need[item] = (need[item] or 0) + use
    if n <= 0 then return end
    local r = depth < 6 and handcraft_recipe(e.force, item)
    if r then
      local per = 1
      for _, p in pairs(r.products) do if p.name == item then per = p.amount or p.amount_max or 1 end end
      local runs = math.ceil(n / per)
      for _, ing in pairs(r.ingredients) do want(ing.name, ing.amount * runs, depth + 1) end
    else
      missing[item] = (missing[item] or 0) + n
    end
  end
  for _, ing in pairs(recipe.ingredients) do want(ing.name, ing.amount * count, 0) end
  if next(missing) then return missing end
  if dry then return end
  for item, n in pairs(need) do take(m, item, n) end
end

local function key_of(e) return e.unit_number or (e.name .. e.position.x .. "," .. e.position.y) end

local function product_amount(r, item)
  for _, p in pairs(r.products) do if p.name == item then return p.amount or p.amount_max or 1 end end
  return 1
end

-- starts hand-crafting `count` of item (or, if that's too much, `single`); crafting goes on while it walks
local function craft_for(m, item, count, single)
  local r = handcraft_recipe(m.entity.force, item)
  if not r then return 0 end
  local per = product_amount(r, item)
  for _, n in ipairs({ count, single }) do
    local runs = math.ceil(n / per)
    if not gather(m, r, runs) then return m.entity.begin_crafting({ recipe = item, count = runs, silent = true }) * per end
  end
  return 0
end

-- the nearest ghost whose item it has, can take, or can hand-craft; and {item, count, single} to craft first
-- the item an entity marked for upgrade needs: {name, count, quality}
local function upgrade_item(ent)
  local proto, q = ent.get_upgrade_target()
  local it = proto and proto.items_to_place_this and proto.items_to_place_this[1]
  if not it then return end
  return { name = it.name, count = it.count or 1, quality = q and q.name or "normal" }
end

-- the nearest of `targets` whose item (item_of) it has, can take, or can hand-craft; and {item, count, single} to
-- craft first. What none of them can get is noted in job.missing (item -> how many short)
local function next_target(m, job, targets, item_of)
  local e = m.entity
  local cache, craftable, demand, best, bd, best_k = {}, {}, {}, nil, nil, nil
  job.short = {}
  local inv = e.get_main_inventory()
  for _, g in pairs(targets) do
    local key = key_of(g)
    local claim = claims()[key]
    if not job.skip[key] and (not claim or claim == m.name or not crew()[claim]) then
      local it = item_of(g)
      if it then
        local k = it.name .. "/" .. it.quality
        if cache[k] == nil then
          cache[k] = inv.get_item_count({ name = it.name, quality = it.quality }) + available(m, it.name, it.quality)
        end
        demand[k] = (demand[k] or 0) + it.count
        if cache[k] < it.count and craftable[k] == nil then
          local r = it.quality == "normal" and handcraft_recipe(e.force, it.name)
          craftable[k] = r and not gather(m, r, math.ceil(it.count / product_amount(r, it.name)), true) or false
        end
        if cache[k] >= it.count or craftable[k] then
          local d = dist2(e.position, g.position)
          if not bd or d < bd then best, bd, best_k = g, d, k end
        else
          job.short[k] = it
        end
      end
    end
  end
  for k, it in pairs(job.short) do job.missing[it.name] = demand[k] - cache[k] end
  if not best then return end
  claims()[key_of(best)] = m.name
  local it = item_of(best)
  if cache[best_k] >= it.count then return best end
  return best, { item = it.name, count = math.min(demand[best_k] - cache[best_k], 50), single = it.count }
end

local function next_ghost(m, job)
  local e = m.entity
  return next_target(m, job, e.surface.find_entities_filtered({ type = { "entity-ghost", "tile-ghost" }, force = e.force,
    position = anchor(m), radius = RADIUS }), place_item)
end

local function next_upgrade(m, job)
  local e = m.entity
  return next_target(m, job, e.surface.find_entities_filtered({ to_be_upgraded = true, force = e.force,
    position = anchor(m), radius = RADIUS }), upgrade_item)
end

-- what it did and what it's missing; on its own (auto) only news: something done, or a new shortage
local function report(m, job, verb, reason)
  local parts = {}
  if job.n > 0 then parts[#parts + 1] = verb .. " " .. job.n .. "." end
  local miss = {}
  for name, n in pairs(job.missing or {}) do
    miss[#miss + 1] = pretty(name)
    if type(n) == "number" and n > 0 then add_need(m.owner, name, n, reason or "the blueprint") end
  end
  table.sort(miss)
  local short = #miss > 0 and ("Out of " .. table.concat(miss, ", ", 1, math.min(#miss, 4)) .. ". I'll go get some.") or nil
  local news = short and (not job.auto or short ~= m.said_short)
  if news then parts[#parts + 1] = short end
  m.said_short = short
  -- on its own (auto, a goal step) what got done is routine: only a new shortage is news
  if #parts > 0 then say(m, table.concat(parts, " "), (job.auto or job.goal) and not news and "quiet" or nil)
  elseif not job.auto then say(m, "Nothing to " .. job.kind .. " here.") end
  if job.n > 0 and not job.auto then remember(m.owner, m.name .. ": " .. verb:lower() .. " " .. job.n) end
  if job.auto and job.n == 0 then m.auto_wait = game.tick + 600 end -- nothing doable: look less often
end

JOBS.build = function(m, job)
  local e = m.entity
  local g = job.target
  if not (g and g.valid) then
    job.missing = {}
    local c
    g, c = next_ghost(m, job)
    job.target = g
    if not g then
      report(m, job, "Built")
      if not e.get_main_inventory().is_empty() then table.insert(m.jobs, 2, { kind = "deliver" }) end
      return true
    end
    if c and e.crafting_queue_size == 0 then craft_for(m, c.item, c.count, c.single) end
    local it = place_item(g) -- (taken now: a trip to the chest comes before the walk to the ghost)
    local have = e.get_main_inventory().get_item_count({ name = it.name, quality = it.quality })
    if have < it.count then take(m, it.name, it.count - have, it.quality) end
    if m.visits and m.visits[1] then return false end -- (the trip first)
  end
  if not go(m, g.position, math.max(e.build_distance - 2, 2)) then return false end
  local key = key_of(g)
  local it = place_item(g)
  local inv = e.get_main_inventory()
  local id = { name = it.name, quality = it.quality }
  local have = inv.get_item_count(id)
  if have < it.count then have = have + take(m, it.name, it.count - have, it.quality) end
  if have < it.count and e.crafting_queue_size > 0 then return false end -- still crafting it
  if have >= it.count then
    g.revive({ raise_revive = true })
    if not g.valid then
      inv.remove({ name = it.name, count = it.count, quality = it.quality })
      job.n = job.n + 1
      m.built = (m.built or 0) + 1
      m.wait_until = game.tick + math.random(8, 20) -- (a hand's pace, not a robot's)
    end
  end
  if g.valid then job.skip[key] = true end
  claims()[key] = nil
  job.target = nil
  return false
end

JOBS.upgrade = function(m, job)
  local e = m.entity
  local t = job.target
  if not (t and t.valid and t.to_be_upgraded()) then
    job.missing = {}
    local c
    t, c = next_upgrade(m, job)
    job.target = t
    if not t then
      report(m, job, "Upgraded", "the upgrades")
      if not e.get_main_inventory().is_empty() then table.insert(m.jobs, 2, { kind = "deliver" }) end
      return true
    end
    if c and e.crafting_queue_size == 0 then craft_for(m, c.item, c.count, c.single) end
    local it = upgrade_item(t)
    local have = e.get_main_inventory().get_item_count({ name = it.name, quality = it.quality })
    if have < it.count then take(m, it.name, it.count - have, it.quality) end
    if m.visits and m.visits[1] then return false end -- (the trip first)
  end
  if not go(m, t.position, math.max(e.build_distance - 2, 2)) then return false end
  local key = key_of(t)
  local it = upgrade_item(t)
  local inv = e.get_main_inventory()
  local have = inv.get_item_count({ name = it.name, quality = it.quality })
  if have < it.count then have = have + take(m, it.name, it.count - have, it.quality) end
  if have < it.count and e.crafting_queue_size > 0 then return false end -- still crafting it
  if have >= it.count then
    local proto, q = t.get_upgrade_target()
    local new = e.surface.create_entity({ name = proto.name, quality = q, position = t.position, direction = t.direction,
      force = t.force, fast_replace = true, character = e, raise_built = true,
      type = t.type == "underground-belt" and t.belt_to_ground_type or nil })
    if new and new.valid then
      inv.remove({ name = it.name, count = it.count, quality = it.quality })
      job.n = job.n + 1
      m.wait_until = game.tick + math.random(8, 20)
    else
      job.skip[key] = true
    end
  else
    job.skip[key] = true
  end
  claims()[key] = nil
  job.target = nil
  return false
end

JOBS.deconstruct = function(m, job)
  local e = m.entity
  local t = job.target
  if not (t and t.valid and t.to_be_deconstructed()) then
    t = nil
    local bd
    for _, c in pairs(e.surface.find_entities_filtered({ position = anchor(m), radius = RADIUS, to_be_deconstructed = true })) do
      local key = key_of(c)
      local claim = claims()[key]
      if c.type ~= "character" and not job.skip[key] and c.minable and (not claim or claim == m.name or not crew()[claim]) then
        local d = dist2(e.position, c.position)
        if not bd or d < bd then t, bd = c, d end
      end
    end
    job.target = t
    if t then claims()[key_of(t)] = m.name end
    if not t then
      report(m, job, "Cleared")
      if not e.get_main_inventory().is_empty() then table.insert(m.jobs, 2, { kind = "deliver" }) end
      return true
    end
  end
  if not go(m, t.position, math.max(e.reach_distance - 2, 2)) then return false end
  local key = key_of(t)
  claims()[key] = nil
  local mt = t.prototype.mineable_properties.mining_time or 0.5
  if e.mine_entity(t, false) then
    job.n = job.n + 1
    m.wait_until = game.tick + math.min(math.floor(mt * 40), 60) + 4 -- (taking it down takes a moment)
  elseif e.get_main_inventory().count_empty_stacks() == 0 then
    table.insert(m.jobs, 1, { kind = "deliver" }) -- pockets full: drop off, then carry on
    return false
  else
    job.skip[key] = true
  end
  job.target = nil
  return false
end

local function nearest_source(m, job)
  local names = sources_for(job.item)
  if #names == 0 then return end
  local e = m.entity
  for _, r in ipairs({ 16, 48, 128 }) do
    local best, bd
    for _, s in pairs(e.surface.find_entities_filtered({ name = names, position = e.position, radius = r })) do
      local key = s.position.x .. "," .. s.position.y
      if not job.skip[key] then
        local d = dist2(e.position, s.position)
        if not bd or d < bd then best, bd = s, d end
      end
    end
    if best then return best end
  end
end

JOBS.mine = function(m, job)
  local e = m.entity
  local inv = e.get_main_inventory()
  local cur = inv.get_item_count(job.item)
  if job.last and cur > job.last then
    job.n = job.n + cur - job.last
    job.since = game.tick
  end
  job.last = cur
  if job.n >= job.count then
    stop_mining(m)
    say(m, "Got " .. job.n .. " " .. pretty(job.item) .. ".", job.goal and "quiet")
    table.insert(m.jobs, 2, { kind = "deliver" })
    return true
  end
  if not inv.can_insert({ name = job.item }) then
    stop_mining(m)
    table.insert(m.jobs, 1, { kind = "deliver" })
    return false
  end
  local t = job.target
  if not (t and t.valid) or job.since and game.tick - job.since > 900 then -- (15 s at it with nothing to show)
    if t and t.valid then job.skip[t.position.x .. "," .. t.position.y] = true end
    stop_mining(m)
    t = nearest_source(m, job)
    job.target, job.since = t, nil
    if not t then
      say(m, "No " .. pretty(job.item) .. " to mine around here." .. (job.n > 0 and (" Got " .. job.n .. ".") or ""))
      if job.n > 0 then table.insert(m.jobs, 2, { kind = "deliver" }) end
      return true
    end
  end
  local reach = e.resource_reach_distance -- hand mining, trees and rocks too, needs to be this close
  if not go(m, t.position, math.max(reach - 0.6, 1)) then
    m.mining = nil
    job.since = nil -- (the time to give up on a source counts from getting there, not the trip)
    return false
  end
  job.since = job.since or game.tick
  m.mining = t.position
  return false
end

JOBS.craft = function(m, job)
  local e = m.entity
  if not job.started then
    local r = handcraft_recipe(e.force, job.recipe)
    if not r then say(m, "I can't hand-craft " .. pretty(job.recipe) .. ".") return true end
    local per = product_amount(r, job.recipe)
    job.runs = math.ceil(job.count / per)
    local missing = gather(m, r, job.runs)
    if missing then
      local parts = {}
      local last
      for item, n in pairs(missing) do
        parts[#parts + 1] = n .. " " .. pretty(item)
        if add_need(m.owner, item, n, pretty(job.recipe)) then last = item end
      end
      for _, nd in pairs(needs(m.owner)) do -- craft again once the last of it is in
        if nd.item == last then nd.after = { kind = "craft", recipe = job.recipe, count = job.count } end
      end
      say(m, "For " .. job.count .. " " .. pretty(job.recipe) .. " I'm short " .. table.concat(parts, ", ") .. ". I'll go get it.")
      return true
    end
    job.started = e.begin_crafting({ recipe = job.recipe, count = job.runs, silent = true }) * per
    if job.started == 0 then say(m, "Couldn't start on " .. pretty(job.recipe) .. ".") unload(m) return true end
    return false
  end
  if e.crafting_queue_size > 0 then return false end
  job.n = job.started
  if job.keep then return true end -- (its own gun or ammo: equipped already)
  say(m, "Made " .. job.started .. " " .. pretty(job.recipe) .. ".", job.goal and "quiet")
  table.insert(m.jobs, 2, { kind = "deliver" })
  return true
end

JOBS.fetch = function(m, job)
  local got = take(m, job.item, job.count, nil, true)
  say(m, got > 0 and ("Got " .. got .. " " .. pretty(job.item) .. " from the chests.") or ("No " .. pretty(job.item) .. " in the chests."),
    got > 0 and job.goal and "quiet" or nil)
  if got > 0 then table.insert(m.jobs, 2, { kind = "deliver" }) end
  return true
end

JOBS.deliver = function(m, job)
  if m.entity.get_main_inventory().is_empty() then return true end
  if not go(m, spot(m, anchor(m)), 2) then return false end
  unload(m)
  return true
end


-- ---------------------------------------------------------------------------------------------- smelting and goals

local FUELS = { "coal", "solid-fuel", "wood" }
local machine_cache = {} -- item -> names of recipes (item ingredients only) that make it in a machine

-- the recipe to make item in a machine (one hand-crafting can't do), preferring the one named after it
local function machine_recipe(force, item)
  if not machine_cache[item] then
    local list = {}
    local hand = hand_categories()
    for name, r in pairs(prototypes.recipe) do
      local ok = not r.hidden and not hand[r.category] and #r.ingredients > 0
      for _, i in pairs(r.ingredients) do if i.type ~= "item" then ok = false end end
      local makes = false
      for _, p in pairs(r.products) do if p.type == "item" and p.name == item then makes = true end end
      if ok and makes then list[#list + 1] = name end
    end
    table.sort(list, function(a, b)
      if (a == item) ~= (b == item) then return a == item end
      if #a ~= #b then return #a < #b end
      return a < b
    end)
    machine_cache[item] = list
  end
  for _, name in ipairs(machine_cache[item]) do
    local r = force.recipes[name]
    if r and r.enabled then return r end
  end
end

local IN = { furnace = defines.inventory.furnace_source, ["assembling-machine"] = defines.inventory.assembling_machine_input }
local OUT = { furnace = defines.inventory.furnace_result, ["assembling-machine"] = defines.inventory.assembling_machine_output }

-- machines near the owner free for this recipe, nearest first, up to 4: a furnace that's empty or on the same input;
-- an assembler-type machine (overhaul mods' furnaces too) with no recipe and nothing in it, or already on this recipe
local function machines_for(m, r, item)
  local e = m.entity
  local out = {}
  for _, f in pairs(e.surface.find_entities_filtered({ type = { "furnace", "assembling-machine" }, force = e.force,
    position = anchor(m), radius = RADIUS })) do
    local p = f.prototype
    local in_line = false -- (a bpgen line's machines are fed by the line)
    for _, g in pairs(storage.goals or {}) do
      local b = g.line and g.line.box
      if b and f.position.x >= b[1] and f.position.y >= b[2] and f.position.x <= b[1] + b[3] and f.position.y <= b[2] + b[4] then
        in_line = true
      end
    end
    if not in_line and not crew_built(f) then -- (a machine of yours that inserters feed or empty is part of a line: not theirs)
      local b = f.bounding_box
      for _, i in pairs(e.surface.find_entities_filtered({ type = "inserter", force = e.force,
        area = { { b.left_top.x - 3, b.left_top.y - 3 }, { b.right_bottom.x + 3, b.right_bottom.y + 3 } } })) do
        if i.drop_target == f or i.pickup_target == f then in_line = true break end
      end
    end
    if not in_line and p.crafting_categories[r.category] and f.status ~= defines.entity_status.no_power
      and not kept_out(f.surface, f.position)
      and (not p.fixed_recipe or p.fixed_recipe == r.name) then
      local src, res = f.get_inventory(IN[f.type]), f.get_inventory(OUT[f.type])
      local free
      if f.type == "furnace" then
        free = src.is_empty() or src.get_item_count(r.ingredients[1].name) > 0
      else
        local cur = f.get_recipe()
        free = (not cur and src.is_empty()) or (cur and cur.name == r.name)
      end
      if free and (res.is_empty() or res.get_item_count(item) > 0) then out[#out + 1] = f end
    end
  end
  table.sort(out, function(a, b) return dist2(e.position, a.position) < dist2(e.position, b.position) end)
  for i = #out, 5, -1 do out[i] = nil end
  return out
end

local function fuel_available(m)
  local inv = m.entity.get_main_inventory()
  for _, f in ipairs(FUELS) do
    if prototypes.item[f] and inv.get_item_count(f) + available(m, f) > 0 then return f end
  end
end

local function needs_fuel(f)
  local fuel = f.burner and f.get_fuel_inventory()
  return fuel and fuel.get_item_count() < 3
end

local function refuel(m, f)
  if not needs_fuel(f) then return end
  local inv = m.entity.get_main_inventory()
  local name = fuel_available(m)
  if not name then return end
  if inv.get_item_count(name) < 10 then take(m, name, 10 - inv.get_item_count(name)) end
  local n = math.min(inv.get_item_count(name), 10)
  if n > 0 then
    local put = f.get_fuel_inventory().insert({ name = name, count = n })
    if put > 0 then inv.remove({ name = name, count = put }) end
  end
end


-- -------------------------------------------------------------------------------------------------------- vehicles
-- Long trips (over TRIP tiles). A train of yours standing at a stop within 24 tiles whose schedule goes to a stop
-- within 60 tiles of where they're headed: they get on and ride along (its schedule left alone), and get off there.
-- Else a car or tank of yours parked within 24 tiles with no one in it (fuelled from stock when low): they drive it
-- along a path the pathfinder found for the car, and park it within 12 tiles of the goal. Stuck in the car for 2 s
-- they back up; a third time, or no route for a car, they get out and go on foot (or fly) and leave cars alone for a
-- minute.
local R = defines.riding

leave = function(m)
  local r = m.ride
  m.ride = nil
  local e = m.entity
  if not (e.valid and e.vehicle) then return end
  local v = e.vehicle
  if v.type == "car" then e.riding_state = { acceleration = R.acceleration.nothing, direction = R.direction.straight } end
  v.set_driver(nil)
  local at = e.surface.find_non_colliding_position(CREW, v.position, 6, 0.5) -- (beside it, not back where they got in)
  if at then
    e.teleport(at)
    m.drop_at = at -- (and again next tick: the game puts them back where they got in once the tick is over)
  end
  if r and r.kind == "car" and r.car.valid and not r.car.get_driver() then -- (handbrake: it stays where they left it)
    r.car.riding_state = { acceleration = R.acceleration.braking, direction = R.direction.straight }
  end
end

local function taken(v)
  for _, o in pairs(crew()) do if o.ride and (o.ride.car == v or o.ride.seat == v) then return true end end
end

-- a train standing near them going where they're going, and a free seat on it
local function train_for(m, goal)
  local e = m.entity
  for _, stop in pairs(e.surface.find_entities_filtered({ type = "train-stop", force = e.force, position = e.position, radius = 24 })) do
    local t = stop.get_stopped_train()
    local sched = t and not t.manual_mode and t.state == defines.train_state.wait_station and t.schedule
    for _, rec in pairs(sched and sched.records or {}) do
      if rec.station and rec.station ~= stop.backer_name then
        for _, to in pairs(game.train_manager.get_train_stops({ station_name = rec.station, surface = e.surface })) do
          if dist2(to.position, goal) < 60 * 60 and dist2(to.position, goal) < dist2(e.position, goal) / 4 then
            local seat, sd
            for _, c in pairs(t.carriages) do
              if not c.get_driver() and not taken(c) then
                local d = dist2(c.position, e.position)
                if not sd or d < sd then seat, sd = c, d end
              end
            end
            if seat then return t, seat, to end
          end
        end
      end
    end
  end
end

local function car_for(m)
  local e = m.entity
  local best, bd
  for _, c in pairs(e.surface.find_entities_filtered({ type = "car", force = e.force, position = e.position, radius = 24 })) do
    local fuel = c.get_fuel_inventory()
    if not c.get_driver() and not c.get_passenger() and not taken(c) and (not fuel or not fuel.is_empty() or fuel_available(m)) then
      local d = dist2(c.position, e.position)
      if not bd or d < bd then best, bd = c, d end
    end
  end
  return best
end

vehicle_trip = function(m, pos, radius)
  if m.fly or m.retreat or game.tick < (m.no_ride or 0) then return false end
  local goal = { x = pos.x, y = pos.y }
  local t, seat, to = train_for(m, goal)
  if t then
    m.ride = { kind = "train", train = t, seat = seat, from = t.station, to = to, goal = goal, radius = radius, t0 = game.tick }
  else
    local car = car_for(m)
    if not car then return false end
    m.ride = { kind = "car", car = car, goal = goal, radius = radius, t0 = game.tick }
  end
  stop_walk(m)
  m.rides = (m.rides or 0) + 1
  return true
end

local function car_path(m)
  local r, car = m.ride, m.ride.car
  local id = car.surface.request_path({ bounding_box = { { -1, -1 }, { 1, 1 } }, collision_mask = car.prototype.collision_mask,
    start = car.position, goal = r.goal, force = car.force, radius = 10, entity_to_ignore = car, path_resolution_modifier = -2,
    pathfind_flags = { cache = false, prefer_straight_paths = true } })
  storage.paths = storage.paths or {}
  storage.paths[id] = m.name
  r.path_id, r.path, r.i, r.repath = id, nil, 1, nil
end

-- each tick of a trip: walking up to the vehicle, getting in; on a train, waiting for its stop; in a car, driving
local function riding(m)
  local r, e = m.ride, m.entity
  local v = r.kind == "car" and r.car or r.seat
  if not (v and v.valid) then return leave(m) end
  if e.vehicle ~= v then
    if r.kind == "train" and not (r.train.valid and r.train.station) then m.move = nil return leave(m) end -- (it left)
    if game.tick - r.t0 > 900 then m.move = nil return leave(m) end
    if dist2(e.position, v.position) > 9 then
      if not (m.move and dist2(m.move.goal, v.position) < 4) then
        m.move = { goal = { x = v.position.x, y = v.position.y }, radius = 2, hops = 0, still_total = 0 }
        request_path(m)
      end
      return
    end
    stop_walk(m)
    if r.kind == "car" then refuel(m, v) end
    v.set_driver(e)
    if e.vehicle ~= v then return leave(m) end
    r.t0 = game.tick
    if r.kind == "car" then car_path(m) end
    return
  end
  if r.kind == "train" then
    local tr = r.train
    r.still = tr.valid and math.abs(tr.speed) < 0.01 and not tr.station and (r.still or 0) + 1 or 0
    if not tr.valid or tr.station == r.to or game.tick - r.t0 > 10800 or r.still > 1800 -- (standing out on the line: off)
      or tr.station == r.from and game.tick - r.t0 > 3600 then -- (a minute aboard and it hasn't left: off again)
      if tr.valid and tr.station ~= r.to then m.no_ride = game.tick + 3600 end
      leave(m)
    end
    return
  end
  local car = v
  if r.repath then car_path(m) end
  local d2 = dist2(car.position, r.goal)
  if d2 < 12 * 12 or r.failed then
    if math.abs(car.speed) > 0.02 then
      e.riding_state = { acceleration = R.acceleration.braking, direction = R.direction.straight }
      return
    end
    if r.failed then m.no_ride = game.tick + 3600 end
    return leave(m)
  end
  if not r.path then
    e.riding_state = { acceleration = R.acceleration.braking, direction = R.direction.straight }
    return
  end
  local wp = r.path[r.i]
  while wp and dist2(car.position, wp.position) < 16 do
    r.i = r.i + 1
    wp = r.path[r.i]
  end
  local to = wp and wp.position or r.goal
  local want = (math.atan2(to.x - car.position.x, -(to.y - car.position.y)) / (2 * math.pi)) % 1
  local diff = (want - car.orientation + 0.5) % 1 - 0.5
  local dir = diff > 0.01 and R.direction.right or diff < -0.01 and R.direction.left or R.direction.straight
  if r.back_until and game.tick < r.back_until then -- (backing out of something, wheel the other way)
    e.riding_state = { acceleration = R.acceleration.reversing,
      direction = dir == R.direction.right and R.direction.left or dir == R.direction.left and R.direction.right or dir }
    return
  end
  r.slow = math.abs(car.speed) < 0.01 and (r.slow or 0) + 1 or 0
  if r.slow > 120 then
    r.slow, r.backs = 0, (r.backs or 0) + 1
    if r.backs > 2 then r.failed = true return end
    r.back_until = game.tick + 45
    return
  end
  local braking = (math.abs(diff) > 0.2 and car.speed > 0.12) or (d2 < 30 * 30 and car.speed > 0.2)
  e.riding_state = { acceleration = braking and R.acceleration.braking or R.acceleration.accelerating, direction = dir }
end

-- loads machines near the owner with the ingredients (and fuel; the recipe when it's an assembler), then collects
-- what they make
JOBS.smelt = function(m, job)
  local e = m.entity
  local inv = e.get_main_inventory()
  local r = e.force.recipes[job.recipe]
  if not job.machines then
    job.machines = machines_for(m, r, job.item)
    if #job.machines == 0 then say(m, "No free machine near you for " .. pretty(job.item) .. ".") return true end
    job.runs = math.ceil(job.count / product_amount(r, job.item))
    for _, ing in pairs(r.ingredients) do
      local need, have = ing.amount * job.runs, inv.get_item_count(ing.name)
      if have < need then take(m, ing.name, need - have) end
    end
    job.i, job.stage, job.left = 1, "load", job.runs
  end
  if job.stage == "load" then
    local f = job.machines[job.i]
    if not f then
      job.stage, job.since = "collect", game.tick
      return false
    end
    if not f.valid then job.i = job.i + 1 return false end
    if not go(m, f.position, math.max(e.reach_distance - 2, 2)) then return false end
    if f.type == "assembling-machine" then
      local cur = f.get_recipe()
      if not (cur and cur.name == r.name) then f.set_recipe(r.name) end
    end
    local runs = math.ceil(job.left / (#job.machines - job.i + 1))
    local src = f.get_inventory(IN[f.type])
    for _, ing in pairs(r.ingredients) do
      local n = math.min(inv.get_item_count(ing.name), ing.amount * runs)
      local put = n > 0 and src.insert({ name = ing.name, count = n }) or 0
      if put > 0 then inv.remove({ name = ing.name, count = put }) end
    end
    job.left = job.left - runs
    refuel(m, f)
    job.i = job.i + 1
    return false
  end
  local best, busy
  for _, f in pairs(job.machines) do
    if f.valid then
      if not best and not f.get_inventory(OUT[f.type]).is_empty() then best = f end
      if not f.get_inventory(IN[f.type]).is_empty() or f.is_crafting() then busy = true end
    end
  end
  if best and (job.n < job.count or not busy) then
    if not go(m, best.position, math.max(e.reach_distance - 2, 2)) then return false end
    local res = best.get_inventory(OUT[best.type])
    for _, it in pairs(res.get_contents()) do -- by-products too: they'd block the machine
      local got = inv.insert({ name = it.name, count = it.count, quality = it.quality })
      if got > 0 then
        res.remove({ name = it.name, count = got, quality = it.quality })
        if it.name == job.item then job.n, job.since = job.n + got, game.tick end
      end
    end
    refuel(m, best)
    return false
  end
  if busy and job.n < job.count and game.tick - job.since < 3600 then return false end
  say(m, "Made " .. job.n .. " " .. pretty(job.item) .. ".", job.goal and "quiet")
  table.insert(m.jobs, 2, { kind = "deliver" })
  return true
end

-- burners low on fuel within 150 tiles of the owner, nearest first
low_burners = function(m, limit)
  local e = m.entity
  local out = {}
  for _, f in pairs(e.surface.find_entities_filtered({ type = { "boiler", "furnace", "mining-drill", "assembling-machine",
    "burner-generator", "inserter", "lab" }, force = e.force, position = anchor(m), radius = 150 })) do
    if needs_fuel(f) and not kept_out(f.surface, f.position) then out[#out + 1] = f end
  end
  table.sort(out, function(a, b) return dist2(e.position, a.position) < dist2(e.position, b.position) end)
  for i = #out, limit + 1, -1 do out[i] = nil end
  return out
end

-- is anything of the force's (not the crew's own, not a character) in area; or a floor the player laid (concrete,
-- stone path: a tile with a hidden tile under it)
local function players_stuff(s, force, area)
  for _, e in pairs(s.find_entities_filtered({ area = area, force = force })) do
    if e.type ~= "character" and e.type ~= "character-corpse" and not crew_built(e) then return true end
  end
  return s.count_tiles_filtered({ area = area, has_hidden_tile = true, limit = 1 }) > 0
end

-- where the crew may put a building of `name` near `near`: on its own grid (a 2x2 at whole tiles, a 3x3 at half tiles:
-- nothing shifts when it's built), placeable as a player's would be, `clear` tiles clear of the player's buildings,
-- ghosts and floors (so it never crowds a production line, an inserter or a walkway) and a tile clear of the crew's
-- own. Nearest first, out to 40 tiles
local function free_spot(s, force, name, near, clear)
  local box = prototypes.entity[name].collision_box
  local w = math.ceil(box.right_bottom.x - box.left_top.x - 0.01)
  local h = math.ceil(box.right_bottom.y - box.left_top.y - 0.01)
  local ox, oy = (w % 2 == 1) and 0.5 or 0, (h % 2 == 1) and 0.5 or 0
  local cx, cy = math.floor(near.x + 0.5), math.floor(near.y + 0.5)
  for r = 0, 40 do
    for dx = -r, r do
      for dy = -r, r do
        if math.max(math.abs(dx), math.abs(dy)) == r then
          local pos = { x = cx + dx + ox, y = cy + dy + oy }
          -- (count_entities_filtered's invert would invert the force too: the player's own buildings then didn't count)
          if s.can_place_entity({ name = name, position = pos, force = force, build_check_type = defines.build_check_type.manual })
            and not kept_out(s, pos)
            and not players_stuff(s, force, { { pos.x - w / 2 - clear, pos.y - h / 2 - clear }, { pos.x + w / 2 + clear, pos.y + h / 2 + clear } })
            and s.count_entities_filtered({ area = { { pos.x - w / 2 - 1, pos.y - h / 2 - 1 }, { pos.x + w / 2 + 1, pos.y + h / 2 + 1 } },
              force = force, type = { "furnace", "assembling-machine", "electric-pole", "boiler", "generator", "offshore-pump" }, limit = 1 }) == 0 then
            return pos
          end
        end
      end
    end
  end
end

-- where the crew's own machines go: beside the ones they built before, else open ground a little way from the owner
local function crew_area(m, type)
  storage.crew_built = storage.crew_built or {}
  for i = #storage.crew_built, 1, -1 do
    local b = storage.crew_built[i]
    if not b.valid then
      table.remove(storage.crew_built, i)
    elseif b.type == type and b.surface == m.entity.surface and dist2(b.position, anchor(m)) < RADIUS * RADIUS then
      return b.position
    end
  end
  local a = anchor(m)
  return { x = a.x + 8, y = a.y - 6 }
end

JOBS.place = function(m, job)
  local e = m.entity
  local inv = e.get_main_inventory()
  if inv.get_item_count(job.item) == 0 and take(m, job.item, 1) == 0 then say(m, "No " .. pretty(job.item) .. " to place.") return true end
  local proto = prototypes.item[job.item].place_result
  local spec = { name = proto.name, position = job.at, direction = job.direction, force = e.force,
    build_check_type = defines.build_check_type.manual }
  if job.at and not e.surface.can_place_entity(spec) then
    if job.layout and storage.steam then storage.steam[job.layout] = nil end -- something's in the way: plan it again
    if job.fixed then return true end
    job.at = nil
  end
  if not job.at then
    job.at = free_spot(e.surface, e.force, proto.name, crew_area(m, proto.type), 3)
    if not job.at then say(m, "No clear ground for a " .. pretty(job.item) .. " near you.") return true end
  end
  if not go(m, job.at, math.max(e.build_distance - 2, 2)) then return false end
  spec.position = job.at
  if not e.surface.can_place_entity(spec) then -- (something got built there meanwhile)
    if job.fixed then return true end
    job.at = nil
    return false
  end
  spec.build_check_type, spec.raise_built = nil, true
  local built = e.surface.create_entity(spec)
  if built then
    inv.remove({ name = job.item, count = 1 })
    job.n = 1
    if not job.fixed then
      storage.crew_built = storage.crew_built or {}
      table.insert(storage.crew_built, built)
    end
    say(m, "Set up a " .. pretty(job.item) .. ".", "quiet")
  end
  return true
end

-- refuels burners (boilers, furnaces, drills...) near the owner that are running low
JOBS.tend = function(m, job)
  local e = m.entity
  job.targets = job.targets or low_burners(m, 6)
  local f = job.targets[1]
  if not f then return true end
  if not (f.valid and needs_fuel(f)) or not fuel_available(m) then table.remove(job.targets, 1) return false end
  if not go(m, f.position, math.max(e.reach_distance - 2, 2)) then return false end
  refuel(m, f)
  job.n = job.n + 1
  table.remove(job.targets, 1)
  return false
end

local function goals()
  storage.goals = storage.goals or {}
  return storage.goals
end

-- how many of item the owner has: pockets, chests near them, and what the crew carries
local function goal_have(owner, item)
  local n, first = 0, nil
  for _, m in pairs(crew()) do
    if m.owner == owner and m.entity.valid then
      first = first or m
      n = n + m.entity.get_item_count(item) -- (all its inventories: a crafted gun goes straight to the gun slot)
    end
  end
  return first and n + available(first, item) or n
end


-- --------------------------------------------------------------------------------------------- machines and power

local plan -- (below)
local GENERATORS = { "generator", "burner-generator", "solar-panel", "electric-energy-interface" }

local function have_count(m, item)
  return m.entity.get_main_inventory().get_item_count(item) + available(m, item)
end

-- is anything generating in this electric network (looked for within 200 tiles)
local function net_has_power(surface, force, id, near)
  if not id then return false end
  for _, g in pairs(surface.find_entities_filtered({ type = GENERATORS, force = force, position = near, radius = 200 })) do
    if g.electric_network_id == id then return true end
  end
  return false
end

-- where water meets land nearest the owner: an offshore pump, a boiler on its output and a steam engine on the boiler's
-- steam, found by trial-placing each piece and keeping it only when its fluidbox connects (modded pieces work too)
local function connects(ent, to)
  for i = 1, #ent.fluidbox do
    for _, fb in pairs(ent.fluidbox.get_connections(i)) do if fb.owner == to then return true end end
  end
  return false
end

local function attach(s, force, name, to, r)
  for _, d in ipairs({ 0, 4, 8, 12 }) do
    for x = -r, r, 0.5 do
      for y = -r, r, 0.5 do
        local spec = { name = name, position = { to.position.x + x, to.position.y + y }, direction = d, force = force,
          build_check_type = defines.build_check_type.manual }
        if s.can_place_entity(spec) then
          spec.build_check_type = nil
          local ent = s.create_entity(spec)
          if ent then
            if connects(ent, to) then return ent end
            ent.destroy()
          end
        end
      end
    end
  end
end

local function steam_layout(m)
  local e = m.entity
  local s, f, a = e.surface, e.force, anchor(m)
  local tiles = s.find_tiles_filtered({ position = a, radius = 150, collision_mask = "water_tile", limit = 20000 })
  table.sort(tiles, function(t1, t2) return dist2(t1.position, a) < dist2(t2.position, a) end)
  local tried = {}
  for i = 1, math.min(#tiles, 400) do
    local tp = tiles[i].position
    for ox = -1, 1 do
      for oy = -1, 1 do
        local pos = { x = tp.x + ox + 0.5, y = tp.y + oy + 0.5 }
        local k = pos.x .. "," .. pos.y
        if not tried[k] then
          tried[k] = true
          for _, d in ipairs({ 0, 4, 8, 12 }) do
            local spec = { name = "offshore-pump", position = pos, direction = d, force = f, build_check_type = defines.build_check_type.manual }
            if s.can_place_entity(spec) then
              spec.build_check_type = nil
              local pump = s.create_entity(spec)
              local boiler = pump and attach(s, f, "boiler", pump, 3)
              local engine = boiler and attach(s, f, "steam-engine", boiler, 5)
              local out
              if engine then
                out = {}
                for _, ent in ipairs({ pump, boiler, engine }) do
                  out[#out + 1] = { name = ent.name, position = { x = ent.position.x, y = ent.position.y }, direction = ent.direction }
                end
              end
              for _, ent in ipairs({ engine, boiler, pump }) do if ent and ent.valid then ent.destroy() end end
              if out then return out end
            end
          end
        end
      end
    end
  end
end

-- the next piece of a steam plant for the owner; nil once it's all standing
local function steam_step(m, depth)
  if not (prototypes.entity["offshore-pump"] and prototypes.entity["boiler"] and prototypes.entity["steam-engine"]) then
    return nil, "I don't know how to build power here."
  end
  local key = m.owner or 0
  storage.steam = storage.steam or {}
  local lay = storage.steam[key]
  if not lay then
    lay = steam_layout(m)
    if not lay then return nil, "There's no water near you to build steam power by." end
    storage.steam[key] = lay
  end
  local s = m.entity.surface
  for _, piece in ipairs(lay) do
    if not s.find_entities_filtered({ name = piece.name, position = piece.position, radius = 0.5, limit = 1 })[1] then
      local item = prototypes.entity[piece.name].items_to_place_this[1].name
      if have_count(m, item) > 0 then
        return { kind = "place", item = item, at = piece.position, direction = piece.direction, layout = key, fixed = true }
      end
      return plan(m, item, 1, depth + 1)
    end
  end
end

local function pole_item(m)
  for _, name in ipairs({ "medium-electric-pole", "small-electric-pole" }) do
    if prototypes.item[name] and have_count(m, name) > 0 then return name end
  end
  return prototypes.item["small-electric-pole"] and "small-electric-pole"
end

-- the next step to power this machine: grow poles from the nearest powered pole (or a generator) towards it, build
-- steam power if there's nothing, fuel the boilers if it's all connected but dark
local function power_to(m, machine, depth)
  local e = m.entity
  local s, force = e.surface, e.force
  local from, fd
  for _, p in pairs(s.find_entities_filtered({ type = "electric-pole", force = force, position = machine.position, radius = 150 })) do
    if net_has_power(s, force, p.electric_network_id, p.position) then
      local d = dist2(p.position, machine.position)
      if not fd or d < fd then from, fd = p, d end
    end
  end
  if not from then
    for _, g in pairs(s.find_entities_filtered({ type = GENERATORS, force = force, position = machine.position, radius = 150 })) do
      local d = dist2(g.position, machine.position)
      if not fd or d < fd then from, fd = g, d end
    end
  end
  if not from then
    local job, why = steam_step(m, depth)
    if job or why then return job, why end
    return nil, "Steam power is up but not connected yet."
  end
  if from.electric_network_id and from.electric_network_id == machine.electric_network_id then
    -- connected, no power: the burners feeding it need fuel
    if #low_burners(m, 1) > 0 then
      if fuel_available(m) then return { kind = "tend" } end
      return plan(m, nearest_source(m, { item = "coal", skip = {} }) and "coal" or "wood", 20, depth + 1)
    end
    return nil, "The power's connected but there isn't enough of it for the " .. pretty(machine.name) .. "."
  end
  local item = pole_item(m)
  if not item then return nil, "I don't know how to make electric poles here." end
  if have_count(m, item) == 0 then return plan(m, item, 5, depth + 1) end
  local pp = prototypes.item[item].place_result
  local reach, supply = pp.get_max_wire_distance() - 0.5, pp.get_supply_area_distance()
  local dx, dy = machine.position.x - from.position.x, machine.position.y - from.position.y
  local d = math.sqrt(dx * dx + dy * dy)
  local is_pole = from.type == "electric-pole"
  for _, step in ipairs(is_pole and { reach, reach - 1.5, reach - 3 } or { 3, 4, 2 }) do
    step = math.min(step, math.max(d - supply - 1, 1))
    local at = s.find_non_colliding_position(pp.name, { x = from.position.x + dx / d * step, y = from.position.y + dy / d * step }, 2, 0.5, true)
    if at and (not is_pole or math.sqrt(dist2(at, from.position)) <= reach) then
      return { kind = "place", item = item, at = at, quiet = true, fixed = true }
    end
  end
  return nil, "No room for poles between the power and the " .. pretty(machine.name) .. "."
end

-- no free machine for recipe r: power one that's standing dark, else make one (burner-powered first) and set it up
local function need_machine(m, r, item, depth)
  local e = m.entity
  for _, f in pairs(e.surface.find_entities_filtered({ type = { "furnace", "assembling-machine" }, force = e.force,
    position = anchor(m), radius = RADIUS })) do
    if f.prototype.crafting_categories[r.category] and f.status == defines.entity_status.no_power then
      return power_to(m, f, depth)
    end
  end
  -- (never a row of them: three of the crew's own for this already and none usable means something else is wrong)
  local own = 0
  for _, b in pairs(storage.crew_built or {}) do
    if b.valid and b.prototype.crafting_categories and b.prototype.crafting_categories[r.category]
      and dist2(b.position, anchor(m)) < RADIUS * RADIUS then own = own + 1 end
  end
  if own >= 3 then return nil, "I've set up " .. own .. " machines for " .. pretty(item) .. " and can't use them; something's in the way." end
  local options = {}
  for name, p in pairs(prototypes.get_entity_filtered({ { filter = "crafting-category", crafting_category = r.category } })) do
    local it = (p.type == "furnace" or p.type == "assembling-machine") and p.items_to_place_this and p.items_to_place_this[1]
    if it and (not p.fixed_recipe or p.fixed_recipe == r.name) then
      local score = (p.burner_prototype and 0 or 2) + (have_count(m, it.name) > 0 and 0 or 1)
      options[#options + 1] = { item = it.name, score = score }
    end
  end
  table.sort(options, function(a, b) if a.score ~= b.score then return a.score < b.score end return a.item < b.item end)
  local why = "Nothing I can build makes " .. pretty(item) .. "."
  for _, o in ipairs(options) do
    if have_count(m, o.item) > 0 then return { kind = "place", item = o.item } end
    local job, w = plan(m, o.item, 1, depth + 1)
    if job then return job end
    why = w or why
  end
  return nil, why
end

-- the next job towards having n more of item; nil and why when nothing gets there
plan = function(m, item, n, depth)
  depth = depth or 0
  if depth > 10 then return nil, "That's too many steps for me." end
  local e = m.entity
  if nearest_source(m, { item = item, skip = {} }) then return { kind = "mine", item = item, count = math.min(n, 50) } end
  local r = handcraft_recipe(e.force, item)
  if r then
    local batch = math.min(n, 20)
    local missing = gather(m, r, math.ceil(batch / product_amount(r, item)), true)
    if not missing then return { kind = "craft", recipe = item, count = batch } end
    for ing, k in pairs(missing) do return plan(m, ing, k, depth + 1) end
  end
  local mr = machine_recipe(e.force, item)
  if mr then
    local machines = machines_for(m, mr, item)
    if #machines == 0 then return need_machine(m, mr, item, depth) end
    local per = product_amount(mr, item)
    local runs = math.ceil(math.min(n, 50) / per)
    local own = e.get_main_inventory()
    for _, ing in pairs(mr.ingredients) do
      local have = own.get_item_count(ing.name) + available(m, ing.name)
      if have < ing.amount then return plan(m, ing.name, ing.amount * runs - have, depth + 1) end
      runs = math.min(runs, math.floor(have / ing.amount))
    end
    for _, f in pairs(machines) do
      if needs_fuel(f) and not fuel_available(m) then
        return plan(m, nearest_source(m, { item = "coal", skip = {} }) and "coal" or "wood", 20, depth + 1)
      end
    end
    return { kind = "smelt", item = item, recipe = mr.name, count = runs * per }
  end
  local locked = e.force.recipes[item]
  if locked and not locked.enabled then return nil, pretty(item) .. " isn't researched yet." end
  return nil, "I don't know how to make " .. pretty(item) .. "."
end

-- ------------------------------------------------------------------------------------------------ bpgen lines

-- a line from bpgen for a goal: {state = "asked"|"placed", box = {x, y, w, h}, inputs = {{items, position}},
-- outputs = {{item, position}}}. bpgen places its ghosts; the crew build them (auto build), power and fuel it, feed
-- its inputs by hand and empty its output.

local function in_box(box, pos, pad)
  pad = pad or 0
  return pos.x >= box[1] - pad and pos.y >= box[2] - pad and pos.x <= box[1] + box[3] + pad and pos.y <= box[2] + box[4] + pad
end

local function box_area(box) return { { box[1] - 1, box[2] - 1 }, { box[1] + box[3] + 1, box[2] + box[4] + 1 } } end

local function belt_at(s, pos)
  return s.find_entities_filtered({ type = { "transport-belt", "underground-belt", "splitter" }, position = pos, radius = 0.5, limit = 1 })[1]
end

local function on_belt(b, item)
  local n = 0
  for i = 1, 2 do n = n + b.get_transport_line(i).get_item_count(item) end
  return n
end

-- the next job the line needs, or "wait" while its ghosts are still being built, or nil when it's running
local function line_step(m, g, depth)
  local e, ln = m.entity, g.line
  local s = e.surface
  local area = box_area(ln.box)
  if s.count_entities_filtered({ area = area, type = { "entity-ghost", "tile-ghost" }, force = e.force, limit = 1 }) > 0 then
    return "wait"
  end
  for _, f in pairs(s.find_entities_filtered({ area = area, type = { "assembling-machine", "furnace", "inserter", "lab" }, force = e.force })) do
    if f.status == defines.entity_status.no_power then
      local job = power_to(m, f, depth)
      return job or "wait"
    end
  end
  for _, o in pairs(ln.outputs or {}) do
    local n = 0
    for _, b in pairs(s.find_entities_filtered({ type = { "transport-belt", "underground-belt" }, position = o.position, radius = 4 })) do
      n = n + on_belt(b, o.item)
    end
    if n >= 8 then return { kind = "collect", item = o.item, at = o.position } end
  end
  for _, i in pairs(ln.inputs or {}) do
    local b = belt_at(s, i.position)
    if b then
      for k, item in ipairs(i.items) do
        if prototypes.item[item] and on_belt(b, item) < 3 then
          -- (two inputs on one belt: a lane each, as bpgen's lines take them)
          local lane = #i.items == 2 and k or nil
          if have_count(m, item) > 0 then return { kind = "feed", item = item, at = i.position, count = 40, lane = lane } end
          local job = plan(m, item, 40, depth + 1)
          if job then return job end
        end
      end
    end
  end
end

-- puts items on a line's input belt (both lanes) until count is in or it runs out; waits while the belt is full
JOBS.feed = function(m, job)
  local e = m.entity
  local inv = e.get_main_inventory()
  local b = belt_at(e.surface, job.at)
  if not b then return true end
  if not go(m, job.at, math.max(e.reach_distance - 2, 2)) then return false end
  local have = inv.get_item_count(job.item)
  if have < job.count - job.n then have = have + take(m, job.item, job.count - job.n - have) end
  job.since = job.since or game.tick
  for lane = job.lane or 1, job.lane or 2 do
    local tl = b.get_transport_line(lane)
    while have > 0 and job.n < job.count and tl.can_insert_at_back() do
      tl.insert_at_back({ name = job.item, count = 1 })
      inv.remove({ name = job.item, count = 1 })
      have, job.n, job.since = have - 1, job.n + 1, game.tick
    end
  end
  m.fed = (m.fed or 0)
  if job.n >= job.count or have == 0 or game.tick - job.since > 1800 then
    m.fed = m.fed + job.n
    return true
  end
  return false
end

-- takes the product off the belts at a line's output and delivers it
JOBS.collect = function(m, job)
  local e = m.entity
  if not go(m, job.at, math.max(e.reach_distance - 3, 2)) then return false end
  local inv = e.get_main_inventory()
  for _, b in pairs(e.surface.find_entities_filtered({ type = { "transport-belt", "underground-belt" }, position = job.at, radius = 4 })) do
    for lane = 1, 2 do
      local tl = b.get_transport_line(lane)
      local n = tl.get_item_count(job.item)
      local got = n > 0 and inv.insert({ name = job.item, count = n }) or 0
      if got > 0 then
        tl.remove_item({ name = job.item, count = got })
        job.n = job.n + got
      end
    end
  end
  m.collected = (m.collected or 0) + job.n
  if job.n > 0 then table.insert(m.jobs, 2, { kind = "deliver" }) end
  return true
end

local function ask_line(m, g)
  local p = m.owner and game.get_player(m.owner)
  local bp = remote.interfaces["bpgen"]
  if not (bp and bp.plan_line) then
    g.line = false
    return
  end
  g.line = { state = "asked", tick = game.tick }
  remote.call("bpgen", "plan_line", p and p.index or m.owner, g.item, g.rate or 30, "ai-crew")
  say(m, "Asking bpgen for a " .. pretty(g.item) .. " line.", "quiet")
end

-- ----------------------------------------------------------------------------------------------------------- combat

local GUNS -- hand-held guns, longest range first
local self_craft

local AMMO_OF = {} -- gun -> the ammo items it fires (its ammo categories)

local function gun_ammo(g)
  if not AMMO_OF[g] then
    local ap = prototypes.item[g].attack_parameters
    local cats = {}
    for _, c in pairs(ap.ammo_categories or { ap.ammo_category }) do cats[c] = true end
    local list = {}
    for name, it in pairs(prototypes.get_item_filtered({ { filter = "type", type = "ammo" } })) do
      local ok, cat = pcall(function() return it.ammo_category.name end)
      if ok and cats[cat] and not it.hidden then list[#list + 1] = name end
    end
    table.sort(list)
    AMMO_OF[g] = list
  end
  return AMMO_OF[g]
end

-- queues hand-crafting `count` of item for itself (kept, not delivered), once; true when queued. What it lacks for it
-- becomes the crew's need, as for any craft
self_craft = function(m, item, count)
  for _, j in pairs(m.jobs) do if j.kind == "craft" and j.recipe == item then return false end end
  -- (already working for it, or for what it's made of: not again; and one try a minute, so a craft short of its
  -- ingredients isn't started, given up and started again every half second)
  for _, nd in pairs(needs(m.owner)) do if nd.item == item or nd.reason == pretty(item) then return false end end
  m.crafted_at = m.crafted_at or {}
  if game.tick - (m.crafted_at[item] or -3600) < 3600 then return false end
  m.crafted_at[item] = game.tick
  if not handcraft_recipe(m.entity.force, item) then
    return add_need(m.owner, item, count, "the crew's guns")
  end
  table.insert(m.jobs, 1, { kind = "craft", recipe = item, count = count, keep = true, n = 0, skip = {} })
  return true
end

local function gun_range(m)
  local g = m.entity.get_inventory(defines.inventory.character_guns)
  local best = 0
  for i = 1, g and #g or 0 do
    local ammo = m.entity.get_inventory(defines.inventory.character_ammo)
    if g[i].valid_for_read and ammo and ammo[i] and ammo[i].valid_for_read then
      local ap = g[i].prototype.attack_parameters
      best = math.max(best, ap and ap.range or 0)
    end
  end
  return best
end

-- armor if it has none; a gun its ammo exists for and that ammo in the slot beside it (taken from the owner, chests
-- near them, the network; made when there's none)
local function arm(m)
  local e = m.entity
  local guns, ammo, inv = e.get_inventory(defines.inventory.character_guns), e.get_inventory(defines.inventory.character_ammo),
    e.get_main_inventory()
  if not (guns and ammo) then return end
  if not GUNS then
    GUNS = {}
    for name, it in pairs(prototypes.get_item_filtered({ { filter = "type", type = "gun" } })) do
      if not it.hidden and it.attack_parameters then GUNS[#GUNS + 1] = name end
    end
    table.sort(GUNS, function(a, b) return prototypes.item[a].attack_parameters.range > prototypes.item[b].attack_parameters.range end)
  end
  local armor = e.get_inventory(defines.inventory.character_armor)
  if armor and armor.is_empty() then -- the best armor to hand (most resistance)
    local best, bs
    for name, it in pairs(prototypes.get_item_filtered({ { filter = "type", type = "armor" } })) do
      if not it.hidden and (inv.get_item_count(name) > 0 or available(m, name) > 0) then
        local score = 0
        for _, r in pairs(it.resistances or {}) do score = score + (r.percent or 0) * 100 + (r.decrease or 0) end
        if not bs or score > bs then best, bs = name, score end
      end
    end
    if best then
      if inv.get_item_count(best) == 0 then take(m, best, 1) end
      if armor.insert({ name = best, count = 1 }) > 0 then inv.remove({ name = best, count = 1 }) end
    end
  end
  -- ammo sitting beside no gun goes back to its pockets
  for i = 1, #ammo do
    if ammo[i].valid_for_read and not (guns[i] and guns[i].valid_for_read) then
      local n = inv.insert(ammo[i])
      if n >= ammo[i].count then ammo[i].clear() elseif n > 0 then ammo[i].count = ammo[i].count - n end
    end
  end
  local function has(item) return inv.get_item_count(item) > 0 or available(m, item) > 0 end
  local function makes(item) local r = e.force.recipes[item] return r and r.enabled end
  -- for gun g: 2 and the ammo when some is in stock, 1 when some can be made, 0 when neither
  local function ammo_for(g)
    local can = 0
    for _, a in ipairs(gun_ammo(g)) do
      if has(a) then return 2, a end
      if makes(a) then can = 1 end
    end
    return can
  end
  for i = 2, #guns do
    if guns[i].valid_for_read and not ammo[i].valid_for_read then
      if inv.insert(guns[i]) > 0 then guns[i].clear() end
    end
  end
  local cur = guns[1].valid_for_read and guns[1].name or nil
  if not (cur and (ammo[1].valid_for_read or ammo_for(cur) == 2)) then
    -- the gun to use: one to hand with ammo in stock, else one to hand whose ammo it can make, else one to make
    -- whose ammo is in stock, else one to make with ammo to make; longest range first among equals
    local pick, ps
    for _, g in ipairs(GUNS) do
      local a = ammo_for(g)
      local held = g == cur or has(g)
      local score = a == 0 and 0 or (held and (a == 2 and 6 or 5)) or (makes(g) and (a == 2 and 4 or 3)) or 0
      if score > 0 and (not ps or score > ps) then pick, ps = g, score end
    end
    if pick and pick ~= cur then
      if cur then
        if inv.insert(guns[1]) > 0 then guns[1].clear() end
      end
      if has(pick) then
        if inv.get_item_count(pick) == 0 then take(m, pick, 1) end
        if inv.get_item_count(pick) > 0 and guns[1].set_stack({ name = pick, count = 1 }) then inv.remove({ name = pick, count = 1 }) end
      else
        if self_craft(m, pick, 1) then say(m, "No gun to hand. I'll make myself a " .. pretty(pick) .. ".") end
        return
      end
    end
  end
  local gun = guns[1].valid_for_read and guns[1].name
  if not gun then return end
  if ammo[1].valid_for_read and ammo[1].count >= 10 then return end
  local state, a = ammo_for(gun)
  if state == 2 then
    local stack = prototypes.item[a].stack_size
    if inv.get_item_count(a) < stack then take(m, a, stack - inv.get_item_count(a)) end
    local cnt = inv.get_item_count(a)
    if not ammo[1].valid_for_read then
      if cnt > 0 and ammo[1].set_stack({ name = a, count = math.min(cnt, stack) }) then inv.remove({ name = a, count = math.min(cnt, stack) }) end
    elseif ammo[1].name == a then
      local add = math.min(cnt, stack - ammo[1].count)
      if add > 0 then
        ammo[1].count = ammo[1].count + add
        inv.remove({ name = a, count = add })
      end
    end
  elseif state == 1 and not ammo[1].valid_for_read then
    for _, am in ipairs(gun_ammo(gun)) do
      if makes(am) then
        if self_craft(m, am, 20) then say(m, "Out of ammo. Making " .. pretty(am) .. ".") end
        break
      end
    end
  end
end

-- every half second: shoot what's in range, fall back to the owner when hurt, come back when healed
local function fight(m)
  local e = m.entity
  local hp = e.health / e.max_health
  -- a fish heals 80, as a player's would: eaten whenever that much is missing (in a fight or after it), sooner when low
  if (e.max_health - e.health >= 80 or hp < 0.5) and prototypes.item["raw-fish"] then
    local inv = e.get_main_inventory()
    if inv.get_item_count("raw-fish") == 0 and available(m, "raw-fish") > 0 then take(m, "raw-fish", 5) end
    if inv.get_item_count("raw-fish") > 0 and game.tick >= (m.fish_at or 0) then
      inv.remove({ name = "raw-fish", count = 1 })
      e.health = e.health + 80
      m.fish_at = game.tick + 30
      hp = e.health / e.max_health
    end
  end
  if m.retreat then
    if hp > 0.8 then m.retreat = nil end
  elseif hp < 0.5 then
    m.retreat, m.target = true, nil
    e.shooting_state = { state = defines.shooting.not_shooting, position = e.position }
    stop_mining(m)
    go(m, anchor(m), 4)
    say(m, line(m, "hurt"))
    return
  end
  if m.defend == false and not (m.jobs[1] and m.jobs[1].kind == "attack") then m.target = nil return end
  local range = gun_range(m)
  if range == 0 then
    arm(m)
    range = gun_range(m)
  end
  -- the target: of the biters in range the most hurt (finish it off), else the nearest of anything
  local enemy
  if range > 0 and not m.retreat then
    local low
    for _, u in pairs(e.surface.find_enemy_units(e.position, range, e.force)) do
      local r = u.health / u.max_health
      if not low or r < low then enemy, low = u, r end
    end
    enemy = enemy or e.surface.find_nearest_enemy({ position = e.position, max_distance = range, force = e.force })
  end
  -- a biter (a melee one) right on it: step back and keep shooting
  if enemy and enemy.type == "unit" and not m.move then
    local close = e.surface.find_enemy_units(e.position, 3.5, e.force)[1]
    local ap = close and close.prototype.attack_parameters
    if close and ap and ap.range < 3 then
      local dx, dy = e.position.x - close.position.x, e.position.y - close.position.y
      local d = math.max(math.sqrt(dx * dx + dy * dy), 0.1)
      local to = e.surface.find_non_colliding_position(CREW, { x = e.position.x + dx / d * 6, y = e.position.y + dy / d * 6 }, 3, 0.5)
      if to then go(m, to, 1) end
    end
  end
  if enemy and not m.target then
    if not m.said_fight or game.tick - m.said_fight > 1800 then
      m.said_fight = game.tick
      say(m, line(m, "contact", { item = pretty(enemy.name) }))
    end
  end
  m.target = enemy
  if enemy and enemy.valid then
    local ammo = e.get_inventory(defines.inventory.character_ammo)
    if ammo and ammo.get_item_count() < 5 then arm(m) end
  end
end

-- Your buildings under attack: every armed fighter of the crew within 160 tiles drops what it's doing and rushes
-- over (flying, with jetpacks), fights there until it has been quiet for 5 seconds, then goes back to its work
local function alarm(surface, force, ent)
  local pos = ent.position
  for _, m in pairs(crew()) do
    local e = m.entity
    if e.valid and e.force == force and e.surface == surface and m.defend ~= false and not m.retreat
      and dist2(e.position, pos) < 160 * 160 and not (m.jobs[1] and (m.jobs[1].kind == "defend" or m.jobs[1].kind == "attack")) then
      if gun_range(m) == 0 then arm(m) end
      if gun_range(m) > 0 then
        stop_mining(m)
        table.insert(m.jobs, 1, { kind = "defend", at = { x = pos.x, y = pos.y }, n = 0, skip = {} })
        m.wait_until = nil
        if game.tick - (storage.alarm_said or -3600) > 1800 then
          storage.alarm_said = game.tick
          say(m, line(m, "alarm", { item = pretty(ent.name) }))
          remember(m.owner, "biters attacked the " .. pretty(ent.name) .. "; the crew went to fight them")
        end
      end
    end
  end
end

JOBS.defend = function(m, job)
  local e = m.entity
  if m.retreat then return false end
  if gun_range(m) == 0 then return true end
  local enemy = e.surface.find_nearest_enemy({ position = job.at, max_distance = 32, force = e.force })
  local d2 = dist2(e.position, enemy and enemy.position or job.at)
  if enemy then
    job.quiet = nil
    if d2 > 24 * 24 and fly(m, enemy.position) then return false end -- (rushing there)
    go(m, enemy.position, math.max(gun_range(m) - 4, 4)) -- (in range of it; fight() does the shooting)
    return false
  end
  job.quiet = job.quiet or game.tick
  if game.tick - job.quiet > 300 then return true end
  if d2 > 24 * 24 and fly(m, job.at) then return false end
  go(m, job.at, 8)
  return false
end

-- raw fish from the water, caught by hand (5 a fish) when the crew have none left to heal with
JOBS.fish = function(m, job)
  local e = m.entity
  job.t0 = job.t0 or game.tick
  local have = e.get_main_inventory().get_item_count("raw-fish")
  if have >= job.count or game.tick - job.t0 > 3600 then -- (enough, or a minute at it: what it has will do)
    if have < job.count then m.fish_wait = game.tick + 18000 end
    say(m, "Caught " .. have .. " fish.", "quiet")
    return true
  end
  local f = job.target
  if not (f and f.valid) then
    f = nil
    for _, r in ipairs({ 48, 120, 250 }) do
      local bd
      for _, c in pairs(e.surface.find_entities_filtered({ type = "fish", position = e.position, radius = r, limit = 60 })) do
        if not job.skip[key_of(c)] then
          local d = dist2(e.position, c.position)
          if not bd or d < bd then f, bd = c, d end
        end
      end
      if f then break end
    end
    if not f then
      m.fish_wait = game.tick + 36000
      say(m, "No fish anywhere near. We'll have to manage without.")
      return true
    end
    job.target, job.target_at = f, game.tick
  end
  -- out in the water: as close as the shore gets them is close enough when it's in reach; 15 s without: another fish
  local reach = e.reach_distance
  local near = dist2(e.position, f.position) <= reach * reach
  if not near then
    if game.tick - job.target_at > 900 then
      job.skip[key_of(f)], job.target = true, nil
      stop_walk(m)
    else
      go(m, f.position, math.max(reach - 2, 2))
    end
    return false
  end
  if not e.mine_entity(f, false) then job.skip[key_of(f)] = true end
  m.wait_until = game.tick + 30
  job.target = nil
  return false
end

-- destroys enemy spawners and worms near the owner, nearest first; the shooting is fight()'s
JOBS.attack = function(m, job)
  local e = m.entity
  if m.retreat then return false end
  if gun_range(m) == 0 then
    arm(m)
    if gun_range(m) == 0 then say(m, "I need a gun and ammo for that.") return true end
  end
  local t = job.target
  if not (t and t.valid) then
    if job.target then job.n = job.n + 1 end
    t = nil
    local bd
    for _, c in pairs(e.surface.find_entities_filtered({ type = { "unit-spawner", "turret" }, position = job.center or anchor(m), radius = job.radius or 96 })) do
      if e.force.is_enemy(c.force) then
        local d = dist2(e.position, c.position)
        if not bd or d < bd then t, bd = c, d end
      end
    end
    job.target = t
    if not t then
      say(m, job.n > 0 and ("Cleared " .. job.n .. " nest" .. (job.n > 1 and "s" or "") .. ".") or "No nests around here.")
      if job.n > 0 then remember(m.owner, m.name .. " cleared " .. job.n .. " nest" .. (job.n > 1 and "s" or "")) end
      return true
    end
  end
  go(m, t.position, math.max(gun_range(m) - 3, 4))
  return false
end

-- with nothing else to do, one step towards what the crew needs, else the owner's goal
local function goal_step(m)
  if game.tick < (m.goal_wait or 0) then return end
  local key = m.owner or 0
  local list = needs(m.owner)
  local g, is_need = list[1], true
  if not g then g, is_need = goals()[key], false end
  if not g then return end
  local have = goal_have(m.owner, g.item)
  g.count = g.count or (have + g.more)
  if have >= g.count then
    if not is_need then
      goals()[key] = nil
      ada("Goal reached: " .. g.count .. " " .. pretty(g.item) .. ". Well done, pioneer.")
      react(m.owner, "goal", "goal reached: " .. g.count .. " " .. pretty(g.item), { item = pretty(g.item) })
      return
    end
    table.remove(list, 1)
    for _, o in pairs(crew()) do if o.owner == m.owner then o.auto_wait = nil end end -- the blueprint can go on
    say(m, "Got the " .. pretty(g.item) .. (g.reason and (" for " .. g.reason) or "") .. ".", "quiet")
    if g.after then
      g.after.n, g.after.skip = 0, {}
      m.jobs[#m.jobs + 1] = g.after
      return true
    end
    return
  end
  if not is_need and g.use_line then
    if g.line == nil then return ask_line(m, g) end
    if g.line and g.line.state == "asked" then
      if game.tick - g.line.tick > 18000 then g.line = false else return end -- (bpgen may measure inserters first)
    end
    if g.line and g.line.state == "placed" then
      local lj = line_step(m, g, 0)
      if lj == "wait" then
        g.step = "building the line"
        m.goal_wait = game.tick + 300
        return
      end
      if lj then
        g.why, g.step = nil, m.name .. ": " .. (DOING_WORD[lj.kind] or lj.kind) .. " " .. pretty(lj.item or lj.recipe or "") .. " (line)"
        lj.n, lj.skip, lj.goal = 0, {}, true
        m.jobs[#m.jobs + 1] = lj
        return true
      end
    end
  end
  local job, why = plan(m, g.item, g.count - have)
  if not job then
    if is_need then
      table.remove(list, 1)
      say(m, why)
      return
    end
    if g.why ~= why then say(m, why) end
    g.why, g.step = why, "stuck"
    m.goal_wait = game.tick + 600
    return
  end
  g.why = nil
  g.step = m.name .. ": " .. (DOING_WORD[job.kind] or job.kind) .. " " .. pretty(job.item or job.recipe)
  job.n, job.skip, job.goal = 0, {}, true
  m.jobs[#m.jobs + 1] = job
  return true
end

-- --------------------------------------------------------------------------------------------------------- roaming
-- Roam: instead of following, each one wanders the area round the player (or home) on its own, stops a while to look
-- around, and deals with what it finds as a player would: goes after a nest when it's armed and may fight, runs poles
-- to a machine standing dark (pole by pole, while poles are all it takes) and mentions machines starved of inputs or
-- backed up. Each thing once; those remarks at most every 3 minutes a member.

local S = defines.entity_status
local REMARKS = {}
for name, kind in pairs({ item_ingredient_shortage = "starved", no_ingredients = "starved", fluid_ingredient_shortage = "starved",
  full_output = "backed", waiting_for_space_in_destination = "backed" }) do
  if S[name] then REMARKS[S[name]] = kind end
end

-- one look round where it stands; true when it found something to do or say
local function notice(m)
  local e = m.entity
  local s = e.surface
  m.noticed = m.noticed or {}
  if table_size(m.noticed) > 300 then m.noticed = {} end
  local function new(x)
    local k = key_of(x)
    if m.noticed[k] then return false end
    m.noticed[k] = true
    return true
  end
  for _, n in pairs(s.find_entities_filtered({ type = { "unit-spawner", "turret" }, position = e.position, radius = 32 })) do
    if e.force.is_enemy(n.force) and new(n) then
      local armed = m.defend ~= false and gun_range(m) > 0
      say(m, line(m, armed and "nest" or "nest_unarmed", { item = pretty(n.name) }))
      remember(m.owner, m.name .. " found " .. a_an(n.name) .. (armed and " and went after it" or ", but had no gun"))
      if armed then m.jobs[#m.jobs + 1] = { kind = "attack", n = 0, skip = {}, center = n.position, radius = 24 } end
      return true
    end
  end
  local remark = game.tick >= (m.remark_at or 0)
  for _, f in pairs(s.find_entities_filtered({ type = { "assembling-machine", "furnace", "lab", "mining-drill" }, force = e.force,
    position = e.position, radius = 20 })) do
    local st = f.status
    local kind = st == S.no_power and "dark" or REMARKS[st]
    if kind and kept_out(s, f.position) then kind = nil end
    if kind and (remark or kind == "dark") and new(f) then
      local job = kind == "dark" and m.auto ~= false and power_to(m, f, 0)
      if job and job.kind == "place" then
        m.powering, m.power_steps = f, 1
        job.n, job.skip = 0, {}
        m.jobs[#m.jobs + 1] = job
      elseif kind == "dark" then
        if not remark then return false end
        kind = "dark_note"
      end
      say(m, line(m, kind, { item = pretty(f.name) }))
      remember(m.owner, m.name .. " found " .. a_an(f.name) .. ({ dark = " with no power and ran poles to it",
        dark_note = " with no power", starved = " short of inputs", backed = " with its output backed up" })[kind])
      if kind ~= "dark" then m.remark_at = game.tick + 10800 end
      return true
    end
  end
end

local function roam(m)
  local e = m.entity
  local c = owner_char(m)
  local center = c and c.position or m.home
  local f = m.powering -- the next pole to a dark machine, while that's all it takes
  if f then
    m.powering = nil
    if f.valid and f.status == S.no_power and m.power_steps < 12 then
      local job = power_to(m, f, 0)
      if job and job.kind == "place" then
        m.powering, m.power_steps = f, m.power_steps + 1
        job.n, job.skip = 0, {}
        m.jobs[#m.jobs + 1] = job
        return
      end
    end
  end
  if dist2(e.position, center) > (ROAM + 16) ^ 2 then -- (the player went off: catch up)
    m.roam_walk = nil
    go(m, spot(m, center), 8)
    return
  end
  if m.roam_walk then -- got there: a look round, then a while here
    m.roam_walk = nil
    m.roam_at = game.tick + math.random(300, 900)
    if notice(m) then return end
  end
  if game.tick < (m.roam_at or 0) then return end
  local a, r = math.random() * 2 * math.pi, 6 + math.random() * (ROAM - 6)
  local to = e.surface.find_non_colliding_position(CREW, { x = center.x + math.cos(a) * r, y = center.y + math.sin(a) * r }, 8, 0.5)
  if not to or kept_out(e.surface, to) then m.roam_at = game.tick + 120 return end
  m.roam_walk = true
  go(m, to, 1.5)
end

-- with nothing queued: like a construction bot (marks, then ghosts near the owner), then the goal, then follow
local function idle(m)
  if game.tick >= (m.next_scan or 0) then
    m.next_scan = game.tick + 120
    if m.auto ~= false and game.tick >= (m.auto_wait or 0) then
      local e = m.entity
      local area = { position = anchor(m), radius = RADIUS, limit = 1, to_be_deconstructed = true }
      local kind
      if e.surface.count_entities_filtered(area) > 0 then kind = "deconstruct" end
      area.to_be_deconstructed, area.to_be_upgraded, area.force = nil, true, e.force
      if not kind and e.surface.count_entities_filtered(area) > 0 then kind = "upgrade" end
      area.to_be_upgraded, area.type = nil, { "entity-ghost", "tile-ghost" }
      if not kind and e.surface.count_entities_filtered(area) > 0 then kind = "build" end
      if kind then
        m.jobs[1] = { kind = kind, auto = true, n = 0, skip = {} }
        return
      end
    end
    if game.tick >= (m.tend_at or 0) then
      m.tend_at = game.tick + 600
      if #low_burners(m, 1) > 0 then
        if fuel_available(m) then
          m.jobs[1] = { kind = "tend", auto = true, n = 0, skip = {} }
          return
        end
        -- burners running dry and no fuel anywhere: go and get some (coal, else wood), then fuel them
        local item = game.tick >= (m.fuel_hunt or 0) and (nearest_source(m, { item = "coal", skip = {} }) and "coal" or "wood")
        m.fuel_hunt = item and game.tick + 18000 or m.fuel_hunt -- (one try every 5 minutes)
        if item and add_need(m.owner, item, 20, "the burners", { kind = "tend", auto = true }) then
          say(m, "The burners are running dry and we're out of fuel. Getting some " .. pretty(item) .. ".")
        end
      end
    end
    -- no fish to heal with: go fishing (fighters only, every 30 s at most)
    if m.defend ~= false and prototypes.item["raw-fish"] and game.tick >= (m.fish_wait or 0) then
      m.fish_wait = game.tick + 1800
      local e = m.entity
      if e.get_main_inventory().get_item_count("raw-fish") + available(m, "raw-fish") < 5
        and e.surface.count_entities_filtered({ type = "fish", position = e.position, radius = 250, limit = 1 }) > 0 then
        say(m, line(m, "fishing"))
        m.jobs[1] = { kind = "fish", count = 20, auto = true, n = 0, skip = {} }
        return
      end
    end
    if goal_step(m) then return end
  end
  if not m.move and game.tick >= (m.glance_at or 0) then -- standing about: look round now and then, mostly at you
    m.glance_at = game.tick + math.random(240, 600)
    local c, p = owner_char(m), m.entity.position
    face(m, c and math.random() < 0.6 and c.position or { x = p.x + math.random(-5, 5), y = p.y + math.random(-5, 5) })
  end
  if m.roam then return roam(m) end
  if not m.follow then return end
  local c = owner_char(m)
  if c and dist2(m.entity.position, spot(m, c.position)) > 16 and dist2(m.entity.position, c.position) > 25 then
    go(m, spot(m, c.position), 1.5)
  end
end

local function think(m)
  if game.tick < (m.wait_until or 0) then return end -- (a moment's pause: reacting, putting something down)
  local v = m.visits and m.visits[1] -- a place it took something from: over there first, a moment at it
  if v then
    if not v.valid or go(m, v.position, math.max(m.entity.reach_distance - 2, 2)) then
      table.remove(m.visits, 1)
      if v.valid then
        face(m, v.position)
        m.wait_until = game.tick + math.random(10, 20)
      end
    end
    return
  end
  local job = m.jobs[1]
  if not job then return idle(m) end
  if job.kind ~= "mine" and m.mining then stop_mining(m) end
  local ok, done = pcall(JOBS[job.kind], m, job)
  if not ok then
    log("[ai-crew] " .. m.name .. " " .. job.kind .. ": " .. tostring(done))
    done = true
  end
  if done then
    for i, j in ipairs(m.jobs) do if j == job then table.remove(m.jobs, i) break end end
    if job.goal and (job.n or 0) == 0 then m.goal_wait = game.tick + 600 end -- a goal step that got nowhere: wait
  end
end

-- ---------------------------------------------------------------------------------------------------------- orders

local function members_of(owner)
  local out = {}
  for _, m in pairs(crew()) do if m.owner == owner then out[#out + 1] = m end end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

local function find_member(name, owner)
  if type(name) ~= "string" then return end
  for _, m in pairs(members_of(owner)) do if m.name:lower() == name:lower() then return m end end
end

-- a crew member on the map (chart view): a coloured dot with its name, following it
map_marker = function(e, name, color)
  rendering.draw_circle({ color = color, radius = 1.6, filled = true, target = e, surface = e.surface, render_mode = "chart" })
  rendering.draw_circle({ color = { 0, 0, 0 }, radius = 1.6, width = 2, filled = false, target = e, surface = e.surface,
    render_mode = "chart" })
  rendering.draw_text({ text = name, target = { entity = e, offset = { 0, -3 } }, surface = e.surface, color = color,
    scale = 1.2, alignment = "center", vertical_alignment = "bottom", render_mode = "chart" })
end

local function hire(name, surface, position, force, owner)
  local taken = {}
  for n in pairs(crew()) do taken[n:lower()] = true end
  if not name then
    for _, n in ipairs(NAMES) do if not taken[n:lower()] then name = n break end end
    name = name or ("Crew" .. (table_size(crew()) + 1))
  end
  if taken[name:lower()] then return nil, name .. " is already on the crew." end
  local at = surface.find_non_colliding_position(CREW, position, 10, 0.5) or position
  local e = surface.create_entity({ name = CREW, position = at, force = force })
  if not e then return nil, "No room to spawn a crew member." end
  local i = table_size(crew())
  local color = COLORS[i % #COLORS + 1]
  e.color = { r = color[1], g = color[2], b = color[3] }
  rendering.draw_text({ text = name, surface = surface, target = { entity = e, offset = { 0, -2.3 } }, color = color,
    scale = 0.9, alignment = "center" })
  map_marker(e, name, color)
  local m = { name = name, entity = e, owner = owner, home = { x = at.x, y = at.y }, jobs = {}, color = color,
    voice = i, follow = true, phase = i * 3, mapped = true }
  crew()[name] = m
  return m
end

local function job_for(m, kind, item, count, extra)
  if kind == "craft" then
    local r = resolve_item(item)
    if not r then return end
    return { kind = "craft", recipe = r, count = math.min(math.max(count or 10, 1), 200) }
  elseif kind == "mine" or kind == "get" or kind == "fetch" then
    local it = resolve_item(item)
    if not it then return end
    count = math.min(math.max(count or 50, 1), 1000)
    if kind == "get" then
      if available(m, it, nil, true) >= count then kind = "fetch"
      elseif nearest_source(m, { item = it, skip = {} }) then kind = "mine"
      elseif handcraft_recipe(m.entity.force, it) then return { kind = "craft", recipe = it, count = math.min(count, 200) }
      elseif plan(m, it, count) then return { kind = "need", item = it, count = count }
      else kind = "fetch" end
    end
    return { kind = kind, item = it, count = count }
  elseif kind == "goal" then
    local use_line = extra and extra.line
    if type(item) == "string" and item:find("%f[%a]line%s*$") then item, use_line = item:gsub("%s*line%s*$", ""), true end
    local it = resolve_item(item)
    if not it then return end
    return { kind = "goal", item = it, count = math.min(math.max(count or 100, 1), 100000), use_line = use_line and true or nil,
      rate = extra and tonumber(extra.rate) }
  elseif kind == "build" or kind == "deconstruct" or kind == "deliver" or kind == "upgrade" then
    return { kind = kind }
  elseif kind == "attack" then
    return { kind = "attack" }
  elseif kind == "follow" or kind == "stay" or kind == "stop" or kind == "roam" then
    return { kind = kind }
  elseif kind == "remember" then
    local text = extra and type(extra.text) == "string" and extra.text or type(item) == "string" and item
    return text and text ~= "" and { kind = "remember", text = text:sub(1, 200), keep_out = extra and extra.keep_out and true } or nil
  end
end

local VERBS = { build = "build", construct = "build", clear = "deconstruct", deconstruct = "deconstruct", upgrade = "upgrade",
  demolish = "deconstruct", remove = "deconstruct", mine = "mine", gather = "get", collect = "get", get = "get",
  fetch = "get", bring = "get", grab = "get", craft = "craft", make = "craft", follow = "follow", come = "follow",
  stay = "stay", wait = "stay", stop = "stop", roam = "roam", wander = "roam", explore = "roam", patrol = "roam", goal = "goal", aim = "goal", attack = "attack", fight = "attack",
  kill = "attack", halt = "stop", cancel = "stop", deliver = "deliver", unload = "deliver" }

-- a plain command ("get 50 iron ore", "build") -> kind, item words, count; nil for anything else
local function parse(text)
  local words = {}
  for w in text:lower():gsub("[%.,!%?]", " "):gmatch("%S+") do words[#words + 1] = w end
  while words[1] == "please" or words[1] == "can" or words[1] == "you" do table.remove(words, 1) end
  local kind = VERBS[words[1] or ""]
  if not kind then return end
  table.remove(words, 1)
  if kind == "build" or kind == "deconstruct" or kind == "stop" or kind == "stay" or kind == "deliver" or kind == "attack" or kind == "upgrade" then
    return #words <= 2 and kind or nil -- "build" / "clear it" / "stop now", nothing longer
  end
  if kind == "follow" or kind == "roam" then return (#words <= 2) and kind or nil end
  local count
  for i, w in ipairs(words) do
    if tonumber(w) then count = tonumber(w) table.remove(words, i) break end
  end
  if words[1] == "me" then table.remove(words, 1) end
  if #words == 0 or #words > 5 then return end
  return kind, table.concat(words, " "), count
end

local function add_job(m, job)
  if job.kind == "stop" then
    for _, j in pairs(m.jobs) do if j.target and j.target.valid and j.target.unit_number then claims()[j.target.unit_number] = nil end end
    m.jobs, m.visits = {}, nil
    stop_walk(m)
    stop_mining(m)
  elseif job.kind == "follow" then
    m.follow, m.roam = true, nil
  elseif job.kind == "roam" then
    m.follow, m.roam, m.roam_at = false, true, nil
    remember(m.owner, m.name .. " went roaming")
  elseif job.kind == "remember" then
    add_note(m.owner, m, job.text, job.keep_out)
  elseif job.kind == "need" then
    add_need(m.owner, job.item, job.count, "you")
  elseif job.kind == "goal" then
    goals()[m.owner or 0] = { item = job.item, count = job.count, use_line = job.use_line, rate = job.rate }
    m.goal_wait = nil
  elseif job.kind == "stay" then
    m.follow, m.roam = false, nil
    stop_walk(m)
  else
    job.n, job.skip = 0, {}
    -- an order comes before what they took on themselves (auto work, goal steps, fishing): after earlier orders
    local i = 1
    while m.jobs[i] and not (m.jobs[i].auto or m.jobs[i].goal) do i = i + 1 end
    table.insert(m.jobs, i, job)
    if i == 1 and m.jobs[2] then -- (dropping what it was on: stop walking there)
      stop_walk(m)
      stop_mining(m)
    end
  end
end

local function busiest_last(list)
  table.sort(list, function(a, b) return #a.jobs < #b.jobs end)
  return list[1]
end

local function context(player, members)
  local ctx = { crew = {} }
  for _, m in pairs(members) do
    local inv = {}
    for _, it in pairs(m.entity.get_main_inventory().get_contents()) do inv[it.name] = (inv[it.name] or 0) + it.count end
    ctx.crew[#ctx.crew + 1] = { name = m.name, manner = trait(m), queued = #m.jobs, carrying = inv,
      doing = m.jobs[1] and m.jobs[1].kind or (m.roam and "roaming" or m.follow and "following" or "waiting") }
  end
  local recent = {}
  for _, ev in ipairs(storage.events and player and storage.events[player.index] or {}) do
    recent[#recent + 1] = math.floor((game.tick - ev.tick) / 3600) .. " min ago: " .. ev.text
  end
  ctx.recent = recent
  local offer = storage.proposals and player and storage.proposals[player.index]
  ctx.open_offer = offer and ("the crew offered to " .. (offer.use_line and "build a production line for " or ("make " .. offer.count .. " "))
    .. offer.item .. "; if the player agrees, give a goal job for it") or nil
  local c0 = player and player.character
  ctx.notes = {}
  for _, n in ipairs(player and notes(player.index) or {}) do
    ctx.notes[#ctx.notes + 1] = (n.keep_out and "keep out of here: " or "") .. n.text .. string.format(" (at %d, %d%s)", n.pos.x, n.pos.y,
      c0 and string.format("; %d tiles from the player", math.sqrt(dist2(n.pos, c0.position))) or "")
  end
  local c = player and player.character
  if c then
    local inv, n = {}, 0
    for _, it in pairs(c.get_main_inventory().get_contents()) do
      if n < 30 then inv[it.name] = (inv[it.name] or 0) + it.count n = n + 1 end
    end
    ctx.player_inventory = inv
    local s = c.surface
    ctx.ghosts_nearby = s.count_entities_filtered({ type = { "entity-ghost", "tile-ghost" }, force = c.force, position = c.position, radius = RADIUS })
    ctx.marked_for_deconstruction = s.count_entities_filtered({ position = c.position, radius = RADIUS, to_be_deconstructed = true })
    local res = {}
    for _, r in pairs(s.find_entities_filtered({ type = "resource", position = c.position, radius = 64, limit = 400 })) do res[r.name] = true end
    ctx.resources_nearby = {}
    for name in pairs(res) do ctx.resources_nearby[#ctx.resources_nearby + 1] = name end
    local r = c.force.current_research
    ctx.researching = r and r.name
  end
  return ctx
end

local function help(player)
  local msg = "Try: get 50 iron ore, craft 10 gears, mine 20 stone, build, clear, deliver, come, stay, stop."
  if player then player.print(msg) else log(msg) end
end

local function tell(player, text) if player then player.print(text) else log("[ai-crew] " .. text) end end

-- a note where the player stands (home without one); keep: a keep-out zone, drawn on their map
local function add_note(owner, m, text, keep)
  local player = owner and game.get_player(owner)
  local c = player and player.character
  local pos, surface = c and c.position or m.home, c and c.surface or m.entity.surface
  local list = notes(owner)
  local n = { text = text, pos = { x = math.floor(pos.x), y = math.floor(pos.y) }, surface = surface.name, keep_out = keep or nil }
  if keep then
    n.mark = rendering.draw_circle({ color = { 1, 0.3, 0.2, 0.6 }, radius = ZONE, width = 3, filled = false, target = pos,
      surface = surface, render_mode = "chart", players = player and { player } or nil })
  end
  list[#list + 1] = n
  if #list > 30 then
    local old = table.remove(list, 1)
    if old.mark and old.mark.valid then old.mark.destroy() end
  end
end

local KEEP_OUT = { "^keep out", "^stay out", "^don'?t touch", "^hands off", "^leave .*alone" }
local function keep_out_cmd(cmd)
  for _, p in ipairs(KEEP_OUT) do if cmd:find(p) then return true end end
end

-- "remember <anything>", "keep out" (and the like), "forget" (all, a number, here), "notes"
local function note_order(owner, player, m, cmd, rest)
  local list = notes(owner)
  local verb = cmd:match("^(%S+)")
  if verb == "notes" then
    if #list == 0 then return tell(player, "No notes. Try \"remember the north is for iron\", \"keep out\" (here), \"forget\".") end
    for i, n in ipairs(list) do tell(player, string.format("%d. %s%s (at %d, %d)", i, n.keep_out and "[keep out] " or "", n.text, n.pos.x, n.pos.y)) end
    return
  end
  if verb == "forget" then
    local what = cmd:match("^forget%s*(.-)%s*$")
    local c = player and player.character
    local pos = c and c.position or m.home
    local before = #list
    for i = #list, 1, -1 do
      local n = list[i]
      if what == "" or what == "all" or what == "everything" or tonumber(what) == i
        or (what == "here" or what == "this") and dist2(n.pos, pos) <= ZONE * ZONE then
        if n.mark and n.mark.valid then n.mark.destroy() end
        table.remove(list, i)
      end
    end
    return say(m, before > #list and line(m, "noted") or "Nothing to forget.", "talk")
  end
  local keep = keep_out_cmd(cmd)
  local text = keep and rest or rest:gsub("^%S+%s*", "")
  if text == "" then return end
  add_note(owner, m, text, keep)
  say(m, line(m, keep and "keep_out" or "noted"), "talk")
end

-- answers to the crew's offer (proposals, below)
local YES = { yes = true, yeah = true, yep = true, y = true, sure = true, ok = true, okay = true, ["do it"] = true, please = true,
  ["go ahead"] = true, ["go for it"] = true, ["yes please"] = true, ["sounds good"] = true }
local NO = { no = true, nope = true, nah = true, n = true, ["no thanks"] = true, ["not now"] = true, later = true }
local function answer_of(cmd) return (cmd:lower():gsub("[%.!,]", ""):gsub("^%s+", ""):gsub("%s+$", "")) end

-- one order: "crew <what>" for everyone, "<Name> <what>" for one member
local function order(owner, text)
  local player = owner and game.get_player(owner)
  local who, rest = text:match("^(%S+)%s*(.*)$")
  if not who then return end
  local lw, cmd = who:lower(), rest:lower()
  local all = lw == "crew" or lw == "all" or lw == "everyone"
  local members
  if all then members = members_of(owner) else
    local m = find_member(who, owner)
    if not m then return tell(player, "No crew member called " .. who .. ".") end
    members = { m }
  end
  local offer = storage.proposals and storage.proposals[owner or 0]
  local ans = answer_of(cmd)
  if offer and #members > 0 and (YES[ans] or NO[ans]) then
    storage.proposals[owner or 0] = nil
    local m = members[1]
    if YES[ans] then
      goals()[owner or 0] = { item = offer.item, count = offer.count, use_line = offer.use_line, rate = offer.rate }
      for _, o in pairs(members_of(owner)) do o.goal_wait = nil end
      remember(owner, "the player agreed: goal " .. offer.count .. " " .. pretty(offer.item) .. (offer.use_line and " with a line" or ""))
      return say(m, line(m, "ack"), "talk")
    end
    storage.declined = storage.declined or {}
    storage.declined[owner or 0] = storage.declined[owner or 0] or {}
    storage.declined[owner or 0][offer.item] = game.tick
    remember(owner, "the player said no to doing something about " .. pretty(offer.item))
    return say(m, line(m, "declined"), "talk")
  end
  -- management
  local verb, arg = cmd:match("^(%S+)%s*(%S*)")
  if all and (verb == "hire" or verb == "recruit") then
    if #members >= MAX_CREW then return tell(player, "The crew is full (" .. MAX_CREW .. ").") end
    local c = player and player.character
    if not c then return tell(player, "Stand somewhere first: crew members spawn next to your character.") end
    local name = rest:match("^%S+%s+(%S+)")
    local m, err = hire(name and (name:sub(1, 1):upper() .. name:sub(2)), c.surface, c.position, c.force, owner)
    if not m then return tell(player, err) end
    ada("New crew member registered: " .. m.name .. ".")
    remember(owner, m.name .. " joined the crew")
    return say(m, line(m, "hello"), "talk")
  elseif all and (verb == "fire" or verb == "dismiss") then
    local m = find_member(arg, owner)
    if not m then return tell(player, "No crew member called " .. arg .. ".") end
    say(m, line(m, "bye"), "talk")
    unload(m)
    if m.entity.valid then m.entity.destroy() end
    crew()[m.name] = nil
    return
  elseif all and (verb == "list" or verb == "status") or verb == "status" then
    if #members == 0 then return tell(player, "No crew yet: press Hire in the crew window.") end
    for _, m in pairs(members) do
      tell(player, m.name .. ": " .. (m.jobs[1] and m.jobs[1].kind or (m.roam and "roaming" or m.follow and "following" or "waiting")) ..
        (#m.jobs > 1 and (" (+" .. (#m.jobs - 1) .. " queued)") or ""))
    end
    return
  elseif verb == "auto" then
    for _, m in pairs(members) do m.auto = arg ~= "off" end
    return tell(player, (arg ~= "off" and "Auto build and clear on" or "Auto build and clear off: only on orders") ..
      " for " .. (all and "the crew" or members[1].name) .. ".")
  elseif verb == "help" or cmd == "" then
    return help(player)
  elseif #members > 0 and (verb == "remember" or verb == "note" or verb == "notes" or verb == "forget" or keep_out_cmd(cmd)) then
    return note_order(owner, player, members[1], cmd, rest)
  end
  if #members == 0 then return tell(player, "No crew yet: press Hire in the crew window.") end
  -- plain commands run without the LLM
  local kind, item, count = parse(rest)
  if kind then
    local targets = members
    if not (kind == "build" or kind == "deconstruct" or kind == "stop" or kind == "follow" or kind == "roam" or kind == "stay" or kind == "deliver" or kind == "attack" or kind == "upgrade") then
      targets = { busiest_last(members) }
    end
    for i, m in ipairs(targets) do
      local job = job_for(m, kind, item, count)
      if not job then return tell(player, "I don't know an item called \"" .. tostring(item) .. "\".") end
      add_job(m, job)
      m.wait_until = game.tick + math.random(20, 60) -- (a moment to take it in, as anyone would)
      if i == 1 then say(m, ACKS[job.kind] and math.random() < 0.5 and pick(ACKS[job.kind]) or line(m, job.kind == "roam" and "roam" or "ack")) end
    end
    return
  end
  -- anything else: the LLM
  local llm = llm_settings(player)
  if not py() or llm.provider == "off" then
    tell(player, "I only understand simple orders without the fse loader and an AI provider.")
    return help(player)
  end
  local names = {}
  for _, m in pairs(members) do names[#names + 1] = m.name end
  jobs.start(owner, "aicrew:ask", helpers.table_to_json({ message = rest, to = names, llm = llm,
    context = context(player, members_of(owner)) }), { kind = "ask", owner = owner, to = names })
  for _, m in pairs(members) do
    if m.bubble and m.bubble.valid then m.bubble.destroy() end
    m.bubble = rendering.draw_text({ text = "...", surface = m.entity.surface, target = { entity = m.entity, offset = { 0, -2.9 } },
      color = m.color, scale = 1.4, alignment = "center", time_to_live = 600 })
  end
end

-- normal chat (T), as you'd talk to another player: a message starting with a crew member's name ("Rook, get coal")
-- goes to them, "crew ..." (all, everyone, guys, team) to everyone, a name later on ("thanks Rook") to that one. With
-- nobody else in the game, anything else goes to whoever is nearest (when it's an order, or there's an AI to answer)
local CALL_ALL = { crew = true, all = true, everyone = true, guys = true, team = true }
local function hear(owner, text)
  local members = members_of(owner)
  if #members == 0 or text:sub(1, 1) == "/" then return end
  local first, rest = text:match("^%s*([%w]+)[,:!]?%s*(.*)$")
  if not first then return end
  if rest == "" then rest = text end
  if CALL_ALL[first:lower()] then return order(owner, "crew " .. rest) end
  if find_member(first, owner) then return order(owner, first .. " " .. rest) end
  local low = text:lower()
  for _, m in pairs(members) do
    if low:find("%f[%a]" .. m.name:lower() .. "%f[%A]") then return order(owner, m.name .. " " .. text) end
  end
  if #game.connected_players > 1 then return end
  local player = owner and game.get_player(owner)
  local llm = llm_settings(player)
  local word = low:match("^%s*(%S+)")
  local meant = parse(text) or keep_out_cmd(low) or word == "remember" or word == "forget" or word == "notes"
    or storage.proposals and storage.proposals[owner or 0] and (YES[answer_of(text)] or NO[answer_of(text)])
  if not (meant or py() and llm.provider ~= "off") then return end
  local c = player and player.character
  if c then table.sort(members, function(a, b) return dist2(a.entity.position, c.position) < dist2(b.entity.position, c.position) end) end
  order(owner, members[1].name .. " " .. text)
end

script.on_event(defines.events.on_console_chat, function(ev)
  if ev.player_index and ev.message then hear(ev.player_index, ev.message) end
end)

-- -------------------------------------------------------------------------------------------------- AFK chatter

-- chatter waiting its turn: storage.lines {at, owner, who, text} (saved: a joining peer must say the same lines)
local function queued()
  storage.lines = storage.lines or {}
  return storage.lines
end

-- stock chatter: one member's line (an idle thought, or a reaction to ev), sometimes another's answer
local function canned(owner, members, ev)
  local pool = {}
  for _, m in pairs(members) do if not (ev and ev.who == m.name) then pool[#pool + 1] = m end end
  if #pool == 0 then return end
  local a = pick(pool)
  local g = storage.goals and storage.goals[owner]
  local text = ev and line(a, ev.kind, ev.vars) or g and math.random() < 0.3
    and string.format("Still on that goal: %d %s. We'll get there.", g.count, pretty(g.item)) or line(a, "idle")
  table.insert(queued(), { at = game.tick + (ev and 90 or 0), owner = owner, who = a.name, text = text })
  if #members > 1 and not ev and math.random() < 0.6 then
    local b
    repeat b = pick(members) until b ~= a
    table.insert(queued(), { at = game.tick + 240, owner = owner, who = b.name, text = line(b, "reply", { other = a.name }) })
  end
end

-- the crew talk among themselves: while the player is away (ev nil), or a reaction to something that happened
-- (ev = {kind = a LINES event, text = what happened, vars, who = the one it happened to}). The LLM writes it when
-- there's one, else stock lines
local function chatter(player, ev)
  local members = members_of(player.index)
  if #members == 0 then return end
  local llm = llm_settings(player)
  if py() and llm.provider ~= "off" then
    local ctx = context(player, members)
    ctx.goal = storage.goals and storage.goals[player.index]
    ctx.event = ev and ev.text
    -- (ev's who is a member's name: plain data, as a job keeps it in storage)
    local plain_ev = ev and { kind = ev.kind, text = ev.text, vars = ev.vars, who = type(ev.who) == "table" and ev.who.name or ev.who }
    if jobs.start(player.index, "aicrew:banter", helpers.table_to_json({ llm = llm, context = ctx }),
           { kind = "banter", owner = player.index, ev = plain_ev }) then
      return
    end
  end
  canned(player.index, members, ev)
end

-- Proposals. Every 10 minutes, with no goal and nothing needed: they look at what your factory used more of than it
-- made in the last 10 minutes (items with a recipe), and offer to deal with the worst of it: make a batch, or a
-- production line when bpgen is there. "yes" (sure, ok, do it...) makes it the goal; "no" leaves that item alone for
-- half an hour. Unanswered, the offer lapses after 5 minutes.
local function shortage(owner, surface, force)
  local stats = force.get_item_production_statistics(surface)
  local declined = storage.declined and storage.declined[owner or 0] or {}
  local best, bd
  for name in pairs(stats.output_counts) do
    local r = force.recipes[name]
    if r and r.enabled and prototypes.item[name] and game.tick - (declined[name] or -1e9) > 108000 then
      local function flow(cat)
        return stats.get_flow_count({ name = name, category = cat, precision_index = defines.flow_precision_index.ten_minutes, count = true })
      end
      local d = flow("output") - flow("input")
      if d > 0 and (not bd or d > bd) then best, bd = name, d end
    end
  end
  return best, bd
end

local function propose(owner)
  local members = members_of(owner)
  local k = owner or 0
  storage.proposals = storage.proposals or {}
  if #members == 0 or storage.proposals[k] or goals()[k] or #needs(owner) > 0 then return end
  local m = members[1]
  local item, d = shortage(owner, m.entity.surface, m.entity.force)
  if not item or d < 20 then return end
  local bp = remote.interfaces["bpgen"] and remote.interfaces["bpgen"].plan_line and true or nil
  local offer = { item = item, count = math.min(math.max(math.ceil(d / 50) * 50, 100), 2000), use_line = bp,
    rate = math.max(math.ceil(d / 50) * 5, 10), at = game.tick }
  storage.proposals[k] = offer
  local what = bp and ("build a production line for " .. pretty(item)) or ("make " .. offer.count .. " " .. pretty(item))
  remember(owner, "offered to " .. what .. " (" .. math.floor(d) .. " more used than made in 10 minutes)")
  local ev = { kind = bp and "propose_line" or "propose", vars = { item = pretty(item), n = offer.count },
    text = "the crew noticed " .. pretty(item) .. " runs short (" .. math.floor(d) .. " more used than made in 10 minutes). "
      .. "One of them asks the player, in one line, whether to " .. what .. ": a yes/no question" }
  local player = owner and game.get_player(owner)
  if player then chatter(player, ev) else canned(owner, members, ev) end
end

-- Hints. What a player at your side would point out, said in chat and out loud by the member nearest you: research
-- to start, machines starved of an ingredient (which one), power running short, machines with none, smelting or
-- mining backed up, something made far beyond what's used, and after 5 minutes with nothing built, crafted or
-- researched, what to do next (research, else an offer to make what runs short). One every 5 minutes at most, the same
-- one not again for half an hour; the AI words them when there is one. Setting: "Crew give hints".
local function cheapest_tech(force)
  local best, bc
  for _, t in pairs(force.technologies) do
    if t.enabled and not t.researched and not t.prototype.hidden and t.research_unit_count > 0 then
      local ok = true
      for _, pre in pairs(t.prerequisites) do if not pre.researched then ok = false break end end
      local cost = t.research_unit_count * #t.research_unit_ingredients
      if ok and (not bc or cost < bc) then best, bc = t, cost end
    end
  end
  return best
end

-- the ingredient a machine of this recipe is out of
local function missing_input(f)
  local r = f.get_recipe()
  local inv = f.get_inventory(defines.inventory.crafter_input or defines.inventory.assembling_machine_input)
  if not (r and inv) then return end
  for _, ing in pairs(r.ingredients) do
    if ing.type == "item" and inv.get_item_count(ing.name) < ing.amount then return ing.name end
  end
end

local function find_hint(owner, surface, force, at)
  local h = {}
  -- machines round you, grouped by what's wrong with them
  local starved, backed, low, dark = {}, {}, 0, 0
  for _, f in pairs(surface.find_entities_filtered({ type = { "assembling-machine", "furnace", "mining-drill", "lab" }, force = force,
    position = at, radius = 100 })) do
    local st = f.status
    if st == S.low_power then low = low + 1
    elseif st == S.no_power and not crew_built(f) then dark = dark + 1
    elseif (st == S.item_ingredient_shortage or st == S.no_ingredients) and f.type == "assembling-machine" then
      local r = f.get_recipe()
      local miss = r and missing_input(f)
      if miss then
        local g = starved[r.name] or { n = 0, miss = miss }
        g.n = g.n + 1
        starved[r.name] = g
      end
    elseif (st == S.full_output or st == S.waiting_for_space_in_destination) and (f.type == "furnace" or f.type == "mining-drill") then
      local r = f.type == "furnace" and f.get_recipe()
      local what = r and r.name or f.mining_target and f.mining_target.name or f.name
      backed[what] = (backed[what] or 0) + 1
    end
  end
  if low >= 3 then h[#h + 1] = { key = "power", kind = "hint_power", vars = { n = low }, text = low .. " machines are on low power" } end
  for name, g in pairs(starved) do
    if g.n >= 3 then
      h[#h + 1] = { key = "starved:" .. name, kind = "hint_starved", vars = { n = g.n, item = pretty(name), other = pretty(g.miss) },
        text = g.n .. " machines making " .. pretty(name) .. " are starved of " .. pretty(g.miss) }
    end
  end
  if dark >= 3 then h[#h + 1] = { key = "dark", kind = "hint_dark", vars = { n = dark }, text = dark .. " machines near the player have no power" } end
  for name, n in pairs(backed) do
    if n >= 4 then
      h[#h + 1] = { key = "backed:" .. name, kind = "hint_backed", vars = { n = n, item = pretty(name) },
        text = n .. " " .. pretty(name) .. " machines are backed up, nothing takes their output" }
    end
  end
  -- made far beyond what's used
  local stats = force.get_item_production_statistics(surface)
  for name in pairs(stats.input_counts) do
    local function flow(cat)
      return stats.get_flow_count({ name = name, category = cat, precision_index = defines.flow_precision_index.ten_minutes, count = true })
    end
    local made = flow("input")
    if made >= 2000 and flow("output") < made * 0.1 then
      h[#h + 1] = { key = "over:" .. name, kind = "hint_over", vars = { n = math.floor(made), item = pretty(name) },
        text = math.floor(made) .. " " .. pretty(name) .. " made in 10 minutes and almost none used" }
    end
  end
  -- nothing done for 5 minutes
  storage.progress_at = storage.progress_at or {}
  local k = owner or 0
  storage.progress_at[k] = storage.progress_at[k] or game.tick
  if game.tick - storage.progress_at[k] >= 18000 then
    local tech = not force.current_research and #force.research_queue == 0 and cheapest_tech(force)
    if tech then
      h[#h + 1] = { key = "research:" .. tech.name, kind = "hint_research", vars = { item = pretty(tech.name) },
        text = "nothing is being researched; " .. pretty(tech.name) .. " is the cheapest next technology" }
    else
      h[#h + 1] = { key = "stall", kind = "hint_stall", text = "the player has built and researched nothing for 5 minutes", stall = true }
    end
  end
  return h
end

-- one hint now, if there's one not given lately; its key
local function hint(owner, now)
  local members = members_of(owner)
  if #members == 0 then return end
  local k = owner or 0
  storage.hint_at, storage.hinted = storage.hint_at or {}, storage.hinted or {}
  storage.hinted[k] = storage.hinted[k] or {}
  if not now and game.tick - (storage.hint_at[k] or -18000) < 18000 then return end
  local player = owner and game.get_player(owner)
  local c = player and player.character
  local m = members[1]
  if c then table.sort(members, function(a, b) return dist2(a.entity.position, c.position) < dist2(b.entity.position, c.position) end) m = members[1] end
  for _, h in ipairs(find_hint(owner, c and c.surface or m.entity.surface, m.entity.force, c and c.position or m.home)) do
    if game.tick - (storage.hinted[k][h.key] or -108000) >= 108000 then
      storage.hinted[k][h.key], storage.hint_at[k] = game.tick, game.tick
      if h.stall then
        storage.progress_at[k] = game.tick -- (asked once; not again until another 5 minutes pass)
        storage.proposals = storage.proposals or {}
        propose(owner)
        if storage.proposals[k] then return h.key end
      end
      remember(owner, m.name .. " pointed out: " .. h.text)
      local llm = llm_settings(player)
      if player and py() and llm.provider ~= "off" then
        chatter(player, { kind = h.kind, vars = h.vars, who = nil,
          text = "a hint for the player: " .. h.text .. ". One of them (" .. m.name .. " ideally) tells the player in one short, " ..
            "helpful line, with a concrete suggestion" })
      else
        say(m, line(m, h.kind, h.vars))
      end
      return h.key
    end
  end
end

local function progress(owner) storage.progress_at = storage.progress_at or {} storage.progress_at[owner or 0] = game.tick end

-- something worth a word happened: remembered, and someone reacts (at most once a minute per player)
react = function(owner, kind, text, vars, who)
  remember(owner, text)
  local player = owner and game.get_player(owner)
  if not (player and player.connected) then return end
  storage.react_at = storage.react_at or {}
  if game.tick < (storage.react_at[owner] or 0) then return end
  storage.react_at[owner] = game.tick + 3600
  chatter(player, { kind = kind, text = text, vars = vars, who = who })
end

local function on_answer(p, out)
  local player = p.owner and game.get_player(p.owner)
  local a = helpers.json_to_table(out) or { error = "unreadable answer" }
  if p.kind == "ada" then
    local text = type(a.text) == "string" and a.text ~= "" and a.text or p.text
    game.print("[color=" .. ADA_COLOR .. "][ADA][/color] " .. text)
    return speak(text, "ada")
  end
  if p.kind == "check" then
    if not (a.provider or a.error) then a.error = "no answer" end
    ai_state()[p.owner] = a
    return
  end
  if p.kind == "banter" then
    local members = members_of(p.owner)
    if #members == 0 then return end
    local at = game.tick
    for _, r in pairs(type(a.replies) == "table" and a.replies or {}) do
      if type(r) == "table" and type(r.text) == "string" and r.text ~= "" then
        local m = find_member(r.who, p.owner) or members[1]
        table.insert(queued(), { at = at, owner = p.owner, who = m.name, text = r.text:sub(1, 200) })
        at = at + 300
      end
    end
    if at == game.tick then canned(p.owner, members, p.ev) end
    return
  end
  local fallback = find_member(p.to[1], p.owner)
  if a.error then
    if fallback and fallback.bubble and fallback.bubble.valid then fallback.bubble.destroy() end
    return tell(player, "[ai-crew] " .. tostring(a.error))
  end
  for _, r in pairs(a.replies or {}) do
    local m = find_member(r.who, p.owner) or fallback
    if m and type(r.text) == "string" and r.text ~= "" then say(m, r.text:sub(1, 300), "talk") end
  end
  for _, j in pairs(a.jobs or {}) do
    local m = find_member(j.who, p.owner) or fallback
    local job = m and type(j.kind) == "string" and job_for(m, j.kind, j.item, tonumber(j.count), j)
    if job then add_job(m, job) end
  end
end

jobs.on_answer = on_answer

-- ------------------------------------------------------------------------------------------------------------ panel
-- The crew button (top left) opens a window: movable and resizable with the fse-std library, a plain movable one
-- without. The chat box, then tabs: Crew, Orders, Goal, AI.

local mod_gui = require("mod-gui")
local fstd = script.active_mods["fse-std"] and require("__fse-std__/window") or nil
local WIN = "aic_window"
local PROVIDER_CHOICES, TOGGLES
local ADA_VOICES = { "ava", "jenny", "aria", "emma", "michelle" }

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
  { "voices", "Crew speak out loud", "Text to speech for the crew's lines (edge-tts voices if installed, else Windows')" },
  { "ada", "ADA announces milestones", "Research done, first science, rocket launches, deaths" },
  { "ada-llm", "ADA words her lines with the AI", "One AI request per announcement" },
  { "chatter", "Crew chatter while you're away", "After 2 minutes without input, every minute or so" },
  { "hints", "Crew give hints", "Research to start, starved or backed-up machines, power, oversupply, what to do next when nothing's happened for 5 minutes" },
  { "jetpack", "Crew jetpacks", "They fly over what's in their way (and to a fight); off: they step through it a few tiles at a time" },
}

local function ai_short(player)
  local a = ai_state()[player.index]
  if not py() then return "[color=0.7,0.7,0.7]AI chat off (no fse loader)[/color]" end
  if not a then return "[color=0.7,0.7,0.7]AI chat not tested (Settings tab)[/color]" end
  return a.ok and ("[color=0.4,1,0.4]AI chat: " .. tostring(a.provider) .. "[/color]") or "[color=1,0.4,0.4]AI chat not working (Settings tab)[/color]"
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
end

local function new_window(player)
  if fstd then
    return fstd.create(player, { name = WIN, title = "AI Crew", width = 640, height = 470, min_width = 520, min_height = 300 })
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

local function build_panel(player)
  local frame, c = new_window(player)
  local st = ui(player)
  local members = members_of(player.index)
  if #members > 0 then -- the chat box, always in sight
    local r = row(c)
    r.style.bottom_margin = 6
    local chat = r.add({ type = "textfield", name = "aic_chat",
      tooltip = "Talk to the crew (to whoever the Orders tab picks). Plain orders run as is; the rest goes to the AI. Enter sends." })
    chat.style.horizontally_stretchable = true
    chat.style.maximal_width = 1000
    btn(r, "Send", "send", nil, "Enter also sends", 60)
  end
  local tabs = c.add({ type = "tabbed-pane", name = "aic_tabs" })
  tabs.style.horizontally_stretchable = true
  tabs.style.vertically_stretchable = true
  local function tab(caption)
    local t = tabs.add({ type = "tab", caption = caption })
    local scroll = tabs.add({ type = "scroll-pane", horizontal_scroll_policy = "never", vertical_scroll_policy = "auto" })
    scroll.style.vertically_stretchable = true
    scroll.style.horizontally_stretchable = true
    tabs.add_tab(t, scroll)
    local body = scroll.add({ type = "flow", direction = "vertical" })
    body.style.vertical_spacing = 8
    body.style.horizontally_stretchable = true
    return body
  end

  -- Crew
  local crew_tab = tab("Crew")
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
    crew_tab.add({ type = "line" })
    r = row(crew_tab)
    r.add({ type = "label", caption = "Everyone:" })
    btn(r, "Build", "build", nil, "Place the ghosts near you now (making what's missing)", 64)
    btn(r, "Clear", "deconstruct", nil, "Remove what's marked for deconstruction near you", 64)
    btn(r, "Upgrade", "upgrade", nil, "Carry out the upgrade planner's marks near you (making the new pieces); recipes and contents kept", 76)
    btn(r, "Deliver", "deliver", nil, "Bring you everything they carry", 72)
    r = row(crew_tab)
    r.add({ type = "label", caption = "Everyone:" }).style.font_color = { 0, 0, 0, 0 } -- (lines up with the row above)
    btn(r, "Come", "follow", nil, "Follow you", 64)
    btn(r, "Roam", "roam", nil, "Wander round you on their own, dealing with what they find", 64)
    btn(r, "Stop", "stop", nil, "Drop all jobs", 56)
    btn(r, "Clear nests", "attack", nil, "Destroy the enemy spawners and worms within 96 tiles of you", 100)
  end

  -- Orders
  local orders = tab("Orders")
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
  note(orders, "Get works for anything: what isn't around they mine, craft or make in a machine (building the machine and its power if need be). Or type it in the box above: \"get 50 iron plate\", \"craft 10 gears\", \"attack\".")

  -- Goal
  local goal = tab("Goal")
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
  note(goal, goal_text(player.index), "aic_goal_status")

  -- Settings (the mod's per-player settings, written here)
  local ai = tab("Settings")
  local set = ai.add({ type = "table", column_count = 2 })
  set.style.vertical_align = "center"
  set.style.horizontal_spacing = 12
  set.style.vertical_spacing = 6
  set.add({ type = "label", caption = "AI provider" })
  local cur = player_setting(player, "ai-crew-provider") or "auto"
  local sel = 1
  for i, v in ipairs(PROVIDER_CHOICES) do if v == cur then sel = i end end
  set.add({ type = "drop-down", name = "aic_set_provider", items = PROVIDER_CHOICES, selected_index = sel,
    tooltip = "auto: picked from the key (sk-or- OpenRouter, gsk_ Groq, AIza Gemini, csk- Cerebras, sk_ Pollinations). off: plain orders only." })
  set.add({ type = "label", caption = "API key" })
  local key = set.add({ type = "textfield", name = "aic_set_key", text = player_setting(player, "ai-crew-api-key") or "",
    tooltip = "Free keys: openrouter.ai/keys, console.groq.com/keys, aistudio.google.com/apikey, cloud.cerebras.ai. Saved in your mod settings." })
  key.style.width = 360
  key.is_password = true
  set.add({ type = "label", caption = "Model" })
  local model = set.add({ type = "textfield", name = "aic_set_model", text = player_setting(player, "ai-crew-model") or "",
    tooltip = "Blank: picked for you (on OpenRouter, a current free model)" })
  model.style.width = 360
  r = row(ai)
  btn(r, "Save & test", "set_save", nil, "Save the provider, key and model, then ask the AI one short question", 110).enabled = py()
  btn(r, "Test", "ai_test", nil, "Ask the AI one short question now", 64).enabled = py()
  for i, line in ipairs(ai_lines(player)) do note(ai, line, "aic_ai_" .. i) end
  ai.add({ type = "line" })
  r = row(ai)
  r.add({ type = "label", caption = "ADA voice" })
  local cur_v = player_setting(player, "ai-crew-ada-voice") or "ava"
  local vi = 1
  for i, v in ipairs(ADA_VOICES) do if v == cur_v then vi = i end end
  r.add({ type = "drop-down", name = "aic_set_ada_voice", items = ADA_VOICES, selected_index = vi,
    tooltip = "A neural voice under ADA's effects (chorus and a detuned echo). Needs edge-tts; the effects need ffmpeg." })
  btn(r, "Hear", "ada_hear", nil, "ADA says a line in this voice", 60).enabled = py()
  for _, c in ipairs(TOGGLES) do
    ai.add({ type = "checkbox", name = "aic_set_" .. c[1], caption = c[2], state = player_setting(player, "ai-crew-" .. c[1]) and true or false,
      tooltip = c[3] })
  end
  tabs.selected_tab_index = math.min(st.tab or 1, 4)

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
  local s = find_el(f, "aic_ai_short")
  if s then s.caption = ai_short(player) end
  local lines = ai_lines(player)
  for i = 1, 6 do
    local l = find_el(f, "aic_ai_" .. i)
    if l then l.caption = lines[i] or "" end
  end
  if #lines > 0 and not find_el(f, "aic_ai_" .. #lines) then return build_panel(player) end
end

-- the drop-down's pick: a member's name, or "crew" for anyone
local function who_of(f)
  local dd = f and find_el(f, "aic_who")
  local i = dd and dd.selected_index or 1
  return i > 1 and dd.items[i] or "crew"
end

local function act(player, action, who)
  local f = open_frame(player)
  local st = ui(player)
  if action == "close" then
    if f then f.destroy() end
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
    order(player.index, "crew fire " .. who)
  elseif action == "mode" then -- follow, roam, stay, follow...
    local m = find_member(who, player.index)
    if m then order(player.index, m.name .. " " .. (m.roam and "stay" or m.follow and "roam" or "follow")) end
  elseif action == "get" or action == "mine" or action == "craft" then
    if not st.item then return player.print("Pick an item first.") end
    order(player.index, who_of(f) .. " " .. action .. " " .. (tonumber(st.count) or 50) .. " " .. st.item)
  elseif action == "goal_set" then
    if not st.goal_item then return player.print("Pick the goal's item first.") end
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
-- hovered; gone when the cursor leaves them. (In a block of its own: the main chunk is at Lua's 200-locals limit.)
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
    if open_frame(player) then open_frame(player).destroy() else build_panel(player) end
  elseif el.tags and el.tags.aic and (el.type == "button" or el.type == "sprite-button") then
    act(player, el.tags.aic, el.tags.who)
  end
end)

script.on_event(defines.events.on_gui_checked_state_changed, function(ev)
  local el = ev.element
  if el.name == "aic_goal_line" then ui(game.get_player(ev.player_index)).goal_line = el.state return end
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
    game.get_player(ev.player_index).mod_settings["ai-crew-ada-voice"] = { value = ADA_VOICES[ev.element.selected_index] or "ava" }
  end
  if ev.element.name == "aic_who" then ui(game.get_player(ev.player_index)).who = ev.element.selected_index end
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
if script.active_mods["fse-std"] then
  script.on_event("fse-sync", function(e)
    if e.key ~= "ai-crew:answer" then return end
    local d = helpers.json_to_table(e.data)
    if d and d.n then jobs.answered(d.n, d.st, d.out) end
  end)
end

-- ------------------------------------------------------------------------------------------------------- milestones

local SCIENCE
local function science_check(silent)
  local f = game.forces.player
  if not f then return end
  if not SCIENCE then
    SCIENCE = {}
    for name in pairs(prototypes.get_item_filtered({ { filter = "type", type = "tool" } })) do SCIENCE[#SCIENCE + 1] = name end
  end
  storage.seen = storage.seen or {}
  for _, s in pairs(game.surfaces) do
    local stats = f.get_item_production_statistics(s).input_counts
    for _, name in ipairs(SCIENCE) do
      if not storage.seen[name] and (stats[name] or 0) > 0 then
        storage.seen[name] = true
        if not silent then ada("Production milestone: first " .. pretty(name) .. " produced. Well done, pioneer.") end
      end
    end
  end
end

-- ----------------------------------------------------------------------------------------------------------- events

local function init()
  crew()
  storage.paths, storage.claims = storage.paths or {}, storage.claims or {}
  if not storage.seen then science_check(true) end
  -- (0.3.1 could crowd the player's base with the crew's machines: empty ones too close to it get taken down)
  for _, b in pairs(storage.crew_built or {}) do
    if b.valid and not b.to_be_deconstructed() then
      local bb = b.bounding_box
      local area = { { bb.left_top.x - 3, bb.left_top.y - 3 }, { bb.right_bottom.x + 3, bb.right_bottom.y + 3 } }
      local empty = true
      for _, i in ipairs({ 1, 2, 3, 4 }) do
        local inv = b.get_inventory(i)
        if inv and not inv.is_empty() then empty = false end
      end
      if empty and players_stuff(b.surface, b.force, area) then b.order_deconstruction(b.force) end
    end
  end
  if storage.map_v ~= 2 then -- (map markers drawn again: the first ones' names grew huge when zoomed out)
    for _, o in pairs(rendering.get_all_objects(script.mod_name)) do
      if o.valid and o.render_mode == "chart" then o.destroy() end
    end
    for _, m in pairs(crew()) do m.mapped = nil end
    storage.map_v = 2
  end
  for _, m in pairs(crew()) do
    if m.entity and m.entity.valid and not m.mapped then map_marker(m.entity, m.name, m.color) end
    m.mapped = true
  end
  for _, p in pairs(game.players) do
    add_button(p)
    local old = mod_gui.get_frame_flow(p).aic_panel -- (0.1's panel)
    if old then old.destroy() end
  end
end
script.on_init(init)

-- you put something down where a crew member stands (their body would block it): they step aside first
script.on_event(defines.events.on_pre_build, function(ev)
  local player = game.get_player(ev.player_index)
  if not player then return end
  for _, m in pairs(crew()) do
    local e = m.entity
    if e.valid and e.surface == player.surface and dist2(e.position, ev.position) < 9 then
      local to = e.surface.find_non_colliding_position(CREW, { x = e.position.x + (e.position.x >= ev.position.x and 3 or -3),
        y = e.position.y }, 6, 0.5)
      if to and dist2(to, ev.position) >= 6 then e.teleport(to) end
    end
  end
end)
script.on_configuration_changed(function() source_names, machine_cache = {}, {} init() end)

script.on_event(defines.events.on_tick, function(ev)
  local t = ev.tick
  if not jobs.checked and t % 60 == 0 and not game.is_multiplayer() then -- (once a session, a second in: the
    jobs.checked = true                                                    -- AI tested for whoever is playing)
    storage.ai = nil -- (before 0.8.0)
    storage.ai_tests = {} -- (the last session's results say nothing about now)
    for _, p in pairs(game.connected_players) do if py() and llm_settings(p).provider ~= "off" then check_ai(p) end end
  end
  for name, m in pairs(crew()) do
    local e = m.entity
    if not (e and e.valid) then
      crew()[name] = nil
    else
      if m.drop_at then
        if not e.vehicle then e.teleport(m.drop_at) end
        m.drop_at = nil
      end
      if m.ride then riding(m) end
      if m.ride and e.vehicle then -- (driving or riding: nothing else moves them)
      elseif m.fly then flight(m) elseif m.move then walk(m) end
      if m.mining then
        e.update_selected_entity(m.mining)
        e.mining_state = { mining = true, position = m.mining }
      end
      if m.target then
        if m.target.valid then
          e.shooting_state = { state = defines.shooting.shooting_enemies, position = m.target.position }
        else
          m.target = nil
          e.shooting_state = { state = defines.shooting.not_shooting, position = e.position }
        end
      end
      local war = m.jobs[1] and (m.jobs[1].kind == "attack" or m.jobs[1].kind == "defend")
      if (t + m.phase) % (war and 15 or 30) == 0 then fight(m) end
      if (t + m.phase) % 10 == 0 and not m.fly and (not m.move or (war and (t + m.phase) % 60 == 0)) and not m.retreat then think(m) end
      if m.retreat and not m.move and (t + m.phase) % 60 == 0 then go(m, anchor(m), 4) end
    end
  end
  if t % 5 == 0 and next(jobs.running) then
    for id, n in pairs(jobs.running) do
      local st, out = native.poll(id)
      if st ~= "pending" then
        jobs.running[id] = nil
        jobs.deliver(n, st, out)
      end
    end
  end
  if t % 600 == 0 and storage.jobs then -- (a job whose peer left, or never answered)
    for n, p in pairs(storage.jobs) do if t - p.at > 18000 then storage.jobs[n] = nil end end
  end
  if t % 30 == 0 then
    for _, p in pairs(game.connected_players) do
      refresh(p)
      if p.gui.screen.aic_card or hover.shown[p.index] then hover.show(p, hover.member_of(p.selected)) end -- (kept current)
    end
    local lines = queued()
    for i = #lines, 1, -1 do
      local l = lines[i]
      if t >= l.at then
        table.remove(lines, i)
        local m = find_member(l.who, l.owner)
        if m then say(m, l.text, "talk") end
      end
    end
  end
  if t % 60 == 0 then -- back at the keyboard after a while away: someone says hello
    storage.away = storage.away or {}
    for _, p in pairs(game.connected_players) do
      if p.afk_time > 7200 then storage.away[p.index] = true
      elseif storage.away[p.index] and p.afk_time < 120 then
        storage.away[p.index] = nil
        local members = members_of(p.index)
        if #members > 0 then
          local m = pick(members)
          say(m, line(m, "welcome"), "talk")
        end
      end
    end
  end
  if t % 600 == 300 then -- hints, for players at the keyboard who want them
    for _, p in pairs(game.connected_players) do
      if p.afk_time < 3600 and player_setting(p, "ai-crew-hints") ~= false then hint(p.index) end
    end
  end
  if t % 600 == 0 then -- offers: a new one every 10 minutes you're at the keyboard, an old one lapsing after 5
    storage.propose_at = storage.propose_at or {}
    for k, o in pairs(storage.proposals or {}) do if t - o.at > 18000 then storage.proposals[k] = nil end end
    for _, p in pairs(game.connected_players) do
      if p.afk_time < 3600 and t >= (storage.propose_at[p.index] or 36000) then
        storage.propose_at[p.index] = t + 36000
        propose(p.index)
      end
    end
  end
  if t % 600 == 0 then
    storage.chat_at = storage.chat_at or {}
    for _, p in pairs(game.connected_players) do
      if p.afk_time > 7200 and t >= (storage.chat_at[p.index] or 0) and player_setting(p, "ai-crew-chatter") then
        storage.chat_at[p.index] = t + math.random(3600, 7200)
        chatter(p)
      end
    end
  end
  if t % 600 == 0 then science_check(false) end
  for k = #delayed, 1, -1 do
    if t >= delayed[k].at then path_finished(table.remove(delayed, k).ev) end
  end
  if t % 300 == 0 and storage.fallen then
    for name, f in pairs(storage.fallen) do
      if t >= f.at and game.get_surface(f.surface) then
        storage.fallen[name] = nil
        local m = hire(name, game.get_surface(f.surface), f.home, f.force, f.owner)
        if m then
          m.auto, m.defend, m.follow = f.auto, f.defend, f.follow
          m.roam = f.roam
          for k, v in pairs(f.stats or {}) do m[k] = v end
          say(m, line(m, "back"))
        end
      end
    end
  end
  if storage.queue_check and t >= storage.queue_check then
    storage.queue_check = nil
    local f = game.forces.player
    if f and not f.current_research and #f.research_queue == 0 then ada("Research queue empty. Awaiting your input, pioneer.") end
  end
end)


path_finished = function(ev)
  if storage.path_delay and not ev.delayed then
    delayed[#delayed + 1] = { at = game.tick + storage.path_delay, ev = { id = ev.id, path = ev.path, try_again_later = ev.try_again_later,
      tick = ev.tick, delayed = true } }
    return
  end
  local name = storage.paths and storage.paths[ev.id]
  if not name then return end
  storage.paths[ev.id] = nil
  local m = crew()[name]
  if m and m.ride and m.ride.path_id == ev.id then -- (a route for the car)
    if ev.path then m.ride.path, m.ride.i = ev.path, 1
    elseif ev.try_again_later then m.ride.repath = true
    else m.ride.failed = true end
    return
  end
  if not (m and m.move) then return end
  if ev.path then
    m.move.path, m.move.i, m.move.straight, m.move.closest, m.move.closest_at = ev.path, 1, nil, nil, nil
    -- a long way round something they could fly over: fly
    local len, prev = 0, m.entity.position
    for _, wp in ipairs(ev.path) do len, prev = len + math.sqrt(dist2(prev, wp.position)), wp.position end
    local straight = math.sqrt(dist2(m.entity.position, m.move.goal))
    if straight <= JET and len > straight * 2.5 + 8 then fly(m, m.move.goal) end
  elseif ev.try_again_later then
    m.move.retry = ev.tick + 30
  else
    -- no path: fly over, else straight at it, and walk()'s step-through covers whatever that runs into
    m.move.path, m.move.i, m.move.straight = { { position = m.move.goal } }, 1, true
    fly(m, m.move.goal)
  end
end
script.on_event(defines.events.on_script_path_request_finished, path_finished)

-- your buildings hit by an enemy: the crew nearby come to defend them (once every 2 s per place)
script.on_event(defines.events.on_entity_damaged, function(ev)
  local ent, by = ev.entity, ev.force
  if not (by and ent.valid and ent.force.is_enemy(by)) then return end
  storage.attacks = storage.attacks or {}
  local k = ent.surface.index
  local a = storage.attacks[k]
  if a and game.tick - a.tick < 120 and dist2(a.pos, ent.position) < 32 * 32 then return end
  storage.attacks[k] = { pos = ent.position, tick = game.tick }
  alarm(ent.surface, ent.force, ent)
end, (function()
  local f = {}
  for _, t in ipairs({ "unit", "unit-spawner", "turret", "character", "tree", "simple-entity", "fish" }) do
    f[#f + 1] = { filter = "type", type = t, invert = true, mode = "and" }
  end
  return f
end)())

-- what counts as progress (no "nothing done" hint while there's some): building, crafting, research
script.on_event({ defines.events.on_built_entity, defines.events.on_player_crafted_item }, function(ev) progress(ev.player_index) end)

script.on_event(defines.events.on_research_finished, function(ev)
  for _, p in pairs(ev.research.force.players) do progress(p.index) end
  if ev.by_script then return end
  ada("Research complete: " .. pretty(ev.research.name) .. ".")
  for _, p in pairs(ev.research.force.connected_players) do
    react(p.index, "research", "research done: " .. pretty(ev.research.name), { item = pretty(ev.research.name) })
  end
  storage.queue_check = ev.tick + 60
end)

script.on_event(defines.events.on_rocket_launched, function()
  ada("Rocket launch confirmed. Excellent work, pioneer.")
end)

script.on_event(defines.events.on_player_died, function()
  ada("Pioneer vital signs lost. Initiating respawn protocol.")
end)

script.on_event(defines.events.on_entity_died, function(ev)
  local cause = ev.cause
  if cause and cause.valid and cause.name == CREW and ev.entity.type ~= "character" then -- (an enemy one of them killed)
    for _, m in pairs(crew()) do if m.entity == cause then m.kills = (m.kills or 0) + 1 end end
    return
  end
  if ev.entity.type ~= "character" then return end
  for name, m in pairs(crew()) do
    if m.entity == ev.entity then
      crew()[name] = nil
      storage.fallen = storage.fallen or {}
      storage.fallen[name] = { at = ev.tick + 3600, owner = m.owner, home = m.home, surface = m.entity.surface.name,
        force = m.entity.force.name, auto = m.auto, defend = m.defend, follow = m.follow, roam = m.roam,
        stats = { kills = m.kills, built = m.built, deaths = (m.deaths or 0) + 1, rides = m.rides, flights = m.flights } }
      ada("Crew member " .. name .. " is down. Reconstruction in sixty seconds.")
      react(m.owner, "down", name .. " was killed" .. (ev.cause and ev.cause.valid and (" by a " .. pretty(ev.cause.name)) or ""),
        { other = name }, name)
    end
  end
end, { { filter = "type", type = "character" }, { filter = "type", type = "unit" }, { filter = "type", type = "unit-spawner" },
  { filter = "type", type = "turret" } })

remote.add_interface("ai-crew", {
  hire = function(name, surface, position, force, owner)
    local m, err = hire(name, game.get_surface(surface) or surface, position, force or "player", owner)
    if not m then error(err) end
    return m.name
  end,
  order = function(owner, text) order(owner, text) end,
  -- (tests) a line typed in normal chat
  hear = function(owner, text) hear(owner, text) end,
  -- (tests) path answers held back n ticks, as a busy pathfinder would
  test_path_delay = function(n) storage.path_delay = n end,
  -- (tests) a button of the window pressed
  press = function(player_index, action) act(game.get_player(player_index), action) end,
  ai_status = function(player_index) return ai_state()[player_index] end,
  -- what the crew remember lately (the AI gets it): {tick, text}, oldest first
  memory = function(owner) return storage.events and storage.events[owner or 0] end,
  notes = function(owner) return storage.notes and storage.notes[owner or 0] end,
  -- (tests) an offer made now; the goal
  propose = function(owner) propose(owner) return storage.proposals and storage.proposals[owner or 0] end,
  goal = function(owner) return storage.goals and storage.goals[owner or 0] end,
  -- (tests) a hint now (the 5-minute gap skipped); its key
  hint = function(owner) return hint(owner, true) end,
  -- (tests) the window opened on a tab
  panel = function(player_index, tab)
    local player = game.get_player(player_index)
    ui(player).tab = tab or 1
    build_panel(player)
  end,
  -- bpgen's answer to plan_line: its ghosts are placed (the crew build them), or why not (they make it by hand)
  line_placed = function(owner, item, ghosts, err, abs)
    local key = owner or 0
    local g = goals()[key]
    if not (g and g.item == item and g.line and g.line.state == "asked") then return end
    local m = members_of(owner)[1]
    if err or not (abs and abs.box) then
      g.line = false
      if m then say(m, "No line from bpgen (" .. tostring(err) .. "). We'll make it by hand.") end
      return
    end
    g.line = { state = "placed", box = abs.box, inputs = abs.inputs or {}, outputs = abs.outputs or {} }
    for _, o in pairs(crew()) do if o.owner == owner then o.auto_wait, o.goal_wait = nil, nil end end
    if m then say(m, "bpgen laid out a " .. pretty(item) .. " line: " .. tostring(ghosts) .. " pieces. Let's build it.") end
  end,
  status = function(name)
    local m = crew()[name]
    if not m then return end
    local inv = {}
    for _, it in pairs(m.entity.get_main_inventory().get_contents()) do inv[it.name] = (inv[it.name] or 0) + it.count end
    local j = m.jobs[1]
    return { lines = m.lines or 0, last_lines = m.last_lines, rides = m.rides or 0, riding = m.ride and m.entity.vehicle and m.entity.vehicle.name or nil, flights = m.flights or 0, flying = m.fly ~= nil, mode = m.roam and "roam" or m.follow and "follow" or "stay", position = m.entity.position, jobs = #m.jobs, health = m.entity.health, retreat = m.retreat, armed = gun_range(m) > 0,
      fighting = m.target and m.target.valid and m.target.name or nil, unit = m.entity.unit_number, doing = j and (j.kind .. ((j.item or j.recipe) and (" " .. (j.item or j.recipe) .. " " .. (j.n or 0) .. "/" .. (j.count or "")) or "")),
      inventory = inv, fed = m.fed, collected = m.collected, need = storage.needs and storage.needs[m.owner or 0] and storage.needs[m.owner or 0][1] and storage.needs[m.owner or 0][1].item }
  end,
})

-- the fse-std window's own handlers (title bar close, remembered place, resize grip), after ours
if fstd then
  require("__fse-std__/safe").chain("ai-crew", { require("__fse-std__/input").handlers, fstd.handlers })
end
