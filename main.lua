-- load love.build 
love.build = require('love-build')

-- handle argument on start
love.load = function(args)
  love.build.log('start')

  -- set some defaults for love
  if love.window and love.graphics then
    love.graphics.setDefaultFilter("nearest", "nearest")
    love.build.canvas:setFilter('nearest', 'nearest')
  end
  -- love-zip, love-icon and love-squashfs are written for 11.X
  -- so turn this off or people might think it's an error
  love.setDeprecationOutput(false)

  -- check arguments, should be main.lua path and then optional targets
  love.build.path = args[1]
  love.build.targets = args[2] or 'windows,macos,linux'

  -- no path, open window for dropping
  if love.build.path == nil then
    love.build.log('Error: No path given, cant package game')
    love.build.status = 'Drop your main.lua file here to build'

  -- not a path to a main.lua file
  elseif string.find(love.build.path, 'main.lua') == nil then
    love.build.log('Error: Path must be to your game\'s "main.lua" file')
    love.event.quit(0)

  -- start building
  else
    love.build.queue = 'startBuild'
    love.build.quit = true -- quit window if called in console mode
  end

end

-- handle file drop
love.filedropped = function(file)
  love.build.status = 'Starting Build...'
  love.build.path = file:getFilename()
  love.build.queue = 'startBuild'
end

-- run stuff on a timer so we can have a delay for the GUI
-- we could use coroutines but then we'd lose the error crashes
love.update = function(dt)
  love.build.update_time = love.build.update_time + dt
  if love.build.update_time >= love.build.target_time then
    love.build.update_time = love.build.update_time - love.build.target_time
    if love.build.path ~= '' then
      if love.build.queue ~= '' then
        local next = love.build[love.build.queue]
        love.build.queue = ''
        next()
        table.insert(love.build.logs, '')
      end
    end
  end
end

-- show status message
love.draw = function()
  love.build.canvas:renderTo(function()
    love.graphics.clear(20/255, 20/255, 20/255, 1)
    love.graphics.setFont(love.build.font)
    love.graphics.draw(love.build.logo, 160 - 32, 80 - 32 - 10)
    love.graphics.printf(love.build.status, 10, 120, 300, 'center')
  end)
  love.graphics.draw(love.build.canvas, 0, 0, 0, 2, 2)
end
