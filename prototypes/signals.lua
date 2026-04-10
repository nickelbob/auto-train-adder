local signals = {}

-- Template signals (1-8): locomotive icon with number overlay
for i = 1, 8 do
  signals[#signals + 1] = {
    type = "virtual-signal",
    name = "ata-template-" .. i,
    icons = {
      {icon = "__base__/graphics/icons/locomotive.png", icon_size = 64},
      {icon = "__base__/graphics/icons/signal/signal_" .. i .. ".png", icon_size = 64, scale = 0.3, shift = {8, -8}},
    },
    subgroup = "virtual-signal-special",
    order = "z[auto-train-adder]-a[template]-" .. string.format("%02d", i),
  }
end

-- Status signal: locomotive icon with red dot
signals[#signals + 1] = {
  type = "virtual-signal",
  name = "ata-status",
  icons = {
    {icon = "__base__/graphics/icons/locomotive.png", icon_size = 64},
    {icon = "__base__/graphics/icons/signal/signal_red.png", icon_size = 64, scale = 0.3, shift = {8, -8}},
  },
  subgroup = "virtual-signal-special",
  order = "z[auto-train-adder]-b[status]-01",
}

data:extend(signals)
