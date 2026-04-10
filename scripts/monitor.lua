local Constants = require("scripts.constants")

local Monitor = {}

--- Initialize a new monitor's data structure.
function Monitor.create(monitor_entity)
  local data = {
    entity = monitor_entity,
    unit_number = monitor_entity.unit_number,
  }
  storage.monitors[monitor_entity.unit_number] = data
  return data
end

--- Remove a monitor.
function Monitor.destroy(unit_number)
  storage.monitors[unit_number] = nil
end

--- Compute a layout hash for a train based on its carriage composition (e.g. "L-C-C-C").
function Monitor.layout_hash(train)
  if not train or not train.valid then return nil end

  local carriages = train.carriages
  if not carriages or #carriages == 0 then return nil end

  local parts = {}
  for _, carriage in ipairs(carriages) do
    if carriage.type == "locomotive" then
      parts[#parts + 1] = "L"
    elseif carriage.name == "cargo-wagon" then
      parts[#parts + 1] = "C"
    elseif carriage.name == "fluid-wagon" then
      parts[#parts + 1] = "F"
    elseif carriage.name == "artillery-wagon" then
      parts[#parts + 1] = "A"
    else
      parts[#parts + 1] = "?"
    end
  end
  return table.concat(parts, "-")
end

--- Check if a station name matches any depot pattern in the setting.
local function is_depot_name(name)
  if not name then return false end
  local setting = settings.global["ata-depot-pattern"]
  if not setting then return false end
  local patterns_str = setting.value
  for pattern in string.gmatch(patterns_str, "[^,]+") do
    pattern = pattern:match("^%s*(.-)%s*$")  -- trim whitespace
    if #pattern > 0 and string.find(name, pattern, 1, true) then
      return true
    end
  end
  return false
end

--- Check if a train is at or heading to a depot station.
function Monitor.is_depot_bound(train)
  -- At a depot station
  if train.state == defines.train_state.wait_station then
    local station = train.station
    if station and station.valid and is_depot_name(station.backer_name) then
      return true
    end
  end

  -- Heading to a depot station
  local dest = train.path_end_stop
  if dest and dest.valid and is_depot_name(dest.backer_name) then
    return true
  end

  return false
end

--- Check if a train is "in use" (not idle/heading to a depot).
--- Depot-bound trains, manual trains, and no-schedule trains count as idle.
function Monitor.is_running(train)
  if not train or not train.valid then return false end
  if train.manual_mode then return false end
  local state = train.state
  if state == defines.train_state.no_schedule then return false end
  return not Monitor.is_depot_bound(train)
end

--- Refresh the shared train count cache with totals and running counts.
function Monitor.refresh_cache()
  local cache = {
    last_update_tick = game.tick,
    type_data = {},        -- {[layout_hash] = {total=N, running=N}}
    ordered_types = {},    -- sorted list of layout hashes for deterministic signal assignment
    total_trains = 0,
  }

  local trains = game.train_manager.get_trains({})

  for _, train in ipairs(trains) do
    if train.valid then
      cache.total_trains = cache.total_trains + 1

      local sh = Monitor.layout_hash(train)
      if sh then
        if not cache.type_data[sh] then
          cache.type_data[sh] = {total = 0, running = 0}
        end
        cache.type_data[sh].total = cache.type_data[sh].total + 1

        if Monitor.is_running(train) then
          cache.type_data[sh].running = cache.type_data[sh].running + 1
        end
      end
    end
  end

  -- Preserve stable signal assignment: existing types keep their index,
  -- new types are appended to the end.
  local known = storage.monitor_type_order or {}

  -- Add any new types to the end
  for hash, _ in pairs(cache.type_data) do
    local found = false
    for _, k in ipairs(known) do
      if k == hash then found = true; break end
    end
    if not found then
      known[#known + 1] = hash
    end
  end

  storage.monitor_type_order = known
  cache.ordered_types = known

  storage.monitor_cache = cache
  return cache
end

--- Process one tick for all monitors.
function Monitor.tick_all()
  local cache = Monitor.refresh_cache()

  for unit_number, data in pairs(storage.monitors) do
    if data.entity and data.entity.valid then
      Monitor.update_output(data, cache)
    else
      storage.monitors[unit_number] = nil
    end
  end
end

--- Update a monitor's output signals: counts on signal-0..9, utilization on signal-A..J.
function Monitor.update_output(data, cache)
  local entity = data.entity
  if not entity or not entity.valid then return end

  local cb = entity.get_or_create_control_behavior()
  if not cb then return end

  -- Ensure we have a section
  if cb.sections_count == 0 then
    cb.add_section()
  end
  local section = cb.get_section(1)

  -- Clear all slots
  local max_slots = Constants.MAX_MONITOR_TYPES * 2
  for i = 1, max_slots do
    section.clear_slot(i)
  end

  local slot = 1
  for idx, layout_hash in ipairs(cache.ordered_types) do
    if idx > Constants.MAX_MONITOR_TYPES then break end

    local td = cache.type_data[layout_hash]
    local count = td and td.total or 0
    local utilization = 0
    if td and count > 0 then
      utilization = math.floor((td.running / count) * 100 + 0.5)
    end

    -- Count signal (signal-0 through signal-9)
    section.set_slot(slot, {
      value = {type = "virtual", name = Constants.COUNT_SIGNALS[idx], quality = "normal"},
      min = count,
    })
    slot = slot + 1

    -- Utilization signal (signal-A through signal-J)
    section.set_slot(slot, {
      value = {type = "virtual", name = Constants.UTIL_SIGNALS[idx], quality = "normal"},
      min = utilization,
    })
    slot = slot + 1
  end
end

return Monitor
