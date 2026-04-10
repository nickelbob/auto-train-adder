local Constants = {}

-- Entity names
Constants.DEPLOYER_NAME = "ata-deployer"
Constants.DEPLOYER_CHEST_NAME = "ata-deployer-chest"
Constants.DEPLOYER_OUTPUT_NAME = "ata-deployer-output"
Constants.MONITOR_NAME = "ata-monitor"

-- Build states
Constants.BUILD_STATE = {
  IDLE = "idle",
  VALIDATE = "validate",
  PLACE_CARRIAGE = "place_carriage",
  FINALIZE = "finalize",
  ERROR = "error",
}

-- Status signal values
Constants.STATUS = {
  IDLE = 0,
  BUILDING = 1,
  ERROR = 2,
}

-- Signal names
Constants.SIGNALS = {
  STATUS = "ata-status",
}

-- Template signal prefix
Constants.TEMPLATE_SIGNAL_PREFIX = "ata-template-"
Constants.MAX_TEMPLATES = 8

-- Monitor: auto-assigned signal names for up to 10 train types
Constants.MAX_MONITOR_TYPES = 10
Constants.COUNT_SIGNALS = {
  "signal-0", "signal-1", "signal-2", "signal-3", "signal-4",
  "signal-5", "signal-6", "signal-7", "signal-8", "signal-9",
}
Constants.UTIL_SIGNALS = {
  "signal-A", "signal-B", "signal-C", "signal-D", "signal-E",
  "signal-F", "signal-G", "signal-H", "signal-I", "signal-J",
}

-- Approximate distance between carriage centers on a rail (in tiles)
Constants.CARRIAGE_SPACING = 7

-- Ticks to wait after an error before retrying
Constants.ERROR_COOLDOWN_TICKS = 60

return Constants
