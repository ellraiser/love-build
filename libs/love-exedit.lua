-- love-exedit
-- very, VERY WIP way to modify the .exe resources of the love source binary
-- currently just changes the ICON to the given icon image 

-- @TODO clean this mess up
-- @NOTE requires love, bit, love-icon

--[[

  usage to modify the icon of an exe:
    require('love-exedit')
    local modified_exe_data = love.exedit.updateIcon('path_to_exe', 'path_to_image')

  ]]

require('bit')
require('libs.love-icon')

love.exedit = {

  updateIcon = function(exe_file, image_file, debug_mode)

    print('love.exedit > modiying exe file', exe_file)

    -- read the data from the file and clone it for later
    local data, err = love.filesystem.read(exe_file)
    print(data, err)
    local new_data = data .. ''

    -- if exe file doesnt start with PE it prob has a dos stub
    -- if it does, the position of the PE entry will be at pos 60
    local poffset = 0
    if data:sub(1, 2) ~= 'PE' then
      poffset = love.exedit._readUInt(data, 61, 2)
    end
    for d=1,256 do
      local prod = data:sub(d, d+1)
      if prod == 'PE' then print('found PE at ', d, d+1) end
    end

    

    -- get the PE data using the PE header
    local pdata = data:sub(poffset+1, #data)
    if pdata:sub(1, 2) ~= 'PE' then
      print('love.exedit > error: invalid PE header')
      return nil
    end
    print('love.exedit > valid PE file', #pdata, pdata:sub(1, 2))

    -- read COFF header, 20 bytes
    local coff_start = 4
    local coff = {
      machine =      love.exedit._readUInt(pdata, coff_start+ 1, 2),
      section_no =   love.exedit._readUInt(pdata, coff_start+ 3, 2),
      timestamp =    love.exedit._readUInt(pdata, coff_start+ 5, 4),
      symbol_table = love.exedit._readUInt(pdata, coff_start+ 9, 4),
      symbol_no =    love.exedit._readUInt(pdata, coff_start+13, 4),
      opt_header =   love.exedit._readUInt(pdata, coff_start+17, 2),
      chars =        love.exedit._readUInt(pdata, coff_start+19, 2)
    }
    if coff.section_no > 96 then
      print('love.exedit > error: invalid section number: ', coff.section_no)
      return nil
    end
    print('love.exedit > coff header', coff.section_no, coff.timestamp, coff.opt_header)

    -- read opt header
    local opt = {
      magic =         love.exedit._readUInt(pdata, coff_start+21, 2),
      majorlversion = love.exedit._readUInt(pdata, coff_start+23, 1),
      minorlversion = love.exedit._readUInt(pdata, coff_start+24, 1),
      codesize =      love.exedit._readUInt(pdata, coff_start+25, 4),
      initdata =      love.exedit._readUInt(pdata, coff_start+29, 4),
      uninitdata =    love.exedit._readUInt(pdata, coff_start+33, 4),
      entrypoint =    love.exedit._readUInt(pdata, coff_start+37, 4),
      codebase =      love.exedit._readUInt(pdata, coff_start+41, 4),
      database =      love.exedit._readUInt(pdata, coff_start+45, 4),
    }
    print('love.exedit > coff opt', opt.magic, opt.majorlversion, opt.minorlversion, opt.initdata)
    if opt.initdata > #pdata then
      print('love.exedit > error: initdata > actual file bytes')
      return nil
    end
    -- 0x10B, 0x20B, 0x107
    -- 0x20B means this is a PE32+ executable with less headers
    local pe32p = false
    if opt.magic ~= 267 and opt.magic ~= 523 and opt.magic ~= 263 then
      print('love.exedit > error: invalid opt header magic', opt.magic)
      return nil
    end
    if opt.magic == 523 then
      pe32p = true
      print('love.exedit > PE32+ detected')
    end

    -- extra coff headers
    -- slight differences depending on pe32p
    local win = {}
    if pe32p == false then
      win = {
        imagebase =         love.exedit._readUInt(pdata, coff_start+ 49, 4),
        sectionalignment =  love.exedit._readUInt(pdata, coff_start+ 53, 4),
        filealignment =     love.exedit._readUInt(pdata, coff_start+ 57, 4),
        majorosversion =    love.exedit._readUInt(pdata, coff_start+ 61, 2),
        minorosversion =    love.exedit._readUInt(pdata, coff_start+ 63, 2),
        majorimageversion = love.exedit._readUInt(pdata, coff_start+ 65, 2),
        minorimageversion = love.exedit._readUInt(pdata, coff_start+ 67, 2),
        majorssversion =    love.exedit._readUInt(pdata, coff_start+ 69, 2),
        minorssversion =    love.exedit._readUInt(pdata, coff_start+ 71, 2),
        win32version =      love.exedit._readUInt(pdata, coff_start+ 73, 4),
        sizeofimage =       love.exedit._readUInt(pdata, coff_start+ 77, 4),
        sizeofheaders =     love.exedit._readUInt(pdata, coff_start+ 81, 4),
        checksum =          love.exedit._readUInt(pdata, coff_start+ 85, 4),
        subsystem =         love.exedit._readUInt(pdata, coff_start+ 89, 2),
        dllchars =          love.exedit._readUInt(pdata, coff_start+ 91, 2),
        stackreserve =      love.exedit._readUInt(pdata, coff_start+ 93, 4),
        stackcommit =       love.exedit._readUInt(pdata, coff_start+ 97, 4),
        heapreserve =       love.exedit._readUInt(pdata, coff_start+101, 4),
        heapcommit =        love.exedit._readUInt(pdata, coff_start+105, 4),
        loaderflags =       love.exedit._readUInt(pdata, coff_start+109, 4),
        rvasizes =          love.exedit._readUInt(pdata, coff_start+113, 4),
      }
    else
      win = {
        imagebase =         love.exedit._readUInt(pdata, coff_start+ 45, 8),
        sectionalignment =  love.exedit._readUInt(pdata, coff_start+ 53, 4),
        filealignment =     love.exedit._readUInt(pdata, coff_start+ 57, 4),
        majorosversion =    love.exedit._readUInt(pdata, coff_start+ 61, 2),
        minorosversion =    love.exedit._readUInt(pdata, coff_start+ 63, 2),
        majorimageversion = love.exedit._readUInt(pdata, coff_start+ 65, 2),
        minorimageversion = love.exedit._readUInt(pdata, coff_start+ 67, 2),
        majorssversion =    love.exedit._readUInt(pdata, coff_start+ 69, 2),
        minorssversion =    love.exedit._readUInt(pdata, coff_start+ 71, 2),
        win32version =      love.exedit._readUInt(pdata, coff_start+ 73, 4),
        sizeofimage =       love.exedit._readUInt(pdata, coff_start+ 77, 4),
        sizeofheaders =     love.exedit._readUInt(pdata, coff_start+ 81, 4),
        checksum =          love.exedit._readUInt(pdata, coff_start+ 85, 4),
        subsystem =         love.exedit._readUInt(pdata, coff_start+ 89, 2),
        dllchars =          love.exedit._readUInt(pdata, coff_start+ 91, 2),
        stackreserve =      love.exedit._readUInt(pdata, coff_start+ 93, 8),
        stackcommit =       love.exedit._readUInt(pdata, coff_start+101, 8),
        heapreserve =       love.exedit._readUInt(pdata, coff_start+109, 8),
        heapcommit =        love.exedit._readUInt(pdata, coff_start+117, 8),
        loaderflags =       love.exedit._readUInt(pdata, coff_start+125, 4),
        rvasizes =          love.exedit._readUInt(pdata, coff_start+129, 4),
      }
    end

    -- sense check some values
    if win.sectionalignment < win.filealignment then
      print('love.exedit > error: invalid section alignment', win.sectionalignment)
      return nil
    end
    if win.filealignment < 512 or win.filealignment > 64000 then
      print('love.exedit > error: invalid file alignment', win.filealignment)
      return nil
    end
    if win.win32version ~= 0 then
      print('love.exedit > error: win32 version is reserved', win.win32version)
      return nil
    end

    -- get number of data dirs in remaining header
    local data_dir_index = 117
    if pe32p then data_dir_index = 133 end
    local resource_table = love.exedit._readDataDirectory('dd_resource_table', pdata, data_dir_index+16)
    local dd_architecture = love.exedit._readUInt(pdata, data_dir_index+57, 8)
    if dd_architecture ~= 0 then
      print('love.exedit > error: data dir architecture is reserved', dd_architecture)
      return nil
    end
    local dd_reserved = love.exedit._readUInt(pdata, data_dir_index+121, 8)
    if dd_reserved ~= 0 then
      print('love.exedit > error: data dir reserved value', dd_reserved)
      return nil
    end

    -- each section has 40 bytes
    local section_table_index = data_dir_index+132
    if section_table_index ~= coff.opt_header + 24 + 1 then
      print('love.exedit > error: section out of alignment', section_table_index, coff.opt_header+24)
      return nil
    end
    local sections = {}
    for s=1,coff.section_no do
      local offset = section_table_index
      local section = {
        name =          pdata:sub(offset, offset+7),
        virtual_size =  love.exedit._readUInt(pdata, offset+ 8, 4),
        virtual_addr =  love.exedit._readUInt(pdata, offset+12, 4),
        raw_size =      love.exedit._readUInt(pdata, offset+16, 4),
        raw_pointer =   love.exedit._readUInt(pdata, offset+20, 4),
        reloc_pointer = love.exedit._readUInt(pdata, offset+24, 4),
        ln_pointer =    love.exedit._readUInt(pdata, offset+28, 4),
        reloc_no =      love.exedit._readUInt(pdata, offset+32, 2),
        ln_no =         love.exedit._readUInt(pdata, offset+34, 2),
        chars =         love.exedit._readUInt(pdata, offset+36, 4),
      }
      section_table_index = section_table_index + 40
      -- should be .X names for normal sections
      if section.name:sub(1, 1) ~= '.' then
        print('warn: uncommon section name', section.name)
      end
      -- size should be multiple of file alignment
      if section.raw_size % win.filealignment ~= 0 then
        print('love.exedit > error: invalid raw size for section', section.raw_size)
        return nil
      end 
      local section_key = section.name:sub(2, 5)
      sections[section_key] = section
    end

    -- check for section
    if sections['rsrc'] == nil then
      print('love.exedit > error: no resource section table found')
      return nil
    end

    -- raw pointers are from start of full file, not section data 
    local rsrc_data_index = sections.rsrc.raw_pointer + 1
    local rsrc_data = data:sub(rsrc_data_index, rsrc_data_index+sections.rsrc.raw_size-1)
    local rsrc_offset = sections.rsrc.raw_pointer
    print('love.exedit > resource section', section_table_index, sections.rsrc.raw_pointer, sections.rsrc.raw_size, #rsrc_data, rsrc_offset)

    local ico_icon = love.icon:newIcon(image_file)
    local ico_img = love.graphics.newImage(ico_icon.img)
    local ico_sizes = { 16, 32, 48, 64, 128, 512 }

    -- read top level directory
    -- this will cascade and read all subdirectories
    -- root resource dirs should have 3 levels to them
    local root_dir = love.exedit._readResourceDirectory(rsrc_data, 1, 1, nil, nil, resource_table.size)
    if root_dir == nil then
      print('love.exedit > failed to read resource directory')
      return nil
    end
    print('love.exedit > ROOT', root_dir.NumberOfIdEntries+root_dir.NumberOfNamedEntries)
    for l1=1,#root_dir.Entries do
      local lvl1_entry = root_dir.Entries[l1]
      local lvl1_type = love.exedit._RESOURCE_TYPES[lvl1_entry.Name]
      print('love.exedit >   RESOURCE', lvl1_type)
      if lvl1_entry.SubDirectory ~= nil then
        for l2=1,#lvl1_entry.SubDirectory.Entries do
          local lvl2_entry = lvl1_entry.SubDirectory.Entries[l2]
          if lvl2_entry.SubDirectory ~= nil then
            for l3=1,#lvl2_entry.SubDirectory.Entries do
              local lvl3_entry = lvl2_entry.SubDirectory.Entries[l3]
              --print('love.exedit >     DATA_ENTRY', l2, lvl3_entry.Name, tostring(#lvl3_entry.Data))
              if lvl1_type == 'VERSION' then

                -- first check the version info header
                -- https://learn.microsoft.com/en-us/windows/win32/menurc/vs-versioninfo
                local vlength =       love.exedit._readUInt(lvl3_entry.Data, 1, 2)
                local vvallen =       love.exedit._readUInt(lvl3_entry.Data, 3, 2) -- 52 if we have VS_FIXEDFILEINFO otherwise 0
                local vtype =         love.exedit._readUInt(lvl3_entry.Data, 5, 2) -- 0, binary data, 1 text data
                local vkey =          lvl3_entry.Data:sub(7, 7+29) -- "VS_VERSION_INFO" but WCHAR so *2 == 30 bytes
                local vpad =          love.exedit._readUInt(lvl3_entry.Data, 37, 2) -- padding to add for VS_FIXEDFILEINFO
                local fixedfileinfo = love.exedit._readDataType(lvl3_entry.Data, 39+vpad, 'FIXED_FILE_INFO')
                local vpad2 =         love.exedit._readUInt(lvl3_entry.Data, 39+vpad+vvallen, 2)
                print('love.exedit >     VERSION_INFO', vkey)

                -- after the second padding is a list of 1 or more StringFileInfo or VarFileInfo objs
                -- in love's case this is just 1 stringfileinfo then 1 varfileinfo
                -- https://learn.microsoft.com/en-us/windows/win32/menurc/stringfileinfo
                local sfi_start = 39+vpad+vvallen+2+vpad2
                local stringfileinfo = {
                  wLength = love.exedit._readUInt(lvl3_entry.Data, sfi_start, 2),
                  wValueLength = love.exedit._readUInt(lvl3_entry.Data, sfi_start+2, 2),
                  wType = love.exedit._readUInt(lvl3_entry.Data, sfi_start+4, 2), -- will be 1, as love uses text data for the info
                  szKey =  lvl3_entry.Data:sub(sfi_start+6, sfi_start+35), -- 'StringFileInfo'
                  padding = love.exedit._readUInt(lvl3_entry.Data, sfi_start+36, 2)
                }
                local vfi_start = sfi_start+stringfileinfo.wLength-2 -- -2 or +1 or +2?
                local varfileinfo = {
                  wLength = love.exedit._readUInt(lvl3_entry.Data, vfi_start, 2),
                  wValueLength = love.exedit._readUInt(lvl3_entry.Data, vfi_start+2, 2),
                  wType = love.exedit._readUInt(lvl3_entry.Data, vfi_start+4, 2), -- will be 1, as love uses text data for the info
                  szKey =  lvl3_entry.Data:sub(vfi_start+6, vfi_start+35), -- 'VarFileInfo'
                  padding = love.exedit._readUInt(lvl3_entry.Data, vfi_start+36, 2)
                }
                -- check things that should always be asserted
                if stringfileinfo.wValueLength == 0 and varfileinfo.wValueLength == 0 then
                  print('love.exedit >       StringFileInfo', stringfileinfo.szKey)
                  print('love.exedit >       VarFileInfo', varfileinfo.szKey)

                  local stringtabledata = lvl3_entry.Data:sub(sfi_start, sfi_start+stringfileinfo.wLength-1)
                  if not debug_mode then love.filesystem.write('testing2', stringtabledata) end
                  local st_start = 37
                  --if not debug_mode then love.filesystem.write('testing2', stringtabledata) end
                  -- now we need to get the actual stringtable under stringfileinfo for the data
                  local stringtable = {
                    wLength = love.exedit._readUInt(stringtabledata, st_start, 2),
                    wValueLength = love.exedit._readUInt(stringtabledata, st_start+2, 2),
                    wType = love.exedit._readUInt(stringtabledata, st_start+4, 2),
                    -- windows docs list this as a WCHAR 8-digit hexadecimal number so 16 bytes
                    szKey = stringtabledata:sub(st_start+6, st_start+21),
                    padding = love.exedit._readUInt(stringtabledata, st_start+22, 2),
                  }
                  print('love.exedit >         StringTable', stringtable.wLength, stringtable.wValueLength, stringtable.wType, stringtable.szKey, stringtable.padding)

                  if stringtable.wValueLength == 0 and stringtable.wType == 1 then
                    -- psych! we have to go another level deeper for the actual string :)
                    -- we also just have to loop through the data as we have no start/stop just the length of the stringtable 
                    if debug_mode then
                      love.exedit._readStringTable(stringtabledata, st_start+24, stringtable.wLength-24, {})
                    else

                      -- we replace the StringTable with our own table containing the data 
                      -- set by the user 
                      local dname = love.exedit._writeWord(love.build.opts.name .. ' by ' .. love.build.opts.developer)
                      local dver = love.exedit._writeWord(love.build.opts.version)
                      local newdesc = stringtabledata:sub(1, 37+23)

                      -- @TODO
                      -- using FileVersion or ProductVersion keywords doesnt actually overwrite the version shown in the tooltip of the exe
                      -- not sure where that version comes from, must be set somewhere else
                      -- i think possibly the fixedfileinfo
--
                      newdesc = newdesc .. love.data.pack('string', '<i2', 38 + 4 + #dname) -- length of whole string obj
                      newdesc = newdesc .. love.data.pack('string', '<i2', #dname/2) -- length of actual data in WORD (string len/2)
                      newdesc = newdesc .. love.data.pack('string', '<i2', 1) -- type 1 (text)
                      newdesc = newdesc .. 'F i l e D e s c r i p t i o n ' -- keyword
                      newdesc = newdesc .. love.data.pack('string', '<i2', 0) -- padding (0)
                      newdesc = newdesc .. '  ' .. dname .. '  '
                      print('love.exedit >         String', 'FileDescription', dname, #dname)
--
                      newdesc = newdesc .. love.data.pack('string', '<i2', 30 + 4 + #dver) -- length of whole string obj
                      newdesc = newdesc .. love.data.pack('string', '<i2', #dver/2) -- length of actual data in WORD (string len/2)
                      newdesc = newdesc .. love.data.pack('string', '<i2', 1) -- type 1 (text)
                      newdesc = newdesc .. 'F i l e V e r s i o n ' -- keyword
                      newdesc = newdesc .. love.data.pack('string', '<i2', 0) -- padding (0)
                      newdesc = newdesc .. '  ' .. dver .. '  '
                      print('love.exedit >         String', 'FileVersion', dver, #dver)
--
                      newdesc = newdesc .. love.data.pack('string', '<i2', 36 + 4 + #dver) -- length of whole string obj
                      newdesc = newdesc .. love.data.pack('string', '<i2', #dver/2) -- length of actual data in WORD (string len/2)
                      newdesc = newdesc .. love.data.pack('string', '<i2', 1) -- type 1 (text)
                      newdesc = newdesc .. 'P r o d u c t V e r s i o n ' -- keyword
                      newdesc = newdesc .. love.data.pack('string', '<i2', 0) -- padding (0)
                      newdesc = newdesc .. '  ' .. dver .. '  '
                      print('love.exedit >         String', 'ProductVersion', dver, #dver)

                      local padding = #stringtabledata - #newdesc
                      newdesc = newdesc .. string.rep(' ', padding)
                      print('love.exedit >         Space remaining:', padding)

                      local prefix = new_data:sub(1, rsrc_data_index+lvl3_entry.Position-2)
                      local newdata = lvl3_entry.Data:sub(1, sfi_start-1) .. newdesc .. lvl3_entry.Data:sub(sfi_start+stringfileinfo.wLength-1, lvl3_entry.DataSize-1)
                      love.filesystem.write('testing', newdesc)
                      local suffix = new_data:sub(rsrc_data_index+lvl3_entry.Position-2+lvl3_entry.DataSize+1, #new_data)
                      new_data = prefix .. newdata .. suffix
                    
                    end
                  end
                end


              end

              -- @TODO if editing the icons properly we'll need to change the GROUP_ICON values, see below
              if lvl1_type == 'GROUP_ICON' then
                local gi_header = love.exedit._readDataType(lvl3_entry.Data, 1, 'GROUP_ICON_HEADER')
                if gi_header ~= nil then
                  print('love.exedit >     GROUP_ICON_HEADER', gi_header.Reserved, gi_header.IdType, gi_header.IdCount)
                  for gi=1,gi_header.IdCount do
                    local offset = 7 + ((gi-1)*14)
                    local gi_entry = love.exedit._readDataType(lvl3_entry.Data, offset, 'GROUP_ICON_ENTRY')
                    if gi_entry ~= nil then
                      local gi_size = math.abs(gi_entry.Width)
                      if gi_size == 0 then gi_size = 256 end -- only stores 0-255, cant have 0 so 256 is 0
                      print('love.exedit >       GROUP_ICON_ENTRY', tostring(gi_size) .. 'px', gi_entry.Id, gi_entry.BytesInRes, offset)
                    end
                  end
                end
              end

              -- @TODO currently this is very hacky but it does work
              -- the default love icon is quite large compared to PNG data so we can just insert 
              -- our PNG data and pad the rest 

              -- if we want to do this properly, we will not only need to update the GROUP_ICON
              -- but ALL resource headers, and section headers because all positions will change
              -- we'll also need to implement and recalc the checksum from the COFF

              -- this will have to be done at some point cos there's not much room anymore
              if lvl1_type == 'ICON' then
                local newdata = ico_icon:_resize(ico_img, ico_sizes[l2]):getString()
                local padding = lvl3_entry.DataSize - #newdata
                if #newdata > lvl3_entry.DataSize then
                  print('love.exedit >       WARN: icon png bigger, reducing', ico_sizes[l2], lvl3_entry.DataSize, #newdata)
                  newdata = ico_icon:_resize(ico_img, ico_sizes[l2]*0.75):getString()
                  padding = lvl3_entry.DataSize - #newdata
                end
                if #newdata > lvl3_entry.DataSize then
                  print('love.exedit >       WARN: icon png bigger than available size', ico_sizes[l2], lvl3_entry.DataSize, #newdata)
                end
                if padding < 0 then
                  newdata = newdata:sub(1, lvl3_entry.DataSize)
                  padding = 0
                end
                local prefix = new_data:sub(1, rsrc_data_index+lvl3_entry.Position-2)
                local newimg = newdata .. string.rep(' ', padding)
                local suffix = new_data:sub(rsrc_data_index+lvl3_entry.Position-2+lvl3_entry.DataSize+1, #new_data)
                print('love.exedit >       ICON_ENTRY', rsrc_data_index+lvl3_entry.Position-2, ico_sizes[l2], #newdata, lvl3_entry.DataSize, padding)
                new_data = prefix .. newimg .. suffix
              end

            end
          end
        end
      end
    end

    -- return the modified data
    if #data ~= #new_data then
      print('love.exedit > new data doesnt match expected', #data, #new_data)
    end
    print('love.exedit > file modified successfully')
    return new_data

  end,


  -- reads the root resource directory and all subdirectories
  -- this will give a 3 tier structure for various resources
  _readResourceDirectory = function(data, base, start, tabs, level, table_size)
    if tabs == nil then tabs = '' end
    if start == -1 then return nil end
    if level == nil then level = 1 end

    local rd = love.exedit._readDataType(data, start, 'RESOURCE_DIRECTORY')
    rd.Entries = {}
    if rd == nil then
      return print(tabs .. 'ERR_INCORRECT_RESOURCE_DIRECTORY')
    end
    -- char is reserved to 0, 'sensible' entry limit
    if rd.Characteristics ~= 0 or rd.NumberOfIdEntries+rd.NumberOfNamedEntries > 4096 then
      return print(tabs .. 'ERR_INVALID_RESOURCE_DIRECTORY', rd.Characteristics, rd.NumberOfIdEntries)
    end
    local read_to = rd.NumberOfIdEntries+rd.NumberOfNamedEntries
    local read_from = 1
    for r=read_from,read_to do
      local offset = start + 16 + ((r-1)*8)
      local rde = love.exedit._readDataType(data, offset, 'RESOURCE_DIRECTORY_ENTRY')
      if rde ~= nil then 
        -- if is_id == 0 that means we actually have a string name
        -- the value given is an offset into the resource string table
        local is_string =   bit.rshift(bit.band(rde.Name, 0x80000000), 31)
        local string_offset = bit.band(rde.Name, 0x7FFFFFFF)
        -- if has_dir == 1 then this entry is a subdirectory pointer
        -- as such we should follow the offset set in first_bit to find the next dir
        local has_dir =    bit.rshift(bit.band(rde.DataOffset, 0x80000000), 31)
        local first_bit =   bit.band(rde.DataOffset, 0x7FFFFFFF)
        if has_dir == 1 then
          rde.SubDirectory = love.exedit._readResourceDirectory(data, base, base+first_bit, tabs .. '  ', level+1, table_size)
        else
          local de = love.exedit._readDataType(data, base+first_bit, 'RESOURCE_DATA_ENTRY')
          if de == nil then
            print(tabs .. '    ERR_INVALID_RESOURCE_DATA_ENTRY')
          else
            -- offset of the entry is offset by the table size from the dd 
            local doffset = de.DataOffset - table_size + 1
            local dentry = data:sub(doffset, doffset + de.DataSize-1)
            -- add our actual resource data along with position for modifying later
            rde.DataSize = de.DataSize
            rde.Data = dentry
            rde.Position = doffset
          end
        end
        table.insert(rd.Entries, rde)
      end
    end
    return rd
  end,

  -- reads a data directory entry from the COFF header
  -- this is just a windows DWORD (4 byte + 4 byte) with pointer + size
  _readDataDirectory = function(name, data, start)
    local data_directory = data:sub(start, start+7)
    local virtual_address = love.data.unpack('<i4', data_directory:sub(1, 4))
    local byte_size = love.data.unpack('<i4', data_directory:sub(5, 8))
    return {
      rva = virtual_address,
      size = byte_size
    }
  end,

  -- reads data from the index as a given type (from above)
  _readDataType = function(data, index, type)
    -- check mapping
    local mapping = love.exedit._DATA_TYPES[type]
    if mapping == nil then
      print('error: undefined type', type)
      return nil
    end
    -- work out total length
    local type_length = 0
    for m=1,#mapping do
      type_length = type_length + mapping[m][2]
    end
    local type_data = data:sub(index, index+type_length-1)
    -- run through each field of the type
    local result = {}
    local mapping_index = 1
    for m=1,#mapping do
      local field = mapping[m]
      -- if this failed something is wrong, index is off etc
      -- so fail the whole thing
      local ok, err = pcall(love.exedit._readUInt, type_data, mapping_index, field[2])
      if ok then
        result[field[1]] = love.exedit._readUInt(type_data, mapping_index, field[2])
        mapping_index = mapping_index + field[2]
      else 
        return nil
      end
    end
    return result
  end,

  -- reads the strings from a stringtable
  -- mainly just used for debugging stuff to reverse engineer
  _readStringTable = function(data, offset, total, results)
    local str_start = offset
    local sz_size = 30
    if total == 442 then sz_size = 22 end
    if total == 394 then sz_size = 22 end -- CompanyName
    if total == 308 then sz_size = 28 end -- LegalCopyright
    local str = {
      wLength = love.exedit._readUInt(data, str_start, 2),
      wValueLength = love.exedit._readUInt(data, str_start+2, 2),
      wType = love.exedit._readUInt(data, str_start+4, 2),
      szKey = data:sub(str_start+6, str_start+6+sz_size-1),
      padding = love.exedit._readUInt(data, str_start+6+sz_size, 2),
    }
    local strv = data:sub(str_start+7+sz_size+str.padding, str_start+7+sz_size+str.padding+(str.wValueLength*2)-1)
    local realKey = str.szKey:gsub(' ', '')
    print('love.exedit >           String', str.wLength, str.wValueLength, str.wType, str.szKey, realKey, #realKey, str.padding, strv, #strv)
    results[str.szKey] = strv
    total = total - str.wLength
    if total > 0 and str.wLength > 0 then
      love.exedit._readStringTable(data, offset+str.wLength, total, results)
    else
      return results
    end
    
  end,
 
 
  -- reads the data from a given index as a UInt
  _readUInt = function(data, index, size)
    return love.data.unpack('<i' .. tostring(size), data:sub(index, index + (size-1)))
  end,

  -- turns a string into a windows WORD
  _writeWord = function(str)
    local word = ''
    for i = 1, #str do
      local c = str:sub(i,i)
      word = word .. c .. ' '
    end
    return word
  end,

 
  -- datatypes to use with readDataType
  _DATA_TYPES = {
    RESOURCE_DIRECTORY = {
      { 'Characteristics', 4 },
      { 'TimeDateStamp', 4 },
      { 'MajorVersion', 2 },
      { 'MinorVersion', 2 },
      { 'NumberOfNamedEntries', 2 },
      { 'NumberOfIdEntries', 2 }
    },
    RESOURCE_DIRECTORY_ENTRY = {
      { 'Name', 4 },
      { 'DataOffset', 4}
    },
    RESOURCE_DATA_ENTRY = {
      { 'DataOffset', 4 },
      { 'DataSize', 4 },
      { 'CodePage', 4 },
      { 'Reserved', 4 }
    },
    GROUP_ICON_HEADER = {
      { 'Reserved', 2 },
      { 'IdType', 2 },
      { 'IdCount', 2 }
    },
    GROUP_ICON_ENTRY = {
      { 'Width', 1 },
      { 'Height', 1 },
      { 'ColorCount', 1 },
      { 'Reserved', 1 },
      { 'Planes', 2 },
      { 'BitCount', 2 },
      { 'BytesInRes', 4 },
      { 'Id', 2 }
    },
    FIXED_FILE_INFO = {
      { 'Signature', 4 },
      { 'StrucVersion', 4 },
      { 'FileVersionMS', 4 },
      { 'FileVersionLS', 4 },
      { 'ProductVersionMS', 4 },
      { 'ProductVersionLS', 4 },
      { 'FileFlagsMask', 4 },
      { 'FileFlags', 4 },
      { 'FileOS', 4 },
      { 'FileType', 4 },
      { 'FileSubtype', 4 },
      { 'FileDateMS', 4 },
      { 'FileDateLS', 4 },
    }
  },

  _RESOURCE_TYPES = { 
    "CURSOR", "BITMAP", "ICON", "MENU", "DIALOG", "STRING", "FONTDIR", "FONT",
    "ACCELERATOR", "RCDATA", "MESSAGETABLE", "GROUP_CURSOR", "UNUSED_13",
    "GROUP_ICON", "UNUSED_15", "VERSION", "DLGINCLUDE", "UNUSED_18", "PLUGPLAY",
    "VXD", "ANICURSOR", "ANIICON", "HTML", "MANIFEST"
  }

}
