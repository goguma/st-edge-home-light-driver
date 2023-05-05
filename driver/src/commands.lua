local caps = require('st.capabilities')
local utils = require('st.utils')
local neturl = require('net.url')
local log = require('log')
local json = require('dkjson')
local cosock = require "cosock"
local http = cosock.asyncify "socket.http"
local ltn12 = require('ltn12')

local command_handler = {}
local token

---------------
-- Ping command
function command_handler.ping(address, port, device)
  local ping_data = {ip=address, port=port, ext_uuid=device.id}
  return command_handler.send_ping(device, ping_data)
end
------------------
-- Refresh command
function command_handler.refresh(_, device)
  local success, data = command_handler.send_refresh(device)

  -- Check success
  if success then
    -- Monkey patch due to issues
    -- on ltn12 lib to fully sink
    -- JSON payload into table. Last
    -- bracket is missing.
    --
    -- Update below when fixed:
    --local raw_data = json.decode(table.concat(data))
    local raw_data = json.decode(table.concat(data)..'}')

    -- Define online status
    device:online()

    log.trace('Refreshing Switch')

    local switches = raw_data.data.units

    for _, switch in ipairs(switches) do
      if string.match(device.preferences.lightNumber,"%d+") == string.match(switch['unit'],"%d+") then
        if switch['state'] == 'on' then
          log.trace('switch on')
          device:emit_event(caps.switch.switch.on())
          break
        else
          log.trace('switch off')
          device:emit_event(caps.switch.switch.off())
          break
        end
      end
    end

  else
    log.error('failed to poll device state')
    device:offline()
  end
end

----------------
-- Switch commad
function command_handler.on_off(_, device, command)
  local on_off = command.command

  log.trace('on_off callled')
  local dest_url = 'http://'..device.preferences.serverIP..':'..device.preferences.serverPort..'/api/controller/light/room'
  local res_body = {}
  local putData = {roomNumber=string.match(device.preferences.roomNumber,"%d+"), lightNumber=string.match(device.preferences.lightNumber,"%d+"), state=on_off}

  -- HTTP Request
  local _, code = http.request({
    method='PUT',
    url=dest_url,
    sink=ltn12.sink.table(res_body),
    source = ltn12.source.string(json.encode(putData)),
    headers={
      ['Content-Type'] = 'application/json',
      ["Content-Length"] = string.len(json.encode(putData)),
      ['x-access-token'] = token
    }})

  -- Handle response
  if code == 200 then
    local raw_data = json.decode(table.concat(res_body)..'}')
    if raw_data.success == true then
      log.debug('on_off success!!!')
      return true, res_body
    end
  end
  log.error('fail code : '..code)
  return false, nil
end

------------------------
-- LAN Send ping
function command_handler.send_ping(device, ping_data)
  log.trace('ping callled')
  local dest_url = 'http://'..device.preferences.serverIP..':'..device.preferences.serverPort..'/api/controller/ping'
  -- local query = neturl.buildQuery(body or {})
  local res_body = {}
  local postData = ping_data

  -- HTTP Request
  local _, code = http.request({
    method='POST',
    url=dest_url,
    sink=ltn12.sink.table(res_body),
    source = ltn12.source.string(json.encode(postData)),
    headers={
      ['Content-Type'] = 'application/json',
      ["Content-Length"] = string.len(json.encode(postData)),
      ['x-access-token'] = token
    }})

  -- Handle response
  if code == 200 then
    local raw_data = json.decode(table.concat(res_body)..'}')
    if raw_data.success == true then
      log.debug('Got pong!!!')
      return true, res_body
    end
  end
  log.error('fail code : '..code)
  return false, nil
end

------------------------
-- LAN Send login
function command_handler.send_login(device)
  log.trace('login callled')
  local dest_url = 'http://'..device.preferences.serverIP..':'..device.preferences.serverPort..'/api/auth/login'
  local res_body = {}
  local postData = {username = device.preferences.userId, password = device.preferences.userPassword}

  -- HTTP Request
  local _, code = http.request({
    method='POST',
    url=dest_url,
    sink=ltn12.sink.table(res_body),
    source = ltn12.source.string(json.encode(postData)),
    headers={
      ['Content-Type'] = 'application/json',
      ["Content-Length"] = string.len(json.encode(postData))
    }})

  -- Handle response
  if code == 200 then
    local raw_data = json.decode(table.concat(res_body)..'}')
    if raw_data.success == true then
      log.debug('Got login token!!!')
      token = raw_data.data
      return true, token
    end
  end
  log.error('fail code : '..code)
  return false, nil
end

------------------------
-- LAN Send Refresh
function command_handler.send_refresh(device)
  log.trace('refresh callled')
  local dest_url = 'http://'..device.preferences.serverIP..':'..device.preferences.serverPort..'/api/controller/refresh?roomNumber='..string.match(device.preferences.roomNumber,"%d+")..'&lightNumber='..string.match(device.preferences.lightNumber,"%d+")
  log.debug('dest_url : '..dest_url)
  local res_body = {}
  -- HTTP Request
  local _, code = http.request({
    method='GET',
    url=dest_url,
    sink=ltn12.sink.table(res_body),
    headers={
      ['x-access-token'] = token
    }
  })

  -- Handle response
  if code == 200 then
    local raw_data = json.decode(table.concat(res_body)..'}')
    log.trace('result : '..tostring(raw_data.success))
    if raw_data.success == true then
      log.debug('refresh success')
      return true, res_body
    else
      log.debug('refresh failed')
      local result, _ = command_handler.send_login(device)
      if result == true then
        log.debug('retry send refresh')
        return command_handler.send_refresh(device)
      end
    end
  end
  log.error('fail code : '..code)
 
  return false, nil

end

return command_handler
