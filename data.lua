-- The crew cards' rings (cards.lua): a frame drawn round a card while that crew member talks, in their colour (one for
-- each of control.lua's COLORS, in the same order), a red one while they fight, and the plain one (no ring, the same
-- room) the rest of the time.
local COLORS = { { 1, 0.55, 0.2 }, { 0.3, 0.8, 1 }, { 0.6, 1, 0.4 }, { 1, 0.4, 0.7 }, { 1, 0.9, 0.3 }, { 0.7, 0.5, 1 },
  { 0.4, 1, 0.9 }, { 1, 0.6, 0.5 } }
local styles = data.raw["gui-style"].default
styles.aic_card_plain = { type = "frame_style", padding = 3, graphical_set = {} }
COLORS.fight = { 0.95, 0.25, 0.2 }  -- (fighting: red)
for i, c in pairs(COLORS) do
  styles["aic_card_ring_" .. i] = { type = "frame_style", padding = 3, graphical_set = { base = {
    filename = "__ai-crew__/graphics/white.png", position = { 0, 0 }, size = 8, corner_size = 3,
    tint = { c[1], c[2], c[3], 1 } } } }
end
