local Constants = require("scripts.constants")
local Log = require("scripts.logger")

local Templates = {}

--- Save a template from a train parked at a deployer stop.
--- @param train LuaTrain The train to copy
--- @param name string User-provided template name
--- @param signal_index number Which ata-template-N signal (1-8)
--- @return table|nil template The saved template, or nil on error
--- @return string|nil error Error message if failed
function Templates.save_from_train(train, name, signal_index)
  if not train or not train.valid then
    return nil, "Invalid train"
  end

  if signal_index < 1 or signal_index > Constants.MAX_TEMPLATES then
    return nil, "Signal index must be 1-" .. Constants.MAX_TEMPLATES
  end

  local carriages = train.carriages
  if not carriages or #carriages == 0 then
    return nil, "Train has no carriages"
  end

  -- Record layout and orientation of first carriage (determines train direction)
  local layout = {}
  local locomotive_orientation = nil
  for i, carriage in ipairs(carriages) do
    layout[i] = {
      name = carriage.name,
      type = carriage.type,
      quality = carriage.quality and carriage.quality.name or "normal",
    }
    if i == 1 then
      locomotive_orientation = carriage.orientation
    end
  end

  -- Record schedule
  local schedule = train.schedule
  local schedule_records = nil
  if schedule then
    schedule_records = schedule.records
  end

  -- Record fuel from the first locomotive
  local fuel_name = nil
  local fuel_count = 0
  for _, carriage in ipairs(carriages) do
    if carriage.type == "locomotive" then
      local burner = carriage.burner
      if burner then
        local fuel_inventory = burner.inventory
        if fuel_inventory and not fuel_inventory.is_empty() then
          local contents = fuel_inventory.get_contents()
          for _, item in ipairs(contents) do
            fuel_name = item.name
            fuel_count = item.count
            break
          end
        end
      end
      break
    end
  end

  local template_id = storage.next_template_id
  storage.next_template_id = template_id + 1

  local template = {
    template_id = template_id,
    name = name or ("Template " .. template_id),
    layout = layout,
    schedule_records = schedule_records,
    locomotive_orientation = locomotive_orientation,
    fuel_name = fuel_name,
    fuel_count = fuel_count,
    signal = {type = "virtual", name = Constants.TEMPLATE_SIGNAL_PREFIX .. signal_index},
    signal_index = signal_index,
  }

  storage.templates[template_id] = template
  Log.log("TEMPLATE SAVED: id=" .. template_id .. " name='" .. template.name .. "' signal_index=" .. signal_index)
  Log.log_table("TEMPLATE layout", layout)
  Log.log_table("TEMPLATE schedule_records", schedule_records)
  Log.log("TEMPLATE fuel: " .. tostring(fuel_name) .. " x" .. tostring(fuel_count))
  return template, nil
end

--- Delete a template by ID.
function Templates.delete(template_id)
  storage.templates[template_id] = nil
end

--- Get a template by its signal index (1-8).
function Templates.get_by_signal_index(signal_index)
  for _, template in pairs(storage.templates) do
    if template.signal_index == signal_index then
      return template
    end
  end
  return nil
end

--- Get a template by ID.
function Templates.get(template_id)
  return storage.templates[template_id]
end

--- Get all templates.
function Templates.get_all()
  return storage.templates
end

--- Build a short layout string like "L-CCCC" for display.
function Templates.layout_string(template)
  local parts = {}
  for _, carriage in ipairs(template.layout) do
    local t = carriage.type or carriage.name
    if t == "locomotive" then
      parts[#parts + 1] = "L"
    elseif t == "cargo-wagon" then
      parts[#parts + 1] = "C"
    elseif t == "fluid-wagon" then
      parts[#parts + 1] = "F"
    elseif t == "artillery-wagon" then
      parts[#parts + 1] = "A"
    else
      parts[#parts + 1] = "?"
    end
  end
  return table.concat(parts, "-")
end

--- Check if a chest inventory has all items needed for a template.
--- @return boolean has_items
--- @return table|nil missing {name=count} of missing items
function Templates.check_inventory(chest, template)
  -- Count required items
  local required = {}
  for _, carriage in ipairs(template.layout) do
    required[carriage.name] = (required[carriage.name] or 0) + 1
  end

  local inventory = chest.get_inventory(defines.inventory.chest)
  if not inventory then
    return false, required
  end

  local missing = {}
  local has_all = true
  for item_name, count in pairs(required) do
    local available = inventory.get_item_count(item_name)
    if available < count then
      missing[item_name] = count - available
      has_all = false
    end
  end

  return has_all, has_all and nil or missing
end

--- Remove one carriage item from the chest.
--- @return boolean success
function Templates.remove_carriage_item(chest, carriage_def)
  local inventory = chest.get_inventory(defines.inventory.chest)
  if not inventory then return false end

  local removed = inventory.remove({name = carriage_def.name, count = 1})
  return removed > 0
end

--- Remove fuel items from the chest for a locomotive.
--- @return number amount actually removed
function Templates.remove_fuel(chest, fuel_name, fuel_count)
  if not fuel_name or fuel_count <= 0 then return 0 end

  local inventory = chest.get_inventory(defines.inventory.chest)
  if not inventory then return 0 end

  return inventory.remove({name = fuel_name, count = fuel_count})
end

return Templates
