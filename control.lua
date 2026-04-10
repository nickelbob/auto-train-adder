local Constants = require("scripts.constants")
local Deployer = require("scripts.deployer")
local Monitor = require("scripts.monitor")
local Templates = require("scripts.templates")
local Gui = require("scripts.gui")
local Log = require("scripts.logger")

--- Initialize storage on new game or when mod is added.
local function init_storage()
  storage.deployers = storage.deployers or {}
  storage.monitors = storage.monitors or {}
  storage.templates = storage.templates or {}
  storage.monitor_cache = storage.monitor_cache or nil
  storage.next_template_id = storage.next_template_id or 1
  Log.clear()
  Log.log("Storage initialized. deployers=" .. table_size(storage.deployers) .. " templates=" .. table_size(storage.templates))
end

---------------------------------------------------------------------------
-- Entity build/destroy lifecycle
---------------------------------------------------------------------------

local function on_entity_built(event)
  local entity = event.entity or event.destination
  if not entity or not entity.valid then return end

  if entity.name == Constants.DEPLOYER_NAME then
    -- Deployer is a train stop. Create co-located chest + output combinator.
    local surface = entity.surface
    local position = entity.position
    local force = entity.force

    local chest = surface.create_entity{
      name = Constants.DEPLOYER_CHEST_NAME,
      position = position,
      force = force,
      raise_built = false,
    }

    local output = surface.create_entity{
      name = Constants.DEPLOYER_OUTPUT_NAME,
      position = position,
      force = force,
      raise_built = false,
    }

    if chest and output then
      chest.destructible = false
      output.destructible = false

      -- Wire the output combinator to the train stop so signals show on its connections
      local deployer_red = entity.get_wire_connector(defines.wire_connector_id.circuit_red, true)
      local deployer_green = entity.get_wire_connector(defines.wire_connector_id.circuit_green, true)
      local output_red = output.get_wire_connector(defines.wire_connector_id.circuit_red, true)
      local output_green = output.get_wire_connector(defines.wire_connector_id.circuit_green, true)
      if deployer_red and output_red then
        deployer_red.connect_to(output_red, false)
      end
      if deployer_green and output_green then
        deployer_green.connect_to(output_green, false)
      end

      Deployer.create(entity, chest, output)
    end

  elseif entity.name == Constants.MONITOR_NAME then
    Monitor.create(entity)
  end
end

local function on_entity_destroyed(event)
  local entity = event.entity
  if not entity or not entity.valid then return end

  if entity.name == Constants.DEPLOYER_NAME then
    Deployer.destroy(entity.unit_number)
  elseif entity.name == Constants.MONITOR_NAME then
    Monitor.destroy(entity.unit_number)
  end
end

-- Entity build events
local build_filter = {
  {filter = "name", name = Constants.DEPLOYER_NAME},
  {filter = "name", name = Constants.MONITOR_NAME},
}

script.on_event(defines.events.on_built_entity, on_entity_built, build_filter)
script.on_event(defines.events.on_robot_built_entity, on_entity_built, build_filter)
script.on_event(defines.events.script_raised_built, on_entity_built, build_filter)
script.on_event(defines.events.on_entity_cloned, on_entity_built, build_filter)

-- Entity destroy events
local destroy_filter = {
  {filter = "name", name = Constants.DEPLOYER_NAME},
  {filter = "name", name = Constants.MONITOR_NAME},
}

script.on_event(defines.events.on_pre_player_mined_item, on_entity_destroyed, destroy_filter)
script.on_event(defines.events.on_robot_pre_mined, on_entity_destroyed, destroy_filter)
script.on_event(defines.events.on_entity_died, on_entity_destroyed, destroy_filter)
script.on_event(defines.events.script_raised_destroy, on_entity_destroyed, destroy_filter)

---------------------------------------------------------------------------
-- Tick handlers
---------------------------------------------------------------------------

--- Deployer demand check: runs every deployer-update-rate ticks (default 30 sec).
local demand_counter = 0
local function tick_deployer_demand()
  demand_counter = demand_counter + 1
  Log.log("DEMAND_TICK #" .. demand_counter .. " deployers=" .. table_size(storage.deployers))

  for unit_number, data in pairs(storage.deployers) do
    if data.entity and data.entity.valid then
      Deployer.read_circuit_demand(data)
    else
      Log.log("Deployer " .. unit_number .. " invalid, removing")
      storage.deployers[unit_number] = nil
    end
  end
