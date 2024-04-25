-- print to check console
function love.load()
  print('hello world!')
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
  love.graphics.print('Hello World! Waiting ' .. tostring(math.floor(6 - wait)) .. 's to close...', 300, 300)
end
