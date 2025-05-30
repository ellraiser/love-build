--[[
  @lib  - love-icon
  @desc - lua convertor for png files to create ico/icns files natively
          built for use with LÖVE 11.X+
  @url - https://github.com/ellraiser/love-icon
  @license - MIT
  ]]


local bit = require("bit")
love.icon = {


  --[[
    @method - love.icon:newIcon()
    @desc - creates a new icon instance for converting
    @param {string} path - path to the target png file
    @return {userdata} - returns the new icon obj to use
    ]]
  newIcon = function(self, path)
    local imgdata = love.image.newImageData(path)
    local iconcls = {
      files = {},
      img = imgdata,
      offset = 0
    }
    print('love.icon > new convertor using: "' .. path .. '"')
    local imgw = imgdata:getWidth()
    local imgh = imgdata:getHeight()
    if imgw ~= imgh then
      print('love.icon > WARNING: given image is not a square')
    end
    if imgw < 256 then
      print('love.icon > WARNING: given image is smaller than 256x256, output files will be low quality')
    end
    setmetatable(iconcls, self)
    self.__index = self
    return iconcls
  end,


  --[[
    @method - Icon:convertToICO()
    @desc - convert loaded file to .ico
    @param {string} output - output file path
    @return {boolean,string} - returns true/false and err if any
    ]]
  convertToICO = function(self, output)
    print('love.icon > creating ico at: "' .. output .. '"')
    return self:_convert(output, 'ico')
  end,


  --[[
    @method - Icon:convertToICNS()
    @desc - convert loaded file to .icns
    @param {string} output - output file path
    @return {boolean,string} - returns true/false and err if any
    ]]
  convertToICNS = function(self, output)
    print('love.icon > creating icns at: "' .. output .. '"')
    return self:_convert(output, 'icns')
  end,


  --[[
    @method - Icon:_resize()
    @desc - internal method to resize given png data to a new size
    @param {imgdata} img - imgdata from love.graphics.newImage 
    @param {format} size - format to use for converting
    @return {string} returns png encoded data
    ]]
  _resize = function(self, img, size)
    local png = love.graphics.newCanvas(size, size, {
      dpiscale = 1,
      format = 'rgba8'
    })
    png:renderTo(function()
      love.graphics.draw(img, 0, 0, 0, size/img:getWidth(), size/img:getHeight())
    end)
    return love.graphics.readbackTexture(png):encode('png')
  end,


  --[[
    @method - Icon:_convert()
    @desc - internal method to do actual data conversion
    @param {string} output - output file path
    @param {format} string - format to use for converting
    @return {boolean,string} - returns true/false and err if any
    ]]
  _convert = function(self, output, format)

    -- on windows we have to build the ico file using the standard format
    -- https://en.wikipedia.org/wiki/ICO_(file_format)
    if format == 'ico' then
      -- get image from data
      local img = love.graphics.newImage(self.img)
      local png128 = self:_resize(img, 128)
      -- ICONDIR header
      local header = ''
      header = header .. self:_intToBytes(0, 2) -- Reserved. Must always be 0. 
      header = header .. self:_intToBytes(1, 2) -- Specifies image type: 1 for icon (.ICO) image
      header = header .. self:_intToBytes(1, 2) -- Specifies number of images in the file. 
      -- ICONDIRENTRY
      local entries = ''
      entries = entries .. self:_intToBytes(128, 1) -- Specifies image width in pixels. Number between 0 and 255, 0 is 256
      entries = entries .. self:_intToBytes(128, 1) -- Specifies image height in pixels. Number between 0 and 255, 0 is 256
      entries = entries .. self:_intToBytes(255, 1) -- Specifies number of colors in the color palette
      entries = entries .. self:_intToBytes(0, 1) -- Reserved. Should be 0.
      entries = entries .. self:_intToBytes(0, 2) -- Specifies color planes. Should be 0 or 1
      entries = entries .. self:_intToBytes(8, 2) -- Specifies bits per pixel. https://learn.microsoft.com/previous-versions/windows/it-pro/windows-2000-server/cc938238(v=technet.10)
      entries = entries .. self:_intToBytes(png128:getSize(), 4) -- Specifies the size of the image's data in bytes 
      entries = entries .. self:_intToBytes(6 + 16, 4) -- Specifies the offset of PNG data from the beginning of the ICO file
      -- write ico file
      return love.filesystem.write(output, header .. entries .. png128:getString())

    -- for icns the format is a lot simpler
    -- https://en.wikipedia.org/wiki/Apple_Icon_Image_format
    elseif format == 'icns' then
      local img = love.graphics.newImage(self.img)
      local png256 = self:_resize(img, 256)
      local totalsize = png256:getSize()
      local file_length = love.data.pack('string', '>I4', totalsize + 16)
      local img_length = love.data.pack('string', '>I4', png256:getSize())
      -- write icns format
      local header = 'icns' -- Magic literal
      header = header .. file_length
      header = header .. 'ic08' -- 256x256
      header = header .. img_length
      header = header .. png256:getString() -- actual data
      return love.filesystem.write(output, header)
    end

  end,


  --[[
    @method - Icon:_intToBytes()
    @desc - internal method to convert a given int to a set number of bytes
    @param {number} int - integer to convert
    @param {number} size - number of bytes
    @return {string} - returns converted bytes
    ]]
  -- @TODO use love.data.pack for ints within range?
  _intToBytes = function(self, int, size)
    local t = {}
    for i=1,size do
      t[i] = string.char(bit.band(int, 255)) -- t[i] = int & 0xFF
      int = bit.rshift(int, 8) -- int = int >> 8
    end
    return table.concat(t)
  end


}
