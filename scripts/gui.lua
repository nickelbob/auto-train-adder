local Constants = require("scripts.constants")
local Templates = require("scripts.templates")
local Monitor = require("scripts.monitor")

local Gui = {}

local DEPLOYER_FRAME = "ata-deployer-frame"
local MONITOR_FRAME = "ata-monitor-frame"

--- Open the deployer GUI for a player.
function Gui.open_deployer(player, deployer_data)
  Gui.close_all(player)

  local frame = player.gui.screen.add{
    type = "frame",
    name = DEPLOYER_FRAME,
    direction = "vertical",
    caption = "Train Deployer",
  }
  frame.auto_center = true

  -- Tags to track which deployer this GUI is for
  frame.tags = {unit_number = deployer_data.unit_number}

  -- Status section
  local status_flow = frame.add{type = "flow", direction = "horizontal"}
  local bs = deployer_data.build_state
  local status_text = "Idle"
  if bs.state == Constants.BUILD_STATE.PLACE_CARRIAGE then
    status_text = "Building train... (" .. bs.carriage_index .. " carriages placed)"
  elseif bs.state == Constants.BUILD_STATE.VALIDATE then
    status_text = "Validating..."
  elseif bs.state == Constants.BUILD_STATE.FINALIZE then
    status_text = "Finalizing train..."
  elseif bs.state == Constants.BUILD_STATE.ERROR then
    status_text = "Error: " .. (bs.error_message or "unknown")
  end
  status_flow.add{type = "label", caption = "Status: " .. status_text}

  frame.add{type = "line"}

  -- Read template signal values directly from the circuit network
  local active_template_signals = {}
  local entity = deployer_data.entity
  if entity and entity.valid then
    local red_net = entity.get_circuit_network(defines.wire_connector_id.circuit_red)
    local green_net = entity.get_circuit_network(defines.wire_connector_id.circuit_green)
    for i = 1, Constants.MAX_TEMPLATES do
      local sig = {type = "virtual", name = Constants.TEMPLATE_SIGNAL_PREFIX .. i}
      local val = 0
      if red_net then val = val + (red_net.get_signal(sig) or 0) end
      if green_net then val = val + (green_net.get_signal(sig) or 0) end
      if val ~= 0 then
        active_template_signals[i] = val
      end
    end
  end

  frame.add{type = "line"}

  -- Template section
  frame.add{type = "label", caption = "Templates", style = "heading_2_label"}
  frame.add{type = "label", caption = "Send positive ata-template-N signal to deploy one train per cycle."}

  local template_table = frame.add{
    type = "table",
    name = "ata-template-table",
    column_count = 5,
  }
  template_table.add{type = "label", caption = "Signal", style = "bold_label"}
  template_table.add{type = "label", caption = "Name", style = "bold_label"}
  template_table.add{type = "label", caption = "Layout", style = "bold_label"}
  template_table.add{type = "label", caption = "Active", style = "bold_label"}
  template_table.add{type = "label", caption = "", style = "bold_label"}

  for _, template in pairs(storage.templates) do
    template_table.add{type = "label", caption = "[virtual-signal=" .. template.signal.name .. "]"}
    template_table.add{type = "label", caption = template.name}
    template_table.add{type = "label", caption = Templates.layout_string(template)}

    -- Show if this template's signal is active
    local sig_val = active_template_signals[template.signal_index]
    if sig_val then
      local active_label = template_table.add{type = "label", caption = ">>> " .. sig_val .. " <<<"}
      active_label.style.font_color = {0, 1, 0}  -- green
    else
      template_table.add{type = "label", caption = "-"}
    end

    local del_btn = template_table.add{
      type = "button",
      name = "ata-delete-template-" .. template.template_id,
      caption = "X",
      style = "red_button",
      tooltip = "Delete this template",
    }
    del_btn.tags = {action = "delete_template", template_id = template.template_id}
  end

  frame.add{type = "line"}

  -- Save template section
  frame.add{type = "label", caption = "Save New Template", style = "heading_2_label"}
  frame.add{type = "label", caption = "Park a train at this stop, then click Save."}

  local save_flow = frame.add{type = "flow", direction = "horizontal"}
  save_flow.add{type = "label", caption = "Name:"}
  save_flow.add{
    type = "textfield",
    name = "ata-template-name",
    text = "Template " .. storage.next_template_id,
  }
  save_flow.add{type = "label", caption = "Signal #:"}
  -- Build dropdown items showing which slots are taken
  local dropdown_items = {}
  local first_free = 1
  for i = 1, Constants.MAX_TEMPLATES do
    local existing = Templates.get_by_signal_index(i)
    if existing then
      dropdown_items[i] = tostring(i) .. " (used: " .. existing.name .. ")"
    else
      dropdown_items[i] = tostring(i)
      if first_free == i - 1 + 1 then first_free = i end  -- track first available
    end
  end
  -- Find actual first free slot
  first_free = 1
  for i = 1, Constants.MAX_TEMPLATES do
    if not Templates.get_by_signal_index(i) then
      first_free = i
      break
    end
  end
  save_flow.add{
    type = "drop-down",
    name = "ata-signal-index",
    items = dropdown_items,
    selected_index = first_free,
  }
  save_flow.add{
    type = "button",
    name = "ata-save-template",
    caption = "Save Template",
    style = "confirm_button",
  }

  -- Inventory contents
  frame.add{type = "line"}
  frame.add{type = "label", caption = "Deployer Inventory", style = "heading_2_label"}
  if deployer_data.chest and deployer_data.chest.valid then
    local inv = deployer_data.chest.get_inventory(defines.inventory.chest)
    if inv then
      local contents = inv.get_contents()
      if #contents == 0 then
        frame.add{type = "label", caption = "Empty — insert items via inserter or manually"}
      else
        local inv_flow = frame.add{type = "table", column_count = 5}
        for _, item in ipairs(contents) do
          inv_flow.add{
            type = "sprite-button",
            sprite = "item/" .. item.name,
            number = item.count,
            tooltip = item.name .. " x" .. item.count,
            enabled = false,
            style = "slot_button",
          }
        end
      end
    end
  end

  -- Queue info
  frame.add{type = "line"}
  frame.add{type = "label", caption = "Deploy queue: " .. #deployer_data.deploy_queue}

  -- Take over the GUI
  player.opened = frame
end

--- Open the monitor GUI for a player.
function Gui.open_monitor(player, monitor_data)
  Gui.close_all(player)

  local frame = player.gui.screen.add{
    type = "frame",
    name = MONITOR_FRAME,
    direction = "vertical",
    caption = "Train Monitor",
  }
  frame.auto_center = true
  frame.tags = {unit_number = monitor_data.unit_number}

  frame.add{type = "label", caption = "Auto-discovered train types and circuit signals.", style = "heading_2_label"}
  frame.add{type = "label", caption = "Counts on signal-0..9, Utilization % on signal-A..J"}

  local cache = storage.monitor_cache
  if not cache then cache = Monitor.refresh_cache() end

  if #cache.ordered_types == 0 then
    frame.add{type = "label", caption = "No trains found."}
  else
    local t = frame.add{type = "table", name = "ata-monitor-table", column_count = 6}
    -- Header
    t.add{type = "label", caption = "#"}
    t.add{type = "label", caption = "Signals"}
    t.add{type = "label", caption = "Type"}
    t.add{type = "label", caption = "Total"}
    t.add{type = "label", caption = "Running"}
    t.add{type = "label", caption = "Util %"}

    for idx, hash in ipairs(cache.ordered_types) do
      if idx > Constants.MAX_MONITOR_TYPES then break end
      local td = cache.type_data[hash]
      local total = td and td.total or 0
      local running = td and td.running or 0
      local util = total > 0 and math.floor((running / total) * 100 + 0.5) or 0

      t.add{type = "label", caption = tostring(idx)}
      t.add{type = "label", caption = "[virtual-signal=" .. Constants.COUNT_SIGNALS[idx] .. "] / [virtual-signal=" .. Constants.UTIL_SIGNALS[idx] .. "]"}
      t.add{type = "label", caption = hash}
      t.add{type = "label", caption = tostring(total)}
      t.add{type = "label", caption = tostring(running)}
      t.add{type = "label", caption = tostring(util) .. "%"}
    end

    if #cache.ordered_types > Constants.MAX_MONITOR_TYPES then
      frame.add{type = "label", caption = (#cache.ordered_types - Constants.MAX_MONITOR_TYPES) .. " additional train types not shown (max 10 signals)."}
    end
  end

  frame.add{type = "line"}
  frame.add{type = "button", name = "ata-monitor-refresh", caption = "Refresh"}

  player.opened = frame
end

--- Close all ATA GUIs for a player.
function Gui.close_all(player)
  if player.gui.screen[DEPLOYER_FRAME] then
    player.gui.screen[DEPLOYER_FRAME].destroy()
  end
  if player.gui.screen[MONITOR_FRAME] then
    player.gui.screen[MONITOR_FRAME].destroy()
  end
end

--- Handle GUI click events.
function Gui.on_gui_click(event)
  local element = event.element
  if not element or not element.valid then return end

  local player = game.get_player(event.player_index)
  if not player then return end

  local name = element.name

  -- Save template button
  if name == "ata-save-template" then
    local frame = player.gui.screen[DEPLOYER_FRAME]
    if not frame then return end

    local unit_number = frame.tags.unit_number
    local deployer_data = storage.deployers[unit_number]
    if not deployer_data or not deployer_data.entity.valid then return end

    -- Get the train at the stop or find nearby rolling stock
    local train = deployer_data.entity.get_stopped_train()
    if not train then
      local search_pos = deployer_data.entity.position
      local surface = deployer_data.entity.surface
      local nearby = surface.find_entities_filtered{
        position = search_pos,
        radius = 10,
        type = {"locomotive", "cargo-wagon", "fluid-wagon", "artillery-wagon"},
        limit = 1,
      }
      if nearby and #nearby > 0 then
        train = nearby[1].train
      end
    end
    if not train then
      player.print("[Auto Train Adder] No train found. Drive or schedule a train to this stop first.")
      return
    end

    local name_field = frame["ata-template-name"]
       or Gui.find_child(frame, "ata-template-name")
    local signal_dropdown = frame["ata-signal-index"]
       or Gui.find_child(frame, "ata-signal-index")

    local template_name = name_field and name_field.text or ("Template " .. storage.next_template_id)
    local signal_index = signal_dropdown and signal_dropdown.selected_index or 1

    -- Check if signal slot is already taken
    local existing = Templates.get_by_signal_index(signal_index)
    if existing then
      player.print("[Auto Train Adder] Signal slot " .. signal_index .. " is already used by template '" .. existing.name .. "'. Delete it first or pick another slot.")
      return
    end

    local template, err = Templates.save_from_train(train, template_name, signal_index)
    if template then
      player.print("[Auto Train Adder] Template '" .. template.name .. "' saved as " .. Templates.layout_string(template))
      Gui.open_deployer(player, deployer_data)  -- Refresh
    else
      player.print("[Auto Train Adder] Error: " .. (err or "unknown"))
    end
    return
  end

  -- Delete template button
  local tags = element.tags
  if tags and tags.action == "delete_template" then
    Templates.delete(tags.template_id)
    player.print("[Auto Train Adder] Template deleted.")

    local frame = player.gui.screen[DEPLOYER_FRAME]
    if frame then
      local unit_number = frame.tags.unit_number
      local deployer_data = storage.deployers[unit_number]
      if deployer_data then
        Gui.open_deployer(player, deployer_data)  -- Refresh
      end
    end
    return
  end

  -- Monitor refresh button
  if name == "ata-monitor-refresh" then
    local frame = player.gui.screen[MONITOR_FRAME]
    if not frame then return end

    local unit_number = frame.tags.unit_number
    local monitor_data = storage.monitors[unit_number]
    if monitor_data then
      Monitor.refresh_cache()
      Gui.open_monitor(player, monitor_data)  -- Refresh
    end
    return
  end
end

--- Handle dropdown selection changes (no-op after removing manual monitor mapping).
function Gui.on_gui_selection_state_changed(event)
end

--- Recursively find a child element by name.
function Gui.find_child(parent, child_name)
  for _, child in pairs(parent.children) do
    if child.name == child_name then
      return child
    end
    local found = Gui.find_child(child, child_name)
    if found then return found end
  end
  return nil
end

return Gui
