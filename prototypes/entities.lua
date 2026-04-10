-- Custom collision layer for the deployer chest so it doesn't conflict with the train stop
data:extend({{type = "collision-layer", name = "ata-chest-layer"}})

-- Train Deployer: a real train stop that snaps to rails
local deployer = table.deepcopy(data.raw["train-stop"]["train-stop"])
deployer.name = "ata-deployer"
deployer.minable = {mining_time = 0.5, result = "ata-deployer"}
deployer.max_health = 300
deployer.icon = "__base__/graphics/icons/train-stop.png"
deployer.icon_size = 64
deployer.flags = {"placeable-neutral", "player-creation", "filter-directions"}
deployer.order = "z[auto-train-adder]-a[deployer]"

-- Save the train stop's selection box before making it non-selectable
local deployer_selection_box = deployer.selection_box

-- Co-located chest for inserter access (invisible, same position as train stop)
local deployer_chest = {
  type = "container",
  name = "ata-deployer-chest",
  inventory_size = 20,
  icon = "__base__/graphics/icons/iron-chest.png",
  icon_size = 64,
  -- Collision box for inserter access, custom layer to avoid conflicts with train stop
  collision_box = {{-0.35, -0.35}, {0.35, 0.35}},
  selection_box = {{0, 0}, {0, 0}},
  -- Circuit wire support — this is the entity players connect wires to
  circuit_wire_max_distance = 9,
  circuit_wire_connection_point = data.raw["container"]["steel-chest"].circuit_wire_connection_point,
  collision_mask = {layers = {["ata-chest-layer"] = true}},
  -- Invisible - the train stop provides the visuals
  picture = {
    filename = "__core__/graphics/empty.png",
    width = 1,
    height = 1,
  },
  flags = {
    "placeable-neutral",
    "not-selectable-in-game",
    "not-deconstructable",
    "not-blueprintable",
    "placeable-off-grid",
    "not-on-map",
  },
  hidden = true,
  hidden_in_factoriopedia = true,
  max_health = 1,
  enable_inventory_bar = false,
}

-- Hidden output combinator for deployer status signals
local deployer_output = {
  type = "constant-combinator",
  name = "ata-deployer-output",
  icon = "__base__/graphics/icons/constant-combinator.png",
  icon_size = 64,
  collision_box = {{0, 0}, {0, 0}},
  selection_box = {{0, 0}, {0, 0}},
  collision_mask = {layers = {}},
  sprites = {
    north = {filename = "__core__/graphics/empty.png", width = 1, height = 1},
    east = {filename = "__core__/graphics/empty.png", width = 1, height = 1},
    south = {filename = "__core__/graphics/empty.png", width = 1, height = 1},
    west = {filename = "__core__/graphics/empty.png", width = 1, height = 1},
  },
  activity_led_sprites = {
    north = {filename = "__core__/graphics/empty.png", width = 1, height = 1},
    east = {filename = "__core__/graphics/empty.png", width = 1, height = 1},
    south = {filename = "__core__/graphics/empty.png", width = 1, height = 1},
    west = {filename = "__core__/graphics/empty.png", width = 1, height = 1},
  },
  activity_led_light_offsets = {{0, 0}, {0, 0}, {0, 0}, {0, 0}},
  circuit_wire_connection_points = {
    {wire = {red = {0, 0}, green = {0, 0}}, shadow = {red = {0, 0}, green = {0, 0}}},
    {wire = {red = {0, 0}, green = {0, 0}}, shadow = {red = {0, 0}, green = {0, 0}}},
    {wire = {red = {0, 0}, green = {0, 0}}, shadow = {red = {0, 0}, green = {0, 0}}},
    {wire = {red = {0, 0}, green = {0, 0}}, shadow = {red = {0, 0}, green = {0, 0}}},
  },
  circuit_wire_max_distance = 0,
  draw_copper_wires = false,
  draw_circuit_wires = false,
  flags = {
    "not-selectable-in-game",
    "not-deconstructable",
    "not-blueprintable",
    "placeable-off-grid",
    "not-on-map",
  },
  hidden = true,
  hidden_in_factoriopedia = true,
  max_health = 1,
}

-- Train Monitor: a combinator that outputs train counts
local monitor_base = data.raw["constant-combinator"]["constant-combinator"]
local monitor = table.deepcopy(monitor_base)
monitor.name = "ata-monitor"
monitor.minable = {mining_time = 0.5, result = "ata-monitor"}
monitor.max_health = 150
monitor.icon = "__base__/graphics/icons/constant-combinator.png"
monitor.icon_size = 64
monitor.flags = {"placeable-neutral", "player-creation"}
monitor.order = "z[auto-train-adder]-b[monitor]"

data:extend({deployer, deployer_chest, deployer_output, monitor})
