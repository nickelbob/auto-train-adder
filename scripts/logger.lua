local Logger = {}

local LOG_FILE = "auto-train-adder.log"

local function is_enabled()
  return settings and settings.global and
    settings.global["ata-debug-logging"] and
    settings.global["ata-debug-logging"].value
end

local function write(text, append)
  if helpers and helpers.write_file then
    helpers.write_file(LOG_FILE, text, append)
  elseif game and game.write_file then
    game.write_file(LOG_FILE, text, append)
  end
end

function Logger.clear()
  if not is_enabled() then return end
  write("=== Auto Train Adder Log Started at tick " .. game.tick .. " ===\n", false)
end

function Logger.log(msg)
  if not is_enabled() then return end
  local tick = game and game.tick or 0
  write("[tick " .. tick .. "] " .. tostring(msg) .. "\n", true)
end

function Logger.log_table(label, t)
  if not is_enabled() then return end
  Logger.log(label .. ": " .. serpent.block(t))
end

return Logger