end

--- Deployer build tick: runs every 10 ticks (fast) to process the state machine.
local build_counter = 0
local function tick_deployer_build()
  build_counter = build_counter + 1

  for unit_number, data in pairs(storage.deployers) do
    if data.entity and data.entity.valid then
      -- Only log when something is happening
      if data.build_state.state ~= Constants.BUILD_STATE.IDLE or #data.deploy_queue > 0 then
        Log.log("BUILD_TICK #" .. build_counter .. " deployer=" .. unit_number .. " state=" .. data.build_state.state .. " queue=" .. #data.deploy_queue)
      end
      Deployer.tick(data)
    end
  end
end

--- Monitor tick: refresh cache and update outputs.
local function tick_monitors()
  if next(storage.monitors) then
    Monitor.tick_all()
  end
end

-- Register nth_tick handlers using settings
local BUILD_TICK_RATE = 10  -- state machine ticks every 10 game ticks

local function register_tick_handlers()
  local demand_rate = settings.global["ata-deployer-update-rate"].value
  local monitor_rate = settings.global["ata-monitor-update-rate"].value

  script.on_nth_tick(nil)  -- Clear all nth_tick handlers

  -- Build a table of rate -> list of functions, then register combined handlers
  local handlers = {}
  local function add(rate, fn)
    if not handlers[rate] then handlers[rate] = {} end
    handlers[rate][#handlers[rate] + 1] = fn
  end

  add(BUILD_TICK_RATE, tick_deployer_build)
  add(demand_rate, tick_deployer_demand)
  add(monitor_rate, tick_monitors)

  for rate, fns in pairs(handlers) do
    if #fns == 1 then
      script.on_nth_tick(rate, fns[1])
    else
      script.on_nth_tick(rate, function()
        for _, fn in ipairs(fns) do fn() end
      end)
    end
  end
end

-- Combined init: storage + tick handlers
local function on_init()
  init_storage()
  register_tick_handlers()
end

local function on_configuration_changed()
  init_storage()
  register_tick_handlers()
end

script.on_init(on_init)
script.on_configuration_changed(on_configuration_changed)
script.on_load(register_tick_handlers)

script.on_event(defines.events.on_runtime_mod_setting_changed, function(event)
  if event.setting == "ata-deployer-update-rate" or event.setting == "ata-monitor-update-rate" then
    register_tick_handlers()
  end
end)

---------------------------------------------------------------------------
-- GUI events
---------------------------------------------------------------------------

--- Open GUI when player opens a deployer or monitor entity.
script.on_event(defines.events.on_gui_opened, function(event)
  if event.gui_type ~= defines.gui_type.entity then return end

  local entity = event.entity
  if not entity or not entity.valid then return end

  local player = game.get_player(event.player_index)
  if not player then return end

  if entity.name == Constants.DEPLOYER_NAME then
    local data = storage.deployers[entity.unit_number]
    if data then
      Gui.open_deployer(player, data)
    end
  elseif entity.name == Constants.DEPLOYER_CHEST_NAME then
    -- Player clicked the co-located chest — find the deployer it belongs to
    for _, data in pairs(storage.deployers) do
      if data.chest and data.chest.valid and data.chest.unit_number == entity.unit_number then
        Gui.open_deployer(player, data)
        break
      end
    end
  elseif entity.name == Constants.MONITOR_NAME then
    local data = storage.monitors[entity.unit_number]
    if data then
      Gui.open_monitor(player, data)
    end
  end
end)

script.on_event(defines.events.on_gui_closed, function(event)
  local player = game.get_player(event.player_index)
  if not player then return end

  -- ONLY react to our own custom frames being closed (via Escape/E)
  -- Never react to entity GUI closes — they cascade and destroy our frame
  local element = event.element
  if element and element.valid then
    if element.name == "ata-deployer-frame" or element.name == "ata-monitor-frame" then
      Gui.close_all(player)
    end
  end
end)

script.on_event(defines.events.on_gui_click, function(event)
  Gui.on_gui_click(event)
end)

script.on_event(defines.events.on_gui_selection_state_changed, function(event)
  Gui.on_gui_selection_state_changed(event)
end)
