data:extend({
  {
    type = "recipe",
    name = "ata-deployer",
    enabled = true,
    ingredients = {
      {type = "item", name = "train-stop", amount = 1},
      {type = "item", name = "electronic-circuit", amount = 10},
      {type = "item", name = "iron-chest", amount = 1},
    },
    results = {{type = "item", name = "ata-deployer", amount = 1}},
    energy_required = 2,
  },
  {
    type = "recipe",
    name = "ata-monitor",
    enabled = true,
    ingredients = {
      {type = "item", name = "constant-combinator", amount = 1},
      {type = "item", name = "electronic-circuit", amount = 5},
    },
    results = {{type = "item", name = "ata-monitor", amount = 1}},
    energy_required = 1,
  },
})
