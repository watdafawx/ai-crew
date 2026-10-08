# AI Crew

Helper characters for Factorio 2.0 that work like construction bots with legs: they build your ghosts, clear
deconstruction marks, mine, craft, smelt, fight, and work towards goals you set (setting up furnaces, assemblers,
power and whole production lines when they need them), all from a window in game. With the
[fnative](https://github.com/watdafawx/fnative) loader they also chat through a free LLM, speak out loud, and ADA
(Satisfactory style) announces your milestones. Single player.

## Install

1. Copy (or symlink) this folder into your mods folder as `ai-crew` (`%APPDATA%\Factorio\mods\ai-crew`) and enable
   "AI Crew". That's all for the crew's work, goals and combat.
2. For chat, voices and ADA: [fnative](https://github.com/watdafawx/fnative) (start the game through its launcher,
   install `fnative-std`), and add this folder to `FNATIVE_PYPATH` in fnative's `dist\fnative.env` (`aicrew.py` is
   loaded from there). Natural voices: `pip install edge-tts`; ADA's effects: ffmpeg (`winget install Gyan.FFmpeg`).
3. For production lines in goals: [bpgen](https://github.com/watdafawx/bpgen) (its in-game mod and fnative).

## The window

The crew button (top left) opens it: movable, and resizable with fnative-std. The chat box on top (plain orders run
as is, the rest goes to the AI), then tabs:

- **Crew**: whether AI chat works, each member's job with **Fight**, **Auto**, **Stay/Follow**, **Stop**, **Fire**;
  **Hire**; everyone: **Build**, **Clear**, **Upgrade**, **Deliver**, **Come**, **Stop**, **Clear nests**.
- **Orders**: who (or anyone), an item and a count: **Get** (from chests or the network, else mined, crafted or made in
  a machine; brought to you), **Mine**, **Craft**.
- **Goal**: an item, how many to have, optionally a **Production line** (bpgen) at a rate; what they're on.
- **Settings**: AI provider, API key, model (**Save & test** checks it for real and shows the answer or the error),
  voices, ADA, chatter. The same values as Settings > Mod settings > Per player.

**Auto** (on by default): with nothing queued, a crew member works like a construction bot within 48 tiles of you:
deconstruction marks first (items brought to you), then the upgrade planner's marks, then ghosts, making what's
missing. Upgrades are done as a player's hand does them (fast-replace): the machine keeps its recipe and contents, a
belt its items, everything its direction and settings, and the old piece comes back to you. Items come from your
pockets, chests near you and your logistic network, taken directly (no walking to each chest). Everything but chat
works without fnative.

**Goal**: an item and how many you want to have. Whenever there's nothing to build or clear, the crew plan the next
step on their own until it's reached (ADA announces it). The AI can set goals from chat too. With **Production line**
(needs bpgen and fnative) bpgen plans a line for it next to your base (its Extend: taps your belts or main bus where
it can), placed as ghosts; the crew build it, power it, keep its burners fuelled, feed by hand whatever no belt
brings (ore and coal on a lane each) and take the product off its output to you. In chat: "goal 500 iron gear wheel
line".

**They work for what they lack.** A ghost whose item nobody has, a craft order short on ingredients, or "get" for
something only a machine makes becomes a *need*, worked on before the goal. The plan for any item, step by step:
take it if it's around; mine it if there's a source nearby (ore, stone, coal, trees); hand-craft it; otherwise run its
recipe in a free machine near you: load the ingredients, fuel burners (coal, else wood, mined if need be), collect the
output. They borrow only machines of yours that no inserter feeds or empties (anything in a production line is left
alone), and put their own on their grid, 3 tiles clear of your buildings, ghosts and floors (concrete, paths),
beside the ones they built before; never more than three of a kind. Vanilla furnaces pick their own recipe; assembler-type machines (assemblers, and overhaul mods' furnaces that
need a recipe chosen) get it set when they're empty and idle.

**They build what the plan needs.** No free machine for a recipe? They make one (burner-powered kinds first, so a
stone furnace for smelting) and set it up near you. An electric machine standing dark gets power: poles grown from
the nearest powered pole, or from a generator; with no power anywhere they build steam at the nearest water (offshore
pump, boiler, steam engine, each trial-placed and kept only when its pipes connect, so modded ones work too). Boilers,
furnaces and burner drills near you are kept fuelled whenever there's coal or wood about. What they can't do: research
(they tell you what needs researching), fluids other than water to steam, and planning big layouts.
- **Chat box**: plain orders ("get 50 iron ore", "craft 10 gears", "goal 200 iron gear wheel") run as is; anything
  else goes to the AI.

**Combat.** With **Fight** ticked (each crew row, on by default) a crew member arms itself from your stock (best
armor; a gun whose ammo is in stock, or can be made, before a longer-range one with none; that ammo in the slot
beside it, topped up; makes the gun and its ammo when there are none) and shoots enemies in range while it works. Hurt, it eats raw fish
if there is any; below half health it falls back to you and rejoins once healed. **Clear nests** (or "attack" in
chat) sends them after the spawners and worms within 96 tiles of you. A crew member who dies is rebuilt at home a
minute later, same name and settings, empty-handed (ADA announces both).

When you've been away from the keyboard for 2 minutes the crew chat among themselves every minute or so: written by
the AI when one is set up, stock lines otherwise (setting: "Crew chatter while you are away").

Items are taken from your pockets, chests near you and the logistic network you stand in, directly (no walking to
each chest). Everything but the chat
works without fnative.

## AI and voices (needs fnative)

`aicrew.py` (on `FNATIVE_PYPATH`) talks to any OpenAI-compatible API. Get a free key and paste it in the
window's Settings tab (Save & test tells you at once whether it works); the provider is picked from it:

| provider | key from | key starts |
|---|---|---|
| OpenRouter (picks a current `:free` model) | openrouter.ai/keys | `sk-or-` |
| Groq | console.groq.com/keys | `gsk_` |
| Google Gemini | aistudio.google.com/apikey | `AIza` |
| Cerebras | cloud.cerebras.ai | `csk-` |
| Pollinations | enter.pollinations.ai | `sk_` |
| Mistral | console.mistral.ai | (choose `mistral`) |
| Ollama (local, no key) | | (choose `ollama`) |

Or set `OPENROUTER_API_KEY` (etc.) before starting the game. The Model setting overrides the pick.

Voices: `pip install edge-tts` for natural neural voices (each crew member has their own, ADA is Ava); without it
Windows' built-in voices are used. Toggle crew voices, ADA, and "ADA words her lines with the AI" per player.

ADA's voice: Satisfactory's ADA is, by the community's ear, Google's WaveNet `en-US-Wavenet-C` with a multi-voice
chorus and a doubled, slightly detuned echo. Here a neural edge-tts voice (pick it in Settings: ava, jenny, aria,
emma, michelle; **Hear** plays a line) goes through the same effects with ffmpeg when it's installed
(`winget install Gyan.FFmpeg`). A short chime plays before each line: a synthesized one (two rising bell tones with
an echo), or your own `ada-chime.wav` put next to `aicrew.py`.

ADA speaks on: research finished, research queue empty, first of each science pack produced, rocket launched, your
death, crew hired or lost.

## Tests

From this folder:

```
python test/run.py ac-place 36010   headless game: own furnace on clear ground, the player's line machines left alone
python test/run.py ac-asmfurnace 36010 headless game: the same with a stone furnace that needs a recipe (overhaul packs)
python test/run.py ac-upgrade 18010 headless game: upgrade marks done like a player: recipe, contents, belt items kept
python test/run.py ac-arm 18010    headless game: no weapons anywhere: makes a submachine gun and magazines
python test/run.py ac-arm2 36010   headless game: magazines but no shells: submachine guns, not shotguns; stray ammo fixed
python test/run.py ac-fight        headless game: arms up, kills biters, clears a spawner and a worm, respawns
python test/run.py ac-line 72010   headless game: a goal with a line (a stand-in bpgen places it): built, fed, emptied
python test/run.py ac-power 144010 headless game: an engine goal with no assembler and no power: they build both
python test/run.py ac-boot         headless game: from nothing, a furnace, plates, a ghost, gears, an engine
python test/run.py ac-goal         headless game: a 10 gear goal from ore, coal and an empty furnace
python test/run.py                 headless game: auto clear and build (crafting a missing item), mine round a wall, craft, deliver
python test/run_gui.py             real client (fnative launcher): every tab screenshotted, Settings saved and tested
python test/run_gui.py ac-follow   real client: the crew follow you through a block of machines (slow pathfinder)
python test/test_py.py [--live KEY] aicrew.py offline; --live asks a real provider once
```
