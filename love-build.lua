require('libs.love-zip')
require('libs.love-icon')
require('libs.love-squashfs')
require('libs.love-exedit')

local build_canvas = nil
local build_logo = nil
local build_font = nil
if love.window and love.graphics then
  build_canvas = love.graphics.newCanvas(320, 160)
  build_logo = love.graphics.newImage('resources/love.png')
  build_font = love.graphics.newImageFont(
    'resources/font-char.png',
    " AaBbCcDdEeFfGgHhIiJjKkLlMmNnOoPpQqRrSsTtUuVvWwXxYyZz+#:-'!?.0123456789,/ %()çö<_", 1)
end

return {

  -- setup general love.build properties
  http = require('https'),
  canvas = build_canvas,
  logo = build_logo,
  font = build_font,
  status = '',
  path = '',
  folder = '',
  os = 'windows',
  opts = {},
  logs = {},
  hooks = {},
  configs = 1,
  config = 1,
  config_name = '',
  cache = '',
  quit = false,
  queue = '',
  update_time = 0,
  target_time = 0.1, -- time between steps


  -- main build methods, in order of execution:


  -- @method - love.build.startBuild()
  -- @desc - start the build, setting up directories and mounting the project
  -- @return {nil}
  startBuild = function()

    -- start build
    love.build.log('starting build')
    love.build.status = 'Starting Build...'
    love.build.start = love.timer.getTime()

    -- get os shorthand
    local current_os = love.system.getOS()
    if current_os == 'Linux' then love.build.os = 'linux' end
    if current_os == 'OS X' then love.build.os = 'macos' end

    -- make sure we have the expected local folders
    love.build.log('setting up save directory')
    love.filesystem.createDirectory('cache')
    love.filesystem.createDirectory('output')
    love.filesystem.createDirectory('temp')
    love.build.wipeDirectory('temp')

    -- mount project path for reading project files
    love.build.path = string.gsub(love.build.path, '/main.lua', '')
    love.build.path = string.gsub(love.build.path, '\\main.lua', '')
    local mountp = love.filesystem.mountFullPath(love.build.path, 'project', 'read')
    if mountp ~= true then
      return love.build.err('failed to mount project path "' .. love.build.path .. '"')
    end
    love.build.log('project mounted at: "' .. love.build.path .. '"')

    -- make sure there is a main.lua in the project
    local main_data = love.build.readData('project/main.lua')
    if main_data == nil then
      return love.build.err('no main.lua file in project root')
    end

    -- read the config file
    love.build.queue = 'readConfig'
    love.build.status = 'Reading Config...'

  end,


  -- @method - love.build.readConfig()
  -- @desc - reads the build.lua in the project to get build options
  -- @return {nil}
  readConfig = function()
    love.build.log('reading config')
    local start_time = love.timer.getTime()

    -- check build file exists in mounted project path
    local build_data = love.build.readData('project/build.lua')
    if build_data == nil then
      return love.build.err('no build.lua found in root of "' .. love.build.path .. '"')
    end

    -- check package returns valid table
    local opts = love.filesystem.load('project/build.lua')()
    if opts == nil or type(opts) ~= 'table' then
      return love.build.err('specified build.lua does not return anything')
    end

    if opts[1] ~= nil and type(opts[1]) == 'table' then
      love.build.configs = #opts
      opts = opts[love.build.config]
    end
  
    -- set options global using config
    love.build.log('setting options')
    love.build.opts.name = opts.name or 'SuperGame'
    love.build.opts.developer = opts.developer or 'love2d'
    love.build.opts.version = opts.version or '1.0.0'
    love.build.opts.output = nil
    love.build.opts.config = opts.config or ''
    if opts.output ~= nil then
      love.build.opts.output = love.build.path .. '/' .. opts.output
    end
    love.build.opts.ignore = opts.ignore or {}
    table.insert(love.build.opts.ignore, '.github')
    table.insert(love.build.opts.ignore, '.gitattributes')
    table.insert(love.build.opts.ignore, '.gitignore')
    table.insert(love.build.opts.ignore, '.git')
    table.insert(love.build.opts.ignore, '.DS_Store')
    table.insert(love.build.opts.ignore, '.vs')
    table.insert(love.build.opts.ignore, '.vscode')
    love.build.opts.version = opts.version or '1.0.0'
    love.build.opts.love = opts.love or '11.5'

    -- set default indentifier for backup if not set
    local default_idendifier = 'com.' .. 
      string.lower(love.build.opts.developer) .. '.' ..
      string.lower(love.build.opts.name)
    love.build.opts.identifier = opts.identifier or default_idendifier

    -- additional options
    love.build.opts.icon = opts.icon or nil
    if love.build.opts.icon == nil then love.build.opts.icon = '' end
    love.build.opts.use32bit = opts.use32bit or false
    -- if platforms specified use that instead for targets
    if opts.platforms ~= nil and type(opts.platforms) == 'table' then
      love.build.targets = table.concat(opts.platforms, ',')
    end
    love.build.log('target platforms: "' .. love.build.targets .. '"')

    -- lib entries are also ignored
    love.build.opts.libs = opts.libs or {}
    for key, value in pairs(love.build.opts.libs) do
      if key == 'windows' or key == 'macos' or key == 'linux' or key == 'steamdeck' or key == 'all' then
        for l=1,#value do
          local filename = value[l]
          if filename:find("/[^/]*$") ~= nil then
            filename = filename:sub(filename:find("/[^/]*$") + 1, #filename)
          end
          table.insert(love.build.opts.ignore, filename)
          print('lib option', filename)
        end
      else
        local filename = value
        if filename:find("/[^/]*$") ~= nil then
          filename = filename:sub(filename:find("/[^/]*$") + 1, #filename)
        end
        table.insert(love.build.opts.ignore, filename)
        print('lib option', filename)
      end
    end

    -- hooks if used
    love.build.hooks = opts.hooks or {}

    -- print options out for sense checking
    for key, value in pairs(love.build.opts) do
      love.build.log('  ' .. key .. ': ' .. tostring(value) )
    end

    love.build.folder = string.lower(love.build.opts.name) .. '_' .. love.build.opts.version
    if love.build.opts.config ~= '' then
      love.build.folder = love.build.folder .. '_' .. love.build.opts.config
      love.build.config_name = ' (' .. love.build.opts.config .. ')'
    end
    love.build.folder = string.gsub(love.build.folder, ' ', '_')

    -- run preprocess if any 
    if love.build.hooks.before_build then
      love.build.log('preprocess: ' .. love.build.path .. '/' .. love.build.hooks.before_build)
      local cmd = 'sh'
      if love.build.os == 'windows' then cmd = 'bash' end
      os.execute(cmd .. ' ' .. love.build.path .. '/' .. love.build.hooks.before_build .. ' ' .. love.build.path)
    end

    love.build.log('step finished in ' .. love.build.formatTime(love.timer.getTime() - start_time))

    love.build.queue = 'makeLovefile'
    love.build.status = 'Making Lovefile...'

  end,


  -- @method - love.build.makeLovefile()
  -- @desc - zip up the project to make the .love file
  -- @return {nil}
  makeLovefile = function ()
  
    -- setup paths
    local opts = love.build.opts
    local output = 'output/' .. love.build.folder
    local lovefile = output .. '/' .. opts.name .. '.love'

    -- if doing multiple configs then dont bother making a love for each one!
    local need_love = true
    if love.build.configs > 1 and love.build.config > 1 then
      need_love = false
    end

    if need_love then
      love.build.log('making lovefile')
      local start_time = love.timer.getTime()
  
      -- create version folder in temp output if doesn't exist
      love.filesystem.createDirectory(output)
  
      -- remove existing .lovefile if any
      love.filesystem.remove(lovefile)
  
      -- zip mounted project directory into a .love file in app data
      love.build.log('creating lovefile from: "' .. love.build.path .. '"')
      love.build.log('ignoring: "' .. table.concat(opts.ignore, ',') .. '"')
  
      -- compress specific files/folders manually
      local zip = love.zip:newZip(false)
      zip:addFolder('project', opts.ignore) -- directory contents with ignore list
      local compress, err = zip:finish(lovefile)
      if compress ~= true then
        return love.build.err('failed to create lovefile: "' .. err .. '"')
      end
  
      -- check we made a lovefile
      local love_data = love.build.readData(lovefile)
      if love_data == nil then
        return love.build.err('failed to create .lovefile')
      end

      love.build.cache = output
  
      love.build.log('created "' .. lovefile .. '"')
      love.build.log('step finished in ' .. love.build.formatTime(love.timer.getTime() - start_time))

    else
      love.build.log('already cached "' .. lovefile .. '"')
      love.filesystem.createDirectory(output)
  
      -- remove existing .lovefile if any
      love.filesystem.remove(lovefile)
      love.build.copyFile(love.build.cache .. '/' .. opts.name .. '.love', output .. '/' .. opts.name .. '.love')
    end

    -- what we make next depends on settings
    if love.build.targets:find('windows') then
      love.build.queue = 'makeWindows'
      love.build.status = 'Building Windows...' .. love.build.config_name
    elseif love.build.targets:find('macos') then
      love.build.queue = 'makeMacOS'
      love.build.status = 'Building MacOS...' .. love.build.config_name
    elseif love.build.targets:find('linux') then
      love.build.queue = 'makeLinux'
      love.build.status = 'Building Linux...' .. love.build.config_name
    elseif love.build.targets:find('steamdeck') then
      love.build.queue = 'makeSteamdeck'
      love.build.status = 'Building Steamdeck...' .. love.build.config_name
    else
      return love.build.err('no target platforms specified')
    end

  end,


  -- @method - love.build.makeWindows()
  -- @desc - build the windows.exe for the project
  -- @param {boolean} build32 - if present, will build 32bit instead of 64
  --                            this is called automatically after a 64bit 
  -- @return {nil}
  makeWindows = function(build32)
    local start_time = love.timer.getTime()

    -- decide on bit
    local wbit = 'win64'
    if build32 then wbit = 'win32' end
    love.build.log('building windows ' .. wbit)

    -- get source file
    local srcfile = 'love-' .. love.build.opts.love .. '-' .. wbit .. '.zip'
    love.build.log('getting love src for: "' .. srcfile .. '"')
    local getsrc = love.build.downloadLove(wbit)
    if getsrc == false then
      return love.build.err('failed to get love src')
    end

    -- get paths
    local opts = love.build.opts
    local output = 'output/' .. love.build.folder
    local lovefile = output .. '/' .. opts.name .. '.love'
    local zipfile = output .. '/' .. opts.name .. '-windows.zip'
    if build32 == true then
      zipfile = output .. '/' .. opts.name .. '-windows32.zip'
    end
    local srcdir = 'love-' .. love.build.opts.love .. '-' .. wbit

    -- cleanup existing if any
    love.filesystem.remove(zipfile)

    -- copy src to /temp
    local copy = love.build.copyFile('cache/' .. srcfile, 'temp/' .. srcfile)
    if copy == false then
      return love.build.err('failed to copy src from /cache to /temp')
    end

    -- extract source
    local unzip = love.zip:newZip()
    local decompress, err = unzip:decompress('temp/' .. srcfile, 'temp/')
    if decompress == false then
      return love.build.err('failed to unzip src: "' .. err .. '"')
    end

    -- add game icon
    if opts.icon ~= nil then
      love.build.log('setting game icon')
      local icon = love.icon:newIcon('project/' .. opts.icon)
      icon:convertToICO('temp/' .. srcdir .. '/game.ico')
      -- set the exe icon itself
      love.build.log('setting game metadata')
      local modified_exe = love.exedit.updateIcon('temp/' .. srcdir .. '/love.exe', 'project/' .. opts.icon)
      local srcexe = love.filesystem.openFile('temp/' .. srcdir .. '/love.exe', 'w')
      srcexe:write(modified_exe)
      srcexe:close()
    end


    -- fuse game
    love.build.log('fuse exe')
    love.build.concatFiles(
      {'temp/' .. srcdir .. '/love.exe', lovefile},
      'temp/' .. srcdir .. '/' .. opts.name .. '.exe'
    )

    -- copy any libs specified into the folder
    for key, value in pairs(opts.libs) do
      if key == 'windows' or key == 'all' then
        for l=1,#value do
          local filename = value[l]
          if filename:find("/[^/]*$") ~= nil then
            filename = filename:sub(filename:find("/[^/]*$") + 1, #filename)
          end
          love.build.log('adding lib: "' .. value[l] .. '" > "/' .. filename .. '"')
          love.build.copyFile('project/' .. value[l], 'temp/' .. srcdir .. '/' .. filename)
        end
      elseif key ~= 'macos' and key ~= 'linux' then
        local filename = value
        if filename:find("/[^/]*$") ~= nil then
          filename = filename:sub(filename:find("/[^/]*$") + 1, #filename)
        end
        love.build.log('adding lib: "' .. value .. '" > "/' .. filename .. '"')
        love.build.copyFile('project/' .. value, 'temp/' .. srcdir .. '/' .. filename)
      end
    end

    -- make config file directly in source
    local config_file = 'return {\n' ..
      "\tname = '" .. love.build.opts.name .. "',\n" ..
      "\tconfig = '" .. love.build.opts.config .. "',\n" ..
      "\tplatform = '" .. wbit .. "',\n" ..
      "\tversion = '" .. love.build.opts.version .. "',\n" ..
      "\tlove = '" .. love.build.opts.love .. "'\n" ..
      '}'
    love.filesystem.write('temp/' .. srcdir .. '/' .. 'lbconfig.lua', config_file)

    -- zip file output, ignoring some files
    local zip = love.zip:newZip(false)
    local compress, err = zip:compress('temp/' .. srcdir, zipfile, {
      'love.exe', 'lovec.exe', 'changes.txt', 'readme.txt', 'love.ico'
    })
    if compress == false then
      return love.build.err('failed to zip up windows output: "' .. err .. '"')
    end

    love.build.log('built windows ' .. wbit .. ' successfully')
    love.build.log('step finished in ' .. love.build.formatTime(love.timer.getTime() - start_time))

    -- what we make next depends on settings
    if build32 == nil and love.build.opts.use32bit == true then
      love.build.makeWindows(true)
    elseif love.build.targets:find('macos') then
      love.build.queue = 'makeMacOS'
      love.build.status = 'Building MacOS...' .. love.build.config_name
    elseif love.build.targets:find('linux') then
      love.build.queue = 'makeLinux'
      love.build.status = 'Building Linux...' .. love.build.config_name
    elseif love.build.targets:find('steamdeck') then
      love.build.queue = 'makeSteamdeck'
      love.build.status = 'Building Steamdeck...' .. love.build.config_name
    else
      love.build.queue = 'finishBuild'
      love.build.status = 'Finishing Up...'
    end

  end,


  -- @method - love.build.makeMacOS()
  -- @desc - build the mac.app for the project
  -- @return {nil}
  makeMacOS = function()
    love.build.log('building macos')
    local start_time = love.timer.getTime()
    
    -- get source file
    local srcfile = 'love-' .. love.build.opts.love .. '-macos.zip'
    love.build.log('getting love src for: "' .. srcfile .. '"')
    local getsrc = love.build.downloadLove('macos')
    if getsrc == false then
      return love.build.err('failed to get love src')
    end

    -- get paths
    local opts = love.build.opts
    local output = 'output/' .. love.build.folder
    local lovefile = output .. '/' .. opts.name .. '.love'
    local zipfile = output .. '/' .. opts.name .. '-macos.zip'
    local srcdir = 'love-' .. love.build.opts.love .. '-macos'

    -- cleanup existing if any
    love.filesystem.remove(zipfile)

    -- copy src to /temp
    local copy = love.build.copyFile('cache/' .. srcfile, 'temp/' .. srcfile)
    if copy == false then
      return love.build.err('failed to copy src from /cache to /temp')
    end

    -- extract source
    local unzip = love.zip:newZip(false, true)
    local mapping = {}
    -- pass a mapping here so we extract the .app as the name we want
    -- saves having to worry about renaming without breaking symlinks
    mapping['love.app'] = opts.name .. '.app'
    local decompress, err = unzip:decompress('temp/' .. srcfile, 'temp/' .. srcdir, mapping)
    if decompress == false then
      return love.build.err('failed to unzip src: "' .. err .. '"')
    end

    -- put lovefile in resources
    local appcontents = 'temp/' .. srcdir .. '/' .. opts.name .. '.app/Contents'
    love.build.copyFile(lovefile, appcontents  .. '/Resources/' .. opts.name .. '.love')

    -- update info.plist with game specific values
    love.build.log('update plist')
    local plist_data = love.build.readData(appcontents .. '/Info.plist')
    if plist_data == nil then
      return love.build.err('failed to read info.plist')
    end
    -- app icon file
    plist_data = string.gsub(plist_data, 
      '<key>CFBundleIconFile</key>\n\t<string>OS X AppIcon</string>', 
      '<key>CFBundleIconFile</key>\n\t<string>game</string>'
    )
    -- app icon name
    plist_data = string.gsub(plist_data, 
      '<key>CFBundleIconName</key>\n\t<string>OS X AppIcon</string>', 
      '<key>CFBundleIconName</key>\n\t<string>game</string>'
    )
    -- game name
    plist_data = string.gsub(plist_data, 
      '<key>CFBundleName</key>\n\t<string>LÖVE</string>', 
      '<key>CFBundleName</key>\n\t<string>'..opts.name..'</string>'
    )
    -- game identifier
    plist_data = string.gsub(plist_data, 
      '<key>CFBundleIdentifier</key>\n\t<string>org.love2d.love</string>',
      '<key>CFBundleIdentifier</key>\n\t<string>'..opts.identifier..'</string>'
    )
    -- strip type association from end of plist
    local types = string.find(plist_data, '<key>UTExportedTypeDeclarations</key>')
    plist_data = string.sub(plist_data, 1, types-1)
    plist_data = plist_data .. '\n</dict>\n</plist>\n'
    local plist_file = love.filesystem.openFile(appcontents .. '/Info.plist', 'w')
    plist_file:write(plist_data)
    plist_file:close()

    -- add game icon
    love.build.log('setting game icon')
    if opts.icon ~= nil then
      -- convert given icon using icon.lua and move to resources
      local icon = love.icon:newIcon('project/' .. opts.icon)
      icon:convertToICNS(appcontents .. '/Resources/game.icns')
    end

    -- copy any libs specified into the app/Contents/Resources folder
    for key, value in pairs(opts.libs) do
      if key == 'macos' or key == 'all' then
        for l=1,#value do
          local filename = value[l]
          if filename:find("/[^/]*$") ~= nil then
            filename = filename:sub(filename:find("/[^/]*$") + 1, #filename)
          end
          love.build.log('adding lib: "' .. value[l] .. '" > "Contents/MacOS/' .. filename .. '"')
          love.build.copyFile('project/' .. value[l], appcontents .. '/MacOS/' .. filename)
          love.build.copyFile('project/' .. value[l], appcontents .. '/Resources/' .. filename)
        end
      elseif key ~= 'windows' and key ~= 'linux' then
        local filename = value
        if filename:find("/[^/]*$") ~= nil then
          filename = filename:sub(filename:find("/[^/]*$") + 1, #filename)
        end
        love.build.log('adding lib: "' .. value .. '" > "Contents/MacOS/' .. filename .. '"')
        love.build.copyFile('project/' .. value, appcontents .. '/MacOS/' .. filename)
        love.build.copyFile('project/' .. value, appcontents .. '/Resources/' .. filename)
      end
    end

    -- make config file directly in source
    local config_file = 'return {\n' ..
      "\tname = '" .. love.build.opts.name .. "',\n" ..
      "\tconfig = '" .. love.build.opts.config .. "',\n" ..
      "\tplatform = '" .. 'macos' .. "',\n" ..
      "\tversion = '" .. love.build.opts.version .. "',\n" ..
      "\tlove = '" .. love.build.opts.love .. "'\n" ..
      '}'
    love.filesystem.write(appcontents .. '/MacOS/' .. 'lbconfig.lua', config_file)
    love.filesystem.write(appcontents .. '/Resources/' .. 'lbconfig.lua', config_file)

    -- zip file output
    local zip = love.zip:newZip(false, true)
    local compress, err = zip:compress('temp/' .. srcdir, zipfile, {}, unzip.symlinks)
    if compress == false then
      return love.build.err('failed to zip up macos output: "' .. err .. '"')
    end

    love.build.log('built macos successfully')
    love.build.log('step finished in ' .. love.build.formatTime(love.timer.getTime() - start_time))

    -- what we make next depends on settings
    if love.build.targets:find('linux') then
      love.build.queue = 'makeLinux'
      love.build.status = 'Building Linux...' .. love.build.config_name
    elseif love.build.targets:find('steamdeck') then
      love.build.queue = 'makeSteamdeck'
      love.build.status = 'Building Steamdeck...' .. love.build.config_name
    else
      love.build.queue = 'finishBuild'
      love.build.status = 'Finishing Up...'
    end

  end,


  -- @method - love.build.makeLinux()
  -- @desc - build the standard linux build for the project
  -- @return {nil}
  makeLinux = function()
    love.build.log('building linux')
    local start_time = love.timer.getTime()

    -- get source file
    local srcfile = 'love-' .. love.build.opts.love .. '-x86_64.AppImage'
    love.build.log('getting love src for: "' .. srcfile .. '"')
    local getsrc = love.build.downloadLove('linux')
    if getsrc == false then
      return love.build.err('failed to get love src')
    end

    -- get paths
    local opts = love.build.opts
    local output = 'output/' .. love.build.folder
    local lovefile = output .. '/' .. opts.name .. '.love'
    local zipfile = output .. '/' .. opts.name .. '-linux.zip'
    local srcdir = 'love-' .. love.build.opts.love .. '-linux'

    -- cleanup existing if any
    love.filesystem.remove(zipfile)

    -- copy src to /temp
    love.filesystem.createDirectory('temp/' .. srcdir)
    local copy = love.build.copyFile('cache/' .. srcfile, 'temp/' .. srcdir .. '/' .. srcfile)
    if copy == false then
      return love.build.err('failed to copy src from /cache to /temp')
    end

    -- strip squashfs from appimage and unsquash to srcdir
    local squash = love.squashfs:newSquashFS(true)
    squash:_stripAppImage('temp/' .. srcdir .. '/' .. srcfile, 'temp/' .. srcdir .. '/squashdata')
    local decompressed, err = squash:decompress('temp/' .. srcdir .. '/squashdata', 'temp/' .. srcdir .. '/squashfs-root')
    if decompressed == false then
      return love.build.err('failed to decompress appimage squashfs: "' .. decompressed .. '"')
    end

    -- fuse game
    love.build.log('fuse binary')
    love.build.concatFiles(
      {'temp/' .. srcdir .. '/squashfs-root/bin/love', lovefile},
      'temp/' .. srcdir .. '/squashfs-root/bin/' .. opts.name
    )
    love.filesystem.remove('temp/' .. srcdir .. '/squashfs-root/bin/love')

    -- create desktop file and move to temp/squashfs-root/love.desktop
    love.build.log('writing love.desktop')
    local desktopfile = '[Desktop Entry]\n'
    desktopfile = desktopfile .. 'Name=' .. love.build.opts.name .. '\n'
    desktopfile = desktopfile .. 'Comment=Built with LÖVE!\n'
    desktopfile = desktopfile .. 'MimeType=application/x-love-game;\n'
    desktopfile = desktopfile .. 'Exec=' .. love.build.opts.name ..' %f\n'
    desktopfile = desktopfile .. 'Type=Application\n'
    desktopfile = desktopfile .. 'Categories=Development;Game;\n'
    desktopfile = desktopfile .. 'Terminal=false\n'
    desktopfile = desktopfile .. 'Icon=icon\n'
    desktopfile = desktopfile .. 'NoDisplay=true\n'
    local desktopf = love.filesystem.openFile('temp/' .. srcdir .. '/squashfs-root/love.desktop', 'w')
    desktopf:write(desktopfile)
    desktopf:close()

    -- copy game icon to temp/squashfs-root/icon.png
    if love.build.opts.icon ~= nil then
      local i = love.icon:newIcon('project/' .. love.build.opts.icon)
      local img = love.graphics.newImage(i.img)
      local iconf = love.filesystem.openFile('temp/' .. srcdir .. '/squashfs-root/icon.png', 'w')
      iconf:write(i:_resize(img, 256):getString())
      iconf:close()
      local icond = love.filesystem.openFile('temp/' .. srcdir .. '/squashfs-root/.DirIcon', 'w')
      icond:write(i:_resize(img, 256):getString())
      icond:close()
    end
    
    -- create AppRun file and move to temp/squashfs-root/AppRun
    local apprunfile = '#!/bin/sh\n'
    apprunfile = apprunfile .. 'if [ -z "$APPDIR" ]; then\n'
    apprunfile = apprunfile .. '  APPDIR="$(dirname "$(readlink -f "$0")")"\n'
    apprunfile = apprunfile .. 'fi\n'
    apprunfile = apprunfile .. 'export LD_LIBRARY_PATH="$APPDIR/lib/:$LD_LIBRARY_PATH"\n'
    apprunfile = apprunfile .. 'if [ -z "$XDG_DATA_DIRS" ]; then #unset or empty\n'
    apprunfile = apprunfile .. '    XDG_DATA_DIRS="/usr/local/share/:/usr/share/"\n'
    apprunfile = apprunfile .. 'fi\n'
    apprunfile = apprunfile .. 'export XDG_DATA_DIRS="$APPDIR/share/:$XDG_DATA_DIRS"\n'
    apprunfile = apprunfile .. 'if [ -z "$LUA_PATH" ]; then\n'
    apprunfile = apprunfile .. '    LUA_PATH=";"\n'
    apprunfile = apprunfile .. 'fi\n'
    apprunfile = apprunfile .. 'export LUA_PATH="$APPDIR/share/luajit-2.1.0-beta3/?.lua;$APPDIR/share/lua/5.1/?.lua;$LUA_PATH"\n'
    apprunfile = apprunfile .. 'if [ -z "$LUA_CPATH" ]; then\n'
    apprunfile = apprunfile .. '    LUA_CPATH=";"\n'
    apprunfile = apprunfile .. 'fi\n'
    apprunfile = apprunfile .. 'export LUA_CPATH="$APPDIR/lib/?.so;$APPDIR/lib/lua/5.1/?.so;$LUA_CPATH"\n'
    apprunfile = apprunfile .. 'exec "$APPDIR/bin/' .. love.build.opts.name .. '" "$@"\n'
    local apprun = love.filesystem.openFile('temp/' .. srcdir .. '/squashfs-root/AppRun', 'w')
    apprun:write(apprunfile)
    apprun:close()

    -- copy any libs specified into the squashfs-root/lib folder
    for key, value in pairs(opts.libs) do
      if key == 'linux' or key == 'all' then
        for l=1,#value do
          local filename = value[l]
          if filename:find("/[^/]*$") ~= nil then
            filename = filename:sub(filename:find("/[^/]*$") + 1, #filename)
          end
          love.build.log('adding lib: "' .. value[l] .. '" > "lib/' .. filename .. '"')
          love.build.copyFile('project/' .. value[l], 'temp/' .. srcdir .. '/squashfs-root/lib/' .. filename)
        end
      elseif key ~= 'macos' and key ~= 'windows' then
        local filename = value
        if filename:find("/[^/]*$") ~= nil then
          filename = filename:sub(filename:find("/[^/]*$") + 1, #filename)
        end
        love.build.log('adding lib: "' .. value .. '" > "lib/' .. filename .. '"')
        love.build.copyFile('project/' .. value, 'temp/' .. srcdir .. '/squashfs-root/lib/' .. filename)
      end
    end

    -- make config file directly in source
    local config_file = 'return {\n' ..
      "\tname = '" .. love.build.opts.name .. "',\n" ..
      "\tconfig = '" .. love.build.opts.config .. "',\n" ..
      "\tplatform = '" .. 'linux' .. "',\n" ..
      "\tversion = '" .. love.build.opts.version .. "',\n" ..
      "\tlove = '" .. love.build.opts.love .. "'\n" ..
      '}'
    love.filesystem.write('temp/' .. srcdir .. '/squashfs-root/lib/' .. 'lbconfig.lua', config_file)

    -- remove squashfs-root/love.svg
    love.filesystem.remove('temp/' .. srcdir .. '/squashfs-root/love.svg')

    -- @NOTE shouldnt need to chmod the binary or apprun here as love-squashfs should handle setting that
    -- do the same as we do for love-zip, no extension, try marking 0755

    -- @TODO repackage as squashfs + combine with runtime-fuse2 when done 
    -- repackage binary, then concatFiles with the runtime-fuse2

    -- for now just zip up contents as the linux build
    local zip = love.zip:newZip(false, true)
    local compress, err = zip:compress('temp/' .. srcdir .. '/squashfs-root', zipfile, {}, squash.symlinks)
    if compress == false then
      return love.build.err('failed to zip up linux output: "' .. err .. '"')
    end

    love.build.log('built linux successfully')
    love.build.log('step finished in ' .. love.build.formatTime(love.timer.getTime() - start_time))

    -- check last type
    if love.build.targets:find('steamdeck') then
      love.build.queue = 'makeSteamdeck'
      love.build.status = 'Building Steamdeck...' .. love.build.config_name
    else
      love.build.queue = 'finishBuild'
      love.build.status = 'Finishing Up...'
    end

  end,


  -- @method - love.build.makeSteamdeck()
  -- @desc - build the linux steamdeck build for the project
  -- @return {nil}
  makeSteamdeck = function()
    love.build.log('building steamdeck')
    local start_time = love.timer.getTime()

    -- get source file
    local srcfile = 'love-' .. love.build.opts.love .. '-x86_64.AppImage'
    love.build.log('getting love src for: "' .. srcfile .. '"')
    local getsrc = love.build.downloadLove('linux')
    if getsrc == false then
      return love.build.err('failed to get love src')
    end

    -- get paths
    local opts = love.build.opts
    local output = 'output/' .. love.build.folder
    local lovefile = output .. '/' .. opts.name .. '.love'
    local zipfile = output .. '/' .. opts.name .. '-steamdeck.zip'
    local srcdir = 'love-' .. love.build.opts.love .. '-steamdeck'

    -- cleanup existing if any
    love.filesystem.remove(zipfile)

    -- copy src to /temp
    love.filesystem.createDirectory('temp/' .. srcdir)
    local copy = love.build.copyFile('cache/' .. srcfile, 'temp/' .. srcdir .. '/' .. srcfile)
    if copy == false then
      return love.build.err('failed to copy src from /cache to /temp')
    end

    -- strip squashfs from appimage and unsquash to srcdir
    local squash = love.squashfs:newSquashFS(true)
    squash:_stripAppImage('temp/' .. srcdir .. '/' .. srcfile, 'temp/' .. srcdir .. '/squashdata')
    local decompressed, err = squash:decompress('temp/' .. srcdir .. '/squashdata', 'temp/' .. srcdir .. '/squashfs-root')
    if decompressed == false then
      return love.build.err('failed to decompress appimage squashfs: "' .. decompressed .. '"')
    end

    -- fuse game
    love.build.log('fuse binary')
    love.build.concatFiles(
      {'temp/' .. srcdir .. '/squashfs-root/bin/love', lovefile},
      'temp/' .. srcdir .. '/squashfs-root/bin/' .. opts.name
    )
    love.filesystem.remove('temp/' .. srcdir .. '/squashfs-root/bin/love')

    -- create desktop file and move to temp/squashfs-root/love.desktop
    love.build.log('writing love.desktop')
    local desktopfile = '[Desktop Entry]\n'
    desktopfile = desktopfile .. 'Name=' .. love.build.opts.name .. '\n'
    desktopfile = desktopfile .. 'Comment=Built with LÖVE!\n'
    desktopfile = desktopfile .. 'MimeType=application/x-love-game;\n'
    desktopfile = desktopfile .. 'Exec=' .. love.build.opts.name ..' %f\n'
    desktopfile = desktopfile .. 'Type=Application\n'
    desktopfile = desktopfile .. 'Categories=Development;Game;\n'
    desktopfile = desktopfile .. 'Terminal=false\n'
    desktopfile = desktopfile .. 'Icon=icon\n'
    desktopfile = desktopfile .. 'NoDisplay=true\n'
    local desktopf = love.filesystem.openFile('temp/' .. srcdir .. '/squashfs-root/love.desktop', 'w')
    desktopf:write(desktopfile)
    desktopf:close()

    -- copy game icon to temp/squashfs-root/icon.png
    if love.build.opts.icon ~= nil then
      local i = love.icon:newIcon('project/' .. love.build.opts.icon)
      local img = love.graphics.newImage(i.img)
      local iconf = love.filesystem.openFile('temp/' .. srcdir .. '/squashfs-root/icon.png', 'w')
      iconf:write(i:_resize(img, 256):getString())
      iconf:close()
      local icond = love.filesystem.openFile('temp/' .. srcdir .. '/squashfs-root/.DirIcon', 'w')
      icond:write(i:_resize(img, 256):getString())
      icond:close()
    end
    
    -- create AppRun file and move to temp/squashfs-root/AppRun
    local apprunfile = '#!/bin/sh\n'
    apprunfile = apprunfile .. 'if [ -z "$APPDIR" ]; then\n'
    apprunfile = apprunfile .. '  APPDIR="$(dirname "$(readlink -f "$0")")"\n'
    apprunfile = apprunfile .. 'fi\n'
    apprunfile = apprunfile .. 'export LD_LIBRARY_PATH="$APPDIR/lib/:$LD_LIBRARY_PATH"\n'
    apprunfile = apprunfile .. 'if [ -z "$XDG_DATA_DIRS" ]; then #unset or empty\n'
    apprunfile = apprunfile .. '    XDG_DATA_DIRS="/usr/local/share/:/usr/share/"\n'
    apprunfile = apprunfile .. 'fi\n'
    apprunfile = apprunfile .. 'export XDG_DATA_DIRS="$APPDIR/share/:$XDG_DATA_DIRS"\n'
    apprunfile = apprunfile .. 'if [ -z "$LUA_PATH" ]; then\n'
    apprunfile = apprunfile .. '    LUA_PATH=";"\n'
    apprunfile = apprunfile .. 'fi\n'
    apprunfile = apprunfile .. 'export LUA_PATH="$APPDIR/share/luajit-2.1.0-beta3/?.lua;$APPDIR/share/lua/5.1/?.lua;$LUA_PATH"\n'
    apprunfile = apprunfile .. 'if [ -z "$LUA_CPATH" ]; then\n'
    apprunfile = apprunfile .. '    LUA_CPATH=";"\n'
    apprunfile = apprunfile .. 'fi\n'
    apprunfile = apprunfile .. 'export LUA_CPATH="$APPDIR/lib/?.so;$APPDIR/lib/lua/5.1/?.so;$LUA_CPATH"\n'
    apprunfile = apprunfile .. 'exec "$APPDIR/bin/' .. love.build.opts.name .. '" "$@"\n'
    local apprun = love.filesystem.openFile('temp/' .. srcdir .. '/squashfs-root/AppRun', 'w')
    apprun:write(apprunfile)
    apprun:close()

    -- copy any libs specified into the squashfs-root/lib folder
    for key, value in pairs(opts.libs) do
      if key == 'steamdeck' or key == 'all' then
        for l=1,#value do
          local filename = value[l]
          if filename:find("/[^/]*$") ~= nil then
            filename = filename:sub(filename:find("/[^/]*$") + 1, #filename)
          end
          love.build.log('adding lib: "' .. value[l] .. '" > "lib/' .. filename .. '"')
          love.build.copyFile('project/' .. value[l], 'temp/' .. srcdir .. '/squashfs-root/lib/' .. filename)
        end
      elseif key ~= 'macos' and key ~= 'windows' and key ~= 'linux' then
        local filename = value
        if filename:find("/[^/]*$") ~= nil then
          filename = filename:sub(filename:find("/[^/]*$") + 1, #filename)
        end
        love.build.log('adding lib: "' .. value .. '" > "lib/' .. filename .. '"')
        love.build.copyFile('project/' .. value, 'temp/' .. srcdir .. '/squashfs-root/lib/' .. filename)
      end
    end

    -- make config file directly in source
    local config_file = 'return {\n' ..
      "\tname = '" .. love.build.opts.name .. "',\n" ..
      "\tconfig = '" .. love.build.opts.config .. "',\n" ..
      "\tplatform = '" .. 'steamdeck' .. "',\n" ..
      "\tversion = '" .. love.build.opts.version .. "',\n" ..
      "\tlove = '" .. love.build.opts.love .. "'\n" ..
      '}'
    love.filesystem.write('temp/' .. srcdir .. '/squashfs-root/lib/' .. 'lbconfig.lua', config_file)

    -- remove squashfs-root/love.svg
    love.filesystem.remove('temp/' .. srcdir .. '/squashfs-root/love.svg')

    -- @NOTE shouldnt need to chmod the binary or apprun here as love-squashfs should handle setting that
    -- do the same as we do for love-zip, no extension, try marking 0755

    -- @TODO repackage as squashfs + combine with runtime-fuse2 when done 
    -- repackage binary, then concatFiles with the runtime-fuse2

    -- for now just zip up contents as the linux build
    local zip = love.zip:newZip(false, true)
    local compress, err = zip:compress('temp/' .. srcdir .. '/squashfs-root', zipfile, {}, squash.symlinks)
    if compress == false then
      return love.build.err('failed to zip up linux output: "' .. err .. '"')
    end

    love.build.log('built steamdeck successfully')
    love.build.log('step finished in ' .. love.build.formatTime(love.timer.getTime() - start_time))

    -- all done, finish up
    love.build.queue = 'finishBuild'
    love.build.status = 'Finishing Up...'

  end,


  -- @method - love.build.finishBuild()
  -- @desc - finish up the build, copy to output if needed, dump logs, and open
  --         the path to the output - also quit if ran from terminal
  -- @return {nil}
  finishBuild = function()
    love.build.log('finishing build')

    -- if output not nil, mount output and move what we've made + logs
    -- otherwise just open 
    local mounted = false
    if love.build.opts.output ~= nil then
      local mountd = love.filesystem.mountFullPath(love.build.opts.output, 'poutput', 'readwrite')
      if mountd ~= true then
        love.build.log('failed to mount output path "' .. love.build.opts.output .. '", make sure you are not using relative paths in the terminal and the folder exists.')
      else
        mounted = true
        local source = 'output/' .. love.build.folder
        local output = 'poutput/' .. love.build.opts.version
        love.filesystem.createDirectory(output)
        local lovefile = '/' .. love.build.opts.name .. '.love'
        local macos = '/' .. love.build.opts.name .. '-macos.zip'
        local win32 = '/' .. love.build.opts.name .. '-windows32.zip'
        local win64 = '/' .. love.build.opts.name .. '-windows.zip'
        local linux = '/' .. love.build.opts.name .. '-linux.zip'
        local steamdeck = '/' .. love.build.opts.name .. '-steamdeck.zip'
        love.build.copyFile(source .. lovefile, output .. lovefile)
        if love.build.targets:find('macos') then love.build.copyFile(source .. macos, output .. macos) end
        if love.build.targets:find('windows') and love.build.opts.use32bit then love.build.copyFile(source .. win32, output .. win32) end
        if love.build.targets:find('windows') then love.build.copyFile(source .. win64, output .. win64) end
        if love.build.targets:find('linux') then love.build.copyFile(source .. linux, output .. linux) end
        if love.build.targets:find('steamdeck') then love.build.copyFile(source .. steamdeck, output .. steamdeck) end
      end
    end

    -- run postprocess if any 
    if love.build.hooks.after_build then
      love.build.log('postprocess: ' .. love.build.path .. '/' .. love.build.hooks.after_build)
      local cmd = 'sh'
      if love.build.os == 'windows' then cmd = 'bash' end
      os.execute(cmd .. ' ' .. love.build.path .. '/' .. love.build.hooks.after_build .. ' ' .. love.build.path .. ' ' .. love.build.opts.output)
    end

    -- finalise build
    love.build.status = 'Build Finished'
    local time = love.timer.getTime() - love.build.start
    love.build.log('build finished in ' .. love.build.formatTime(time))
    love.build.dumpLogs()

    -- check if more configs?
    if love.build.configs > love.build.config then
      love.build.config = love.build.config + 1
      love.build.readConfig()
    else

      -- open path to output
      if mounted == true then
        love.build.copyFile('output/' .. love.build.folder .. '/build.log', 'poutput/' .. love.build.opts.version .. '/build.log')
        local ppath = love.build.opts.output .. '/' .. love.build.opts.version
        local try = love.system.openURL('file://' .. ppath)
        if try == false then print('couldnt open output folder, relative path used instead of fullpath: "' .. ppath .. '"') end
      else
        love.system.openURL('file://' .. love.filesystem.getSaveDirectory() .. '/output/' .. love.build.folder)
      end

      -- quit if ran from terminal
      if love.build.quit == true then
        love.event.quit(0)
      end

    end

  end,


  -- util methods used by the module


  -- @method - love.build.readData()
  -- @desc - reads the data for a given path and returns it 
  -- @param {string} path - path of the file to read
  -- @return {string} - returns file data or nil if failed
  readData = function(path, ignore_errs)
    local open, open_err = love.filesystem.openFile(path, 'r')
    if open ~= nil then
      local data, read_err = open:read()
      open:close()
      if data == nil and not ignore_errs then
        love.build.err('Failed to read path: "' .. path .. '" (' .. read_err .. ')')
      end
      return data
    end
    if not ignore_errs then love.build.err('Failed to open path: "' .. path .. '" (' .. open_err .. ')') end
    return nil
  end,


  -- @method - love.build.copyFile()
  -- @desc - copies an existing file to make a new renamed version
  -- @param {string} from - path of the file to copy
  -- @param {string} to - path of the new file to make
  -- @return {boolean} - returns true if succeeded, else returns false
  copyFile = function(from, to)
    local from_data = love.build.readData(from)
    if from_data == nil then return false end
    local to_file, err = love.filesystem.openFile(to, 'w')
    if to_file == nil then
      return false
    end
    local write = to_file:write(from_data)
    to_file:close()
    return write
  end,


  -- @method - love.build.concatFiles()
  -- @desc - concats a list of files into a new file, used to fuse binaries
  -- @param {table} files - list of file paths to concat together
  -- @param {string} to - path of the new file to make
  -- @return {boolean} - returns true if succeeded, else returns false
  concatFiles = function(files, to)
    local new_data = ''
    for f=1,#files do
      local read_data = love.build.readData(files[f])
      if read_data ~= nil then
        new_data = new_data .. read_data
      else
        love.build.log('failed to concat file: "' .. files[f] .. '"')
        return false
      end
    end
    local to_file = love.filesystem.openFile(to, 'w')
    local write = to_file:write(new_data)
    to_file:close()
    return write
  end,


  -- @method - love.build.wipeDirectory()
  -- @desc - wipes all files + folders inside a given directory
  -- @param {string} path - path of the folder to wipe
  -- @return {nil}
  wipeDirectory = function(path)
    local items = love.filesystem.getDirectoryItems(path)
    for i=1,#items do
      local info = love.filesystem.getInfo(path .. '/' .. items[i])
      if info.type == 'directory' then
        love.build.wipeDirectory(path .. '/' .. items[i])
        love.filesystem.remove(path .. '/' .. items[i])
      else
        love.filesystem.remove(path .. '/' .. items[i])
      end
    end
  end,


  -- @method - love.build.downloadLove()
  -- @desc - downloads the love source for a given os
  -- @param {string} - os to match github released, should be 'linux', 'macos',
  --                   win64 or win32
  -- @return {boolean} - returns true/false on whether source file has been downloaded
  downloadLove = function(os)

    -- get file version required
    local download_url = 'https://github.com/love2d/love/releases/download/'
    local srcfile = 'love-' .. love.build.opts.love .. '-' .. os .. '.zip'
    if os == 'linux' then
      srcfile = 'love-' .. love.build.opts.love .. '-' .. 'x86_64.AppImage'
    end

    -- check if we already have this in the cache, if we do return true
    local existing_data = love.build.readData('cache/' .. srcfile, true)
    if existing_data ~= nil then
      love.build.log('src already cached!')
      return true
    end

    -- if we dont we need to download a fresh source zip
    love.build.log('no cache for ' .. srcfile .. ', downloading release')

    -- try downloading
    local source_url = download_url .. love.build.opts.love .. '/' .. srcfile
    love.build.log('downloading: "' .. source_url .. '"')
    local code, body, _ = love.build.http.request(source_url)

    love.build.status = 'Downloading Source...'

    -- download succeeded
    if code == 200 then

      -- add to cache once downloaded for future builds
      love.filesystem.createDirectory('cache')
      local new_cache = love.filesystem.openFile('cache/' .. srcfile, 'w')
      local success, msg = new_cache:write(body)
      new_cache:close()
      if success == false then
        love.build.log('failed to create cache: ' .. msg)
        love.build.status = 'Error: Source download failed' .. msg
        return false
      else
        return true
      end

    -- requested version does not have a release
    else
      love.build.log('failed to download release: ' .. body)

      -- for 12.0 show message to prompt user to add to cache manually
      if tonumber(love.build.opts.love) >= 12 then
        love.build.log('if you want to use 12.0 for packaging you will need ' ..
          'to manually download the source and add it to ' ..
          love.filesystem.getSaveDirectory() .. '/cache')
        love.build.err('source file must be supplied to build with 12.0')
      end

      return false
    end

  end,


  -- @method - love.build.log()
  -- @desc - logs to console and stores in a table to be writting to build.log
  -- @param {string} msg - message to log
  -- @return {nil}
  log = function(msg)
    print('love.build > ' .. msg)
    table.insert(love.build.logs, msg)
  end,


  -- @method - love.build.err()
  -- @desc - logs an error and cancells the build process, dumping the logs
  -- @param {string} err - err that caused the problem
  -- @return {boolen} - returns false always
  err = function(err)
    love.build.log('love.build > error > ' .. err)
    love.build.status = 'Error: ' .. err -- show in gui
    table.insert(love.build.logs, err)
    love.build.dumpLogs()
    love.system.openURL('file://' .. love.filesystem.getSaveDirectory() .. '/output/' .. love.build.folder)
    return false
  end,


  -- @method - love.build.err()
  -- @desc - dumps logs to a log file to view later
  -- @return {nil}
  dumpLogs = function()
    local logdata = table.concat(love.build.logs, '\n')
    love.filesystem.write('output/' .. love.build.folder .. '/build.log', logdata)
  end,

  -- @method - love.build.formatTime
  -- @desc - formats seconds nicely
  -- @return {string} - returns formatted number as string
  formatTime = function(seconds)
    return string.format("%.3f", tostring(seconds)) .. 's'
  end


}
