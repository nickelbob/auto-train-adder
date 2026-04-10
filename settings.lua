data:extend({
  {
    type = "int-setting",
    name = "ata-deployer-update-rate",
    setting_type = "runtime-global",
    default_value = 1800,
    minimum_value = 60,
    maximum_value = 18000,
    order = "a",
  },
  {
    type = "int-setting",
    name = "ata-monitor-update-rate",
    setting_type = "runtime-global",
    default_value = 60,
    minimum_value = 10,
    maximum_value = 600,
    order = "b",
  },
  {
    type = "string-setting",
    name = "ata-depot-pattern",
    setting_type = "runtime-global",
    default_value = "depot,D",
    order = "c",
  },
})
