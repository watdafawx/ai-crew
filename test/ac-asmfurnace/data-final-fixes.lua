-- the stone furnace as some overhaul packs (Krastorio 2) make it: an assembling machine, its recipe chosen by hand
local f = data.raw.furnace["stone-furnace"]
data.raw.furnace["stone-furnace"] = nil
f.type = "assembling-machine"
f.crafting_categories = { "smelting" }
f.source_inventory_size, f.result_inventory_size = nil, nil
data.raw["assembling-machine"]["stone-furnace"] = f
