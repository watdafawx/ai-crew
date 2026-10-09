-- The crew's body: a copy of the character with a thinner collision box, so only the crew are thin and the player
-- keeps the vanilla box.
--
-- This has to happen in data-final-fixes, not data.lua: Space Age rewrites the base character in its own data.lua
-- (crafting_categories gains "pressing"/"electronics" and the like) and other mods may touch it later still. ai-crew
-- does not depend on Space Age, so our data.lua runs before that, and a copy taken there would be missing all of it:
-- the crew then could not hand-craft belts or electric poles.
local CREW_BOX = { { -0.1, -0.1 }, { 0.1, 0.1 } } -- half the width of a player, and a good deal shorter

local base = data.raw.character and data.raw.character.character
if base then
  local crew = table.deepcopy(base)
  crew.name = "crew-character"
  crew.localised_name = { "entity-name.crew-character" }
  crew.collision_box = CREW_BOX
  crew.selection_box = { { -0.3, -1.1 }, { 0.3, 0.2 } }
  crew.hit_visualization_box = { { -0.15, -1 }, { 0.15, 0.2 } }
  crew.sticker_box = { { -0.15, -0.85 }, { 0.15, 0 } }
  crew.order = "ab"
  -- belt immunity: belts don't carry them off, so they cross and stand on belts as a player with the equipment does
  crew.has_belt_immunity = true
  data:extend({ crew })
  log("ai-crew: crew-character collision_box w=" .. (CREW_BOX[2][1] - CREW_BOX[1][1]))
else
  log("ai-crew: no base character prototype to copy: the crew stay full width")
end
