local Constants = require("scripts.constants")
local Templates = require("scripts.templates")
local Log = require("scripts.logger")

local Deployer = {}

--- Initialize a new deployer's data structure.
function Deployer.create(deployer_entity, chest_entity, output_entity)
  local data = {
    entity = deployer_entity,     -- the train stop (visible)
    chest = chest_entity,         -- co-located chest for inserter access
    output = output_entity,       -- hidden combinator for circuit output
    unit_number = deployer_entity.unit_number,
    build_state = {
      state = Constants.BUILD_STATE.IDLE,
      template_id = nil,
      carriage_index = 0,
      entity_refs = {},
      error_cooldown = 0,
      items_consumed = {},
    },
    deploy_queue = {},
  }
  storage.deployers[deployer_entity.unit_number] = data
  return data
end

--- Remove a deployer and clean up.
function Deployer.destroy(unit_number)
  local data = storage.deployers[unit_number]
  if not data then return end

  -- Abort any in-progress build
  if data.build_state.state ~= Constants.BUILD_STATE.IDLE then
    Deployer.abort_build(data)
  end

  -- Destroy companion entities; spill chest contents
  if data.chest and data.chest.valid then
    local inventory = data.chest.get_inventory(defines.inventory.chest)
    if inventory then
      for i = 1, #inventory do
        local stack = inventory[i]
        if stack and stack.valid_for_read then
          data.entity.surface.spill_item_stack{
            position = data.entity.position,
            stack = stack,
            force = data.entity.force,
          }
        end
      end
    end
    data.chest.destroy()
  end

  if data.output and data.output.valid then
    data.output.destroy()
  end

  storage.deployers[unit_number] = nil
end

