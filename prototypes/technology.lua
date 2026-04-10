data:extend({
  {
    type = "technology",
    name = "ata-auto-train-deployment",
    icon = "__base__/graphics/technology/automated-rail-transportation.png",
    icon_size = 256,
    effects = {
      {type = "unlock-recipe", recipe = "ata-deployer"},
      {type = "unlock-recipe", recipe = "ata-monitor"},
    },
    prerequisites = {"automated-rail-transportation", "circuit-network"},
    unit = {
      count = 200,
      ingredients = {
        {"automation-science-pack", 1},
        {"logistic-science-pack", 1},
      },
      time = 30,
    },
    order = "c-g-c",
  },
})
