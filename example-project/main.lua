function love.load()
  print('hello world!')
  love.quit(1)
end

function love.draw()
  love.graphics.print('Hello World!?', 400, 300)
end