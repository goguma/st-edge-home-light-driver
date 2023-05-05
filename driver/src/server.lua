local lux = require('luxure')
local cosock = require('cosock').socket
local json = require('dkjson')
local log = require('log')

local hub_server = {}

function hub_server.start(driver)
  local server = lux.Server.new_with(cosock.tcp(), {env='debug'})

  -- Register server
  driver:register_channel_handler(server.sock, function ()
    server:tick()
  end)

  -- Endpoint
  server:post('/push-state', function (req, res)
    local body = json.decode(req:get_body())

    local device = driver:get_device_info(body.uuid)

    roomNumber = string.match(device.preferences.roomNumber,"%d+")
    if roomNumber == body.roomNumber then
      log.debug('This push event is mine, roomNumber : '..roomNumber)

      local switches = body.units

      for _, switch in ipairs(switches) do
        if string.match(device.preferences.lightNumber,"%d+") == string.match(switch['unit'],"%d+") then
          log.debug('device lightNumber :'..device.preferences.lightNumber)
          log.debug('json switch number : '..switch['unit'])
          if switch['state'] == 'on' then
            log.trace('switch on')
            driver:on_off(device, 'on')
            break
          else
            log.trace('switch off')
            driver:on_off(device, 'off')
            break
          end
        end
      end
    end

    res:send('HTTP/1.1 200 OK')
  end)
  server:listen()
  driver.server = server
end

return hub_server