--- Read circuit network demand signals. If any template signal is positive
--- and the deployer is idle, pick one template at random and queue a single deploy.
function Deployer.read_circuit_demand(data)
  local entity = data.entity
  if not entity.valid then return end

  -- Don't queue new work if we're already building or have work queued
  if data.build_state.state ~= Constants.BUILD_STATE.IDLE then
    Log.log("DEMAND: skip, state=" .. data.build_state.state)
    return
  end
  if #data.deploy_queue > 0 then
    Log.log("DEMAND: skip, queue=" .. #data.deploy_queue)
    return
  end

  local red_network = entity.get_circuit_network(defines.wire_connector_id.circuit_red)
  local green_network = entity.get_circuit_network(defines.wire_connector_id.circuit_green)

  -- Collect all signals on the wire
  local all_signals = {}
  if red_network then
    local sigs = red_network.signals
    if sigs then
      for _, sig in ipairs(sigs) do
        local key = (sig.signal.type or "?") .. "/" .. (sig.signal.name or "?")
        all_signals[key] = (all_signals[key] or 0) + sig.count
      end
    end
  end
  if green_network then
    local sigs = green_network.signals
    if sigs then
      for _, sig in ipairs(sigs) do
        local key = (sig.signal.type or "?") .. "/" .. (sig.signal.name or "?")
        all_signals[key] = (all_signals[key] or 0) + sig.count
      end
    end
  end

  -- Subtract our own output combinator signals to get only incoming signals
  local our_output = {}
  if data.output and data.output.valid then
    local cb = data.output.get_or_create_control_behavior()
    if cb and cb.sections_count > 0 then
      local section = cb.get_section(1)
      for i = 1, 20 do
        local slot = section.get_slot(i)
        if slot and slot.value then
          local key = (slot.value.type or "?") .. "/" .. (slot.value.name or "?")
          our_output[key] = (our_output[key] or 0) + (slot.min or 0)
        end
      end
    end
  end

  local incoming_signals = {}
  for key, count in pairs(all_signals) do
    local net = count - (our_output[key] or 0)
    if net ~= 0 then
      incoming_signals[key] = net
    end
  end
  data._last_signals = incoming_signals  -- cache for GUI display

  -- Collect all templates with a positive signal
  local candidates = {}
  for i = 1, Constants.MAX_TEMPLATES do
    local signal_id = {type = "virtual", name = Constants.TEMPLATE_SIGNAL_PREFIX .. i}
    local value = 0

    if red_network then
      value = value + (red_network.get_signal(signal_id) or 0)
    end
    if green_network then
      value = value + (green_network.get_signal(signal_id) or 0)
    end

    if value > 0 then
      Log.log("DEMAND: signal " .. signal_id.name .. " = " .. value)
      local template = Templates.get_by_signal_index(i)
      if template then
        candidates[#candidates + 1] = template.template_id
        Log.log("DEMAND: template match: id=" .. template.template_id .. " name='" .. template.name .. "'")
      else
        Log.log("DEMAND: no template for signal index " .. i)
      end
    end
  end

  -- Pick one at random and queue a single deploy job
  if #candidates > 0 then
    local chosen = candidates[math.random(1, #candidates)]
    data.deploy_queue = {{template_id = chosen}}
    Log.log("DEMAND: queued template_id=" .. chosen .. " from " .. #candidates .. " candidates")
  else
    Log.log("DEMAND: no positive ata-template-N signals found (looking for virtual/ata-template-1 through virtual/ata-template-8)")
  end
end

--- Process one tick of the deployer's build state machine.
function Deployer.tick(data)
  if not data.entity.valid then return end

  local bs = data.build_state

  if bs.state == Constants.BUILD_STATE.IDLE then
    Deployer.tick_idle(data)
  elseif bs.state == Constants.BUILD_STATE.VALIDATE then
    Deployer.tick_validate(data)
  elseif bs.state == Constants.BUILD_STATE.PLACE_CARRIAGE then
    Deployer.tick_place_carriage(data)
  elseif bs.state == Constants.BUILD_STATE.FINALIZE then
    Deployer.tick_finalize(data)
  elseif bs.state == Constants.BUILD_STATE.ERROR then
    Deployer.tick_error(data)
  end

  Deployer.update_output_signals(data)
end

function Deployer.tick_idle(data)
  if #data.deploy_queue > 0 then
    local job = data.deploy_queue[1]
    Log.log("IDLE -> VALIDATE: starting build for template_id=" .. job.template_id)
    data.build_state.state = Constants.BUILD_STATE.VALIDATE
    data.build_state.template_id = job.template_id
    data.build_state.carriage_index = 0
    data.build_state.entity_refs = {}
    data.build_state.items_consumed = {}
  end
end

--- Send a Factorio alert to all players on the deployer's force.
local function send_alert(data, message)
  for _, player in pairs(game.players) do
    if player.force == data.entity.force then
      player.add_custom_alert(
        data.entity,
        {type = "item", name = "ata-deployer"},
        message,
        true
      )
    end
  end
end

function Deployer.tick_validate(data)
  local bs = data.build_state
  local template = Templates.get(bs.template_id)
  if not template then
    Log.log("VALIDATE: template not found for id=" .. tostring(bs.template_id))
    bs.state = Constants.BUILD_STATE.IDLE
    table.remove(data.deploy_queue, 1)
    return
  end

  Log.log("VALIDATE: template='" .. template.name .. "' layout=" .. Templates.layout_string(template) .. " carriages=" .. #template.layout)

  -- Check chest has all items
  local has_items, missing = Templates.check_inventory(data.chest, template)
  if not has_items then
    Log.log("VALIDATE: missing items")
    local missing_parts = {}
    if missing then
      for item_name, count in pairs(missing) do
        missing_parts[#missing_parts + 1] = count .. "x " .. item_name
      end
    end
    local missing_str = #missing_parts > 0 and table.concat(missing_parts, ", ") or "unknown items"
    send_alert(data, "[ATA] Missing items for '" .. template.name .. "': " .. missing_str)
    bs.state = Constants.BUILD_STATE.ERROR
    bs.error_cooldown = Constants.ERROR_COOLDOWN_TICKS
    bs.error_message = "Missing items: " .. missing_str
    return
  end

  -- Check chest has fuel if template requires it
  if template.fuel_name and template.fuel_count > 0 then
    local inventory = data.chest.get_inventory(defines.inventory.chest)
    local fuel_available = inventory and inventory.get_item_count(template.fuel_name) or 0
    if fuel_available < template.fuel_count then
      local msg = "Missing fuel: need " .. template.fuel_count .. "x " .. template.fuel_name .. " (have " .. fuel_available .. ")"
      send_alert(data, "[ATA] " .. msg)
      bs.state = Constants.BUILD_STATE.ERROR
      bs.error_cooldown = Constants.ERROR_COOLDOWN_TICKS
      bs.error_message = msg
      return
    end
  end

  -- Check rail is clear
  local rail = data.entity.connected_rail
  if not rail then
    bs.state = Constants.BUILD_STATE.ERROR
    bs.error_cooldown = Constants.ERROR_COOLDOWN_TICKS
    bs.error_message = "No connected rail"
    return
  end

  Log.log("VALIDATE -> PLACE_CARRIAGE")
  bs.state = Constants.BUILD_STATE.PLACE_CARRIAGE
  bs.carriage_index = 0
  bs.rail = rail
  bs.rail_direction = data.entity.connected_rail_direction
end

function Deployer.tick_place_carriage(data)
  local bs = data.build_state
  local template = Templates.get(bs.template_id)
  if not template then
    Deployer.abort_build(data)
    return
  end

  bs.carriage_index = bs.carriage_index + 1
  local carriage_def = template.layout[bs.carriage_index]
  if not carriage_def then
    Log.log("PLACE_CARRIAGE: all " .. (bs.carriage_index - 1) .. " carriages placed -> FINALIZE")
    bs.state = Constants.BUILD_STATE.FINALIZE
    return
  end

  Log.log("PLACE_CARRIAGE: placing carriage " .. bs.carriage_index .. "/" .. #template.layout .. " name=" .. carriage_def.name)

  -- Remove item from chest
  if not Templates.remove_carriage_item(data.chest, carriage_def) then
    Log.log("PLACE_CARRIAGE: failed to remove item '" .. carriage_def.name .. "' from chest")
    Deployer.abort_build(data)
    return
  end
  bs.items_consumed[#bs.items_consumed + 1] = {name = carriage_def.name, count = 1}

  local surface = data.entity.surface
  local force = data.entity.force

  if bs.carriage_index == 1 then
    -- Place first carriage at the deployer stop position
    local position = data.entity.position
    Log.log("PLACE_CARRIAGE: first carriage at deployer position " .. serpent.line(position))

    local create_params = {
      name = carriage_def.name,
      position = position,
      force = force,
      raise_built = true,
    }
    if carriage_def.type == "locomotive" or carriage_def.name == "locomotive" then
      create_params.snap_to_train_stop = true
      if template.locomotive_orientation then
        create_params.orientation = template.locomotive_orientation
      end
    end

    local entity = surface.create_entity(create_params)
    if not entity then
      Log.log("PLACE_CARRIAGE: create_entity returned nil!")
      Deployer.abort_build(data)
      return
    end

    Log.log("PLACE_CARRIAGE: created " .. entity.name .. " at " .. serpent.line(entity.position) .. " orientation=" .. entity.orientation)
    bs.entity_refs[bs.carriage_index] = entity
  else
    -- Walk along the rail network from both ends of the train to find placement positions
    local prev = bs.entity_refs[bs.carriage_index - 1]
    if not prev or not prev.valid then
      Deployer.abort_build(data)
      return
    end

    local train = prev.train
    if not train then
      Deployer.abort_build(data)
      return
    end

    local back_end = train.back_end
    local front_end = train.front_end

    -- Collect candidate positions by walking the rail network
    local candidates = {}

    local rail_end_back = back_end.make_copy()
    for step = 1, 10 do
      local moved = rail_end_back.move_natural()
      if not moved then break end
      candidates[#candidates+1] = {pos = rail_end_back.rail.position, label = "back_step" .. step}
    end

    local rail_end_front = front_end.make_copy()
    for step = 1, 10 do
      local moved = rail_end_front.move_natural()
      if not moved then break end
      candidates[#candidates+1] = {pos = rail_end_front.rail.position, label = "front_step" .. step}
    end

    candidates[#candidates+1] = {pos = back_end.rail.position, label = "back_end_rail"}
    candidates[#candidates+1] = {pos = front_end.rail.position, label = "front_end_rail"}

    local placed_entity = nil

    for _, candidate in ipairs(candidates) do
      local test_entity = surface.create_entity{
        name = carriage_def.name,
        position = candidate.pos,
        force = force,
        raise_built = false,
      }

      if test_entity then
        -- Check if it auto-joined the locomotive's train
        local new_train = test_entity.train
        local joined = false
        if new_train then
          for _, c in ipairs(new_train.carriages) do
            if c.unit_number == bs.entity_refs[1].unit_number then
              joined = true
              break
            end
          end
        end

        if joined then
          Log.log("PLACE_CARRIAGE: CONNECTED at " .. candidate.label)
          placed_entity = test_entity
          break
        end

        -- Try manual connect
        local connected = test_entity.connect_rolling_stock(defines.rail_direction.front)
        if not connected then
          connected = test_entity.connect_rolling_stock(defines.rail_direction.back)
        end
        if connected then
          Log.log("PLACE_CARRIAGE: MANUAL-CONNECTED at " .. candidate.label)
          placed_entity = test_entity
          break
        end

        test_entity.destroy()
      end
    end

    if not placed_entity then
      Log.log("PLACE_CARRIAGE: ALL candidates failed. Aborting.")
      Deployer.abort_build(data)
      return
    end

    bs.entity_refs[bs.carriage_index] = placed_entity
  end
end

function Deployer.tick_finalize(data)
  Log.log("FINALIZE: starting")
  local bs = data.build_state
  local template = Templates.get(bs.template_id)

  if not bs.entity_refs[1] or not bs.entity_refs[1].valid then
    Deployer.abort_build(data)
    return
  end

  local train = bs.entity_refs[1].train
  if not train then
    Deployer.abort_build(data)
    return
  end
  Log.log("FINALIZE: train id=" .. train.id .. " carriages=" .. #train.carriages)

  -- Insert fuel into each locomotive
  if template.fuel_name and template.fuel_count > 0 then
    for _, carriage in ipairs(train.carriages) do
      if carriage.type == "locomotive" then
        local fuel_removed = Templates.remove_fuel(data.chest, template.fuel_name, template.fuel_count)
        if fuel_removed > 0 then
          local burner = carriage.burner
          if burner then
            burner.inventory.insert({name = template.fuel_name, count = fuel_removed})
          end
        else
          game.print("[Auto Train Adder] Warning: no " .. template.fuel_name .. " in deployer chest for fuel")
        end
      end
    end
  end

  -- Set schedule
  if template.schedule_records then
    train.schedule = {current = 1, records = template.schedule_records}
  end

  -- Set to automatic mode
  train.manual_mode = false

  -- Console message
  game.print("[Auto Train Adder] Deployed '" .. template.name .. "' (" .. Templates.layout_string(template) .. ")")

  -- Clean up build state
  bs.state = Constants.BUILD_STATE.IDLE
  bs.template_id = nil
  bs.carriage_index = 0
  bs.entity_refs = {}
  bs.items_consumed = {}
  table.remove(data.deploy_queue, 1)
end

function Deployer.tick_error(data)
  local bs = data.build_state
  bs.error_cooldown = bs.error_cooldown - 1
  if bs.error_cooldown <= 0 then
    bs.state = Constants.BUILD_STATE.IDLE
    bs.error_message = nil
  end
end

--- Abort a build in progress, destroying created entities and returning items.
function Deployer.abort_build(data)
  Log.log("ABORT_BUILD: aborting at state=" .. data.build_state.state .. " carriage_index=" .. data.build_state.carriage_index)
  local bs = data.build_state

  -- Destroy any entities we created
  for _, entity in ipairs(bs.entity_refs) do
    if entity and entity.valid then
      entity.destroy()
    end
  end

  -- Return consumed items to chest
  if data.chest and data.chest.valid then
    local inventory = data.chest.get_inventory(defines.inventory.chest)
    if inventory then
      for _, item in ipairs(bs.items_consumed) do
        local inserted = inventory.insert(item)
        if inserted < item.count then
          data.entity.surface.spill_item_stack{
            position = data.entity.position,
            stack = {name = item.name, count = item.count - inserted},
            force = data.entity.force,
          }
        end
      end
    end
  end

  bs.state = Constants.BUILD_STATE.ERROR
  bs.error_cooldown = Constants.ERROR_COOLDOWN_TICKS
  bs.error_message = bs.error_message or "Build failed at carriage " .. bs.carriage_index
  bs.entity_refs = {}
  bs.items_consumed = {}

  if #data.deploy_queue > 0 then
    table.remove(data.deploy_queue, 1)
  end
end

--- Update the hidden output combinator with status and chest inventory signals.
function Deployer.update_output_signals(data)
  if not data.output or not data.output.valid then return end

  local cb = data.output.get_or_create_control_behavior()
  if not cb then return end

  local bs = data.build_state
  local status = Constants.STATUS.IDLE
  if bs.state == Constants.BUILD_STATE.PLACE_CARRIAGE or bs.state == Constants.BUILD_STATE.VALIDATE or bs.state == Constants.BUILD_STATE.FINALIZE then
    status = Constants.STATUS.BUILDING
  elseif bs.state == Constants.BUILD_STATE.ERROR then
    status = Constants.STATUS.ERROR
  end

  if cb.sections_count == 0 then
    cb.add_section()
  end
  local section = cb.get_section(1)

  -- Slot 1: status signal
  section.set_slot(1, {
    value = {type = "virtual", name = Constants.SIGNALS.STATUS, quality = "normal"},
    min = status,
  })

  -- Slots 2+: chest inventory contents
  if data.chest and data.chest.valid then
    local chest_inv = data.chest.get_inventory(defines.inventory.chest)
    if chest_inv then
      local contents = chest_inv.get_contents()
      local slot_index = 2
      for _, item in ipairs(contents) do
        if slot_index > 20 then break end
        section.set_slot(slot_index, {
          value = {type = "item", name = item.name, quality = item.quality or "normal"},
          min = item.count,
        })
        slot_index = slot_index + 1
      end
      -- Clear leftover slots
      for i = slot_index, 20 do
        section.clear_slot(i)
      end
    end
  end
end

return Deployer
