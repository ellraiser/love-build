print('main.lua')

-- for macos we need to append the source directory to use our .so file in 
-- the exported version
if love.system.getOS() == 'OS X' and love.filesystem.isFused() then
  package.cpath = package.cpath .. ';' .. love.filesystem.getSourceBaseDirectory() .. '/?.so'
end

-- require our https.so / https.dll and check its loaded
local https = require('https')
print(https)

-- print to check console on load
function love.load()
  print('love.load')
end

-- wait 5s then quit, used by the github workflow
local wait = 0
function love.update(dt)
  wait = wait + dt
  if wait >= 5 then
    love.event.quit()
  end
end

-- say hi!
function love.draw()
  love.graphics.print('Hello World! Waiting ' ..
    tostring(math.floor(6 - wait)) .. 's to close...', 300, 300)
end
