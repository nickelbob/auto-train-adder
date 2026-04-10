data:extend({
  {
    type = "item",
    name = "ata-deployer",
    icon = "__base__/graphics/icons/train-stop.png",
    icon_size = 64,
    subgroup = "train-transport",
    order = "z[auto-train-adder]-a[deployer]",
    place_result = "ata-deployer",
    stack_size = 10,
  },
  {
    type = "item",
    name = "ata-monitor",
    icon = "__base__/graphics/icons/constant-combinator.png",
    icon_size = 64,
    subgroup = "circuit-network",
    order = "z[auto-train-adder]-b[monitor]",
    place_result = "ata-monitor",
    stack_size = 50,
  },
})
