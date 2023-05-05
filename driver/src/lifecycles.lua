local commands = require('commands')
local config = require('config')
local log = require('log')

local function update_device(driver, device)
  log.info('===== UPDATING DEVICE...')
  -- device metadata table
  local metadata = {
    profile = config.DEVICE_PROFILE,
    manufacturer = 'Goguma electronics',
    model = 'Goguma light',
    vendor_provided_label = 'Goguma light Device'
  }
  -- return driver:try_create_device(metadata)
  return device:try_update_metadata(metadata)
end

local function create_device(driver)
  date = os.date('%x')
  time = os.date('%X')

  local metadata = {
    type = config.DEVICE_TYPE,
    -- the DNI must be unique across your hub, using static ID here so that we
    -- only ever have a single instance of this "device"
    device_network_id = "home-light-controller-1"..'-'..date..'-'..time,
    label = "Goguma Home Light Controller",
    profile = config.DEVICE_PROFILE,
    manufacturer = 'Goguma electronics',
    model = 'Goguma light',
    vendor_provided_label = 'Goguma light Device'
  }

  -- tell the cloud to create a new device record, will get synced back down
  -- and `device_added` and `device_init` callbacks will be called
  return driver:try_create_device(metadata)
end

local lifecycle_handler = {}

function lifecycle_handler.init(driver, device)
  -------------------
  -- Set up scheduled
  -- services once the
  -- driver gets
  -- initialized.
  log.trace('[goguma] LifeCycle init')

  -- Ping schedule.
  device.thread:call_on_schedule(
    config.SCHEDULE_PERIOD,
    function ()
      return commands.ping(
        driver.server.ip,
        driver.server.port,
        device)
    end,
    'Ping schedule')

  -- Refresh schedule
  device.thread:call_on_schedule(
    config.SCHEDULE_PERIOD,
    function ()
      return commands.refresh(nil, device)
    end,
    'Refresh schedule')
end

function lifecycle_handler.added(driver, device)
  -- Once device has been created
  -- at API level, poll its state
  -- via refresh command and send
  -- request to share server's ip
  -- and port to the device os it
  -- can communicate back.
  log.trace('[goguma] LifeCycle added')
  update_device(driver, device)

  -- commands.refresh(nil, device)
  -- commands.ping(driver.server.ip, driver.server.port, device)
end

function lifecycle_handler.doConfigure(driver, device)

  log.trace('[goguma] LifeCycle doConfigure')
end

function lifecycle_handler.infoChanged(driver, device, event, args)

  log.trace('[goguma] LifeCycle infoChanaged')
  log.trace(device.type)
  log.trace(device.device_network_id)
  log.trace(device.label)
  log.trace(device.profile)
  log.trace(device.manufacturer)
  log.trace(device.model)
  log.trace(device.vendor_provided_label)
  log.trace('--------------- end ------------')

  commands.refresh(nil, device)
  commands.ping(driver.server.ip, driver.server.port, device)

  log.trace('[goguma] old state : '..tostring(args.old_st_store.preferences.createDevice))

  if args.old_st_store.preferences.createDevice == false and device.preferences.createDevice == true then
    log.trace('[goguma] create new device!!!')
    create_device(driver)
  end
end

function lifecycle_handler.driverSwitched(driver, device)

  log.trace('[goguma] LifeCycle driverSwitched')
  log.trace(device.type)
  log.trace(device.device_network_id)
  log.trace(device.label)
  log.trace(device.profile)
  log.trace(device.manufacturer)
  log.trace(device.model)
  log.trace(device.vendor_provided_label)
  log.trace('--------------- end ------------')

  commands.send_login(device)
  commands.refresh(nil, device)
  commands.ping(driver.server.ip, driver.server.port, device)
end

function lifecycle_handler.removed(_, device)
  -- Notify device that the device
  -- instance has been deleted and
  -- parent node must be deleted at
  -- device app.

  log.trace('[goguma] LifeCycle removed')

  -- Remove Schedules created under
  -- device.thread to avoid unnecessary
  -- CPU processing.
  for timer in pairs(device.thread.timers) do
    device.thread:cancel_timer(timer)
  end
end

return lifecycle_handler
