--[[
  @lib  - love-squashfs
  @desc - lua squashfs compressing/decompressing that works cross platform 
          and can handle symlinks, built for use with LÖVE 11.X+
  @url - https://github.com/ellraiser/love-squashfs
  @license - MIT
  ]]

-- format taken from the following pages:
-- https://dr-emann.github.io/squashfs/squashfs.html
-- https://dr-emann.github.io/squashfs/
-- https://www.kernel.org/doc/Documentation/filesystems/squashfs.txt
-- glhf


local bit = require('bit')


love.squashfs = {


  --[[
    @method - love.squashfs:newSquashFS()
    @desc - creates a new squashfs instance for compressing/decompress
    @param {bool} manual_symlink - whether symlinks should be stored to the inst
                                   rather than actually created, used by love-build
                                   to work around mklink needing sysadmin on windows
    @return {userdata} - returns the new icon obj to use
    ]]
  newSquashFS = function(self, manual_symlink)
    local squashcls = {
      manual_symlink = manual_symlink or false,
      symlinks = {}
    }
    setmetatable(squashcls, self)
    self.__index = self
    return squashcls
  end,


  --[[
    @method = SquashFS:compress()
    @desc - compresses a target folder into squashfs format
    @param {string} target - target folder to compress
    @param {string} output - output path/file
    @return {bool,string} - returns true/false for success and error if any
    ]]

  -- @NOTE currently broken, I think the padding after id_table is causing issues
  -- for unsquash readers

  compress = function(self, target, output)
    
    print('love.squashfs > compressing: "' .. target .. '"')
    
    -- get all the target folder entries and map each to an inode number
    -- this also sets the parent inodes for each so we have that ready
    -- we also need a special additional 'root' entry
    local inode_paths, inode_count = self:_readDirectory(target)
    inode_count = inode_count + 1
    local root_info = love.filesystem.getInfo(target)
    table.insert(inode_paths, {
      name = '',
      path = target,
      type = 'directory',
      number = inode_count,
      modtime = root_info.modtime,
      parent = 0,
      root = true,
      root_inode = true
    })

    -- pick a sensible blocksize
    local block_size = 131072
    print('love.squashfs > inodes read: ' .. tostring(#inode_paths) .. '/' .. inode_count)

    -- quick reference for love type => squashfs inode type
    local inode_types = {
      directory = 1,
      file = 2,
      symlink = 3
    }

    -- used to setup directory entry indices early
    local dir_offset = 0
    local inode_offset = 0
    local data_table_offset = 0
    local block_table_data = ''
    local inode_table_data = ''
    local inode_path_map = {}
    local symcount = 0
    local filecount = 0

    -- then we can make an actual inode entry for each inode given
    for i=1,#inode_paths do
      local item = inode_paths[i]
      local inode = ''

      -- set the common header first
      local inode_type = inode_types[item.type]
      item.inode_type = inode_type
      item.permissions = 493
      item.uid = 0
      item.gid = 0
      item.inode_offset = inode_offset
      inode_path_map[item.path] = { inode_offset, item.number }
      inode = inode .. love.data.pack('string', '<i2', inode_type) -- u16 type
      inode = inode .. love.data.pack('string', '<i2', 493) -- u16 perms
      inode = inode .. love.data.pack('string', '<i2', 0) -- u16 uid
      inode = inode .. love.data.pack('string', '<i2', 0) -- u16 gid
      inode = inode .. love.data.pack('string', '<i4', item.modtime) -- u32 modtime
      inode = inode .. love.data.pack('string', '<i4', item.number) -- u32 inode number

      -- directory inodes
      if item.type == 'directory' then
        -- although dynamic we can get the directory entry length now
        -- we'll need a second pass to write the actual entries using inode offsets
        local raw_entries = love.filesystem.getDirectoryItems(item.path)
        local entries = {}
        -- ignore any ds_store that might exist on mac
        for r=1,#raw_entries do
          if raw_entries[r] ~= '.DS_Store' then table.insert(entries, raw_entries[r]) end
        end
        local raw_entry_count = #entries
        -- empty directories still have 1 entry for themselves
        if #entries == 0 then table.insert(entries, '$SELF$') end
        -- calc length as 12 + (8*entry) + (N*entry) where N is entry name len
        local dir_entry_len = 12
        for e=1,#entries do
          local entry_name = entries[e]
          if entries[e] == '$SELF$' then entry_name = item.name end
          dir_entry_len = dir_entry_len + 8 + #entry_name
        end
        -- set directory properties
        item.block_index = 0
        item.link_count = 2 + raw_entry_count
        item.file_size = dir_entry_len + 3
        item.block_offset = dir_offset
        item.parent_inode = item.parent
        inode = inode .. love.data.pack('string', '<i4', 0) -- u32 block index
        inode = inode .. love.data.pack('string', '<i4', 2 + raw_entry_count) -- u32 link_count
        inode = inode .. love.data.pack('string', '<i2', dir_entry_len + 3) -- u16 link_count
        inode = inode .. love.data.pack('string', '<i2', dir_offset) -- u16 block offset
        inode = inode .. love.data.pack('string', '<i4', item.parent) -- u32 parent inode
        -- update offset for next dir entry
        dir_offset = dir_offset + dir_entry_len

      -- symlink inodes
      elseif item.type == 'symlink' then
        -- resolve actual symlink path
        -- @TODO currently only works for symlinks in the same folder
        -- which is all LOVE needs rn so 
        local symlink_path = self:_resolveSymlink(love.filesystem.getSaveDirectory() .. '/' .. item.path)
        local path = symlink_path:sub(symlink_path:find("/[^/]*$") + 1, #symlink_path)
        -- set symlink properties
        item.link_count = 0
        item.target_size = #path
        item.target_path = path
        inode = inode .. love.data.pack('string', '<i4', 0) -- u32 hard links
        inode = inode .. love.data.pack('string', '<i4', #path)
        inode = inode .. path
        symcount = symcount + 1

      -- file inodes
      else

        -- first calculate the blocks needed for this file
        -- if we only have a small bit of data we'll make it a fragment
        local filedata, filesize = love.filesystem.read(item.path)
        local blocks_needed = math.ceil(filesize / block_size)

        -- for all blocks required, create the data blocks needed
        -- as fragments are not technically required we can just use blocks for 
        -- all the data, even though it'd be more efficient to tail-end pack
        -- feel free to add all that code yaself lol
        local block_sizes = {}
        local bdata_written = 0
        local cdata_index = 0
        for b=1,blocks_needed do
          local bdata_offset = (b-1) * block_size
          local bdata_size = block_size + 0
          if b == blocks_needed then bdata_size = #filedata - bdata_written end
          local bdata = filedata:sub(bdata_offset + 1, bdata_offset + bdata_size)
          local cdata = love.data.compress('string', 'zlib', bdata)
          bdata_written = bdata_written + #bdata
          block_table_data = block_table_data .. cdata
          table.insert(block_sizes, love.data.pack('string', '<i4', #cdata))
          cdata_index = cdata_index + #cdata
        end

        item.block_start = 96 + data_table_offset
        item.frag_index = -1
        item.block_offset = 0
        item.file_size = filesize
        item.block_sizes = block_sizes
        inode = inode .. love.data.pack('string', '<i4', item.block_start)
        inode = inode .. love.data.pack('string', '<i4', item.frag_index)
        inode = inode .. love.data.pack('string', '<i4', item.block_offset)
        inode = inode .. love.data.pack('string', '<i4', item.file_size)
        inode = inode .. table.concat(block_sizes, '')
        filecount = filecount + 1

        data_table_offset = data_table_offset + cdata_index

      end
      inode_offset = inode_offset + #inode + 1
      inode_table_data = inode_table_data .. inode
    end

    -- now for each of the inodes we need to make the actual directory entry
    local dir_count = 0
    local dir_table_data = ''
    for i=1,#inode_paths do
      local item = inode_paths[i]
      if item.type == 'directory' then
        -- we need to make the directory entry now for real 
        local raw_entries = love.filesystem.getDirectoryItems(item.path)
        local entries = {}
        for r=1,#raw_entries do
          if raw_entries[r] ~= '.DS_Store' then table.insert(entries, raw_entries[r]) end
        end
        local dir_entry = ''
        dir_entry = dir_entry .. love.data.pack('string', '<i4', #entries - 1) -- u32 count 
        dir_entry = dir_entry .. love.data.pack('string', '<i4', 0) -- u32 start block
        dir_entry = dir_entry .. love.data.pack('string', '<i4', 0) -- u32 inode_offset
        -- add entry for each item (should already be alphabetical from love)
        if #entries == 0 then
          table.insert(entries, '$SELF$')
        end
        for e=1,#entries do
          local entry_path = item.path .. '/' .. entries[e]
          local entry_name = entries[e]
          if entries[e] == '$SELF$' then
            entry_path = item.path
            entry_name = item.name
          end
          local entry_info = love.filesystem.getInfo(entry_path)
          local entry_type = 1
          if entry_info.type == 'file' then entry_type = 2 end
          if entry_info.type == 'symlink' then entry_type = 3 end

          -- as we have proicessed every inode, we should be able to get the matching inode
          -- and pull the offset + inode numbers from it
          local match = inode_path_map[entry_path]

          -- add entry contents
          dir_entry = dir_entry .. love.data.pack('string', '<i2', match[1]) -- u16 offset
          dir_entry = dir_entry .. love.data.pack('string', '<i2', match[2]) -- u16 inode offset
          dir_entry = dir_entry .. love.data.pack('string', '<i2', entry_type) -- u16 type
          dir_entry = dir_entry .. love.data.pack('string', '<i2', #entry_name - 1) -- u16 name size
          dir_entry = dir_entry .. entry_name
        end

        -- add to dir table
        dir_table_data = dir_table_data .. dir_entry
        dir_count = dir_count + 1

      end
    end

    print('love.squashfs > compressing ' .. tostring(filecount) .. ' files')
    print('love.squashfs > compressing ' .. tostring(dir_count) .. ' directories')
    print('love.squashfs > compressing ' .. tostring(symcount) .. ' symlinks')

    -- for the id table we need to add one id entry to the id_table
    -- all the inodes are using the same one (1000)
    -- however unclear on how these are to be stored


    print('love.squashfs > writing data')

    -- add block data
    local archive_data = ''
    archive_data = archive_data .. block_table_data

    -- add inode metadata
    local inode_table_index = #archive_data + 96
    local inode_metadata = self:_writeMBlock(inode_table_data)
    archive_data = archive_data .. inode_metadata

    -- add dir metadata
    local dir_table_index = #archive_data + 96
    archive_data = archive_data .. self:_writeMBlock(dir_table_data)

    -- to support NFS add an export table, which has an 8 byte ref for each inode
    -- this allows for quick reading of inodes
    -- @TODO get correct value
    local root_inode_ref = ''
    local export_table_data = ''
    for i=1,#inode_paths do
      -- Entries in the Inode table are referenced with u64 values (8 bytes)
      -- The upper 16 bits are unused. 
      -- The next 32 bits are the position of the first byte of the metadata block, 
      -- relative to the start of the inode table. 
      -- The lower 16 bits describe the (uncompressed) offset within the metadata 
      -- block where the inode begins
      local inode_ref = 
        love.data.pack('string', '<i2', 0) ..
        love.data.pack('string', '<i4', 0) ..
        love.data.pack('string', '<i2', inode_paths[i].inode_offset)
      if inode_paths[i].root_inode == true then
        root_inode_ref = inode_ref
      end
      export_table_data = export_table_data .. inode_ref
    end
    -- export data needs to have the actual export metadata block
    -- followed by the index to the block at the export_table_index
    local export_metadata = self:_writeMBlock(export_table_data)
    archive_data = archive_data .. export_metadata
    local export_table_index = #archive_data + 96
    archive_data = archive_data ..
      love.data.pack('string', '<i8', export_table_index - #export_metadata)

    -- metadatablocks for export + id table can be looser in their location
    -- however when reading tables, squashfs will use a lower limit and upper limit
    -- if the metadata block index is outside then it will be seen as out of bounds
    -- lower_limit The lowest "sane" position at which to expect a meta
    -- we pad here a few bytes to make sure we get seen as a valid position
    archive_data = archive_data .. '    '

    -- the id_table_index should point to the position where we encode the 
    -- index for the id metadata block
    local id_table_data = love.data.pack('string', '<i4', 128)
    local id_metadata = self:_writeMBlock(id_table_data, false)
    archive_data = archive_data .. id_metadata
    local id_table_index = #archive_data + 96
    archive_data = archive_data ..
      love.data.pack('string', '<i8', id_table_index - #id_metadata)
    archive_data = archive_data .. '    ' -- see above padding

    -- https://dr-emann.github.io/squashfs/#superblock-flags
    -- 0x0010, fragments not used
    -- 0x0080, NFS supported
    -- 0x0200, no xattrs 
    local flags = 0x0290

    -- @TODO setting this to what i think is correct breaks rdsquashfs from ng-tools
    -- ptting back to 0 will read the file but only love.svg, which is probably
    -- the first file?
    local root_inode = love.data.pack('string', '<i8', 0) --root_inode_ref

    local superblock = 'hsqs'
    superblock = superblock .. love.data.pack('string', '<i4', #inode_paths) -- u32 inode count
    superblock = superblock .. love.data.pack('string', '<i4', love.timer.getTime()) -- u32 mod time
    superblock = superblock .. love.data.pack('string', '<i4', block_size) -- u32 block size
    superblock = superblock .. love.data.pack('string', '<i4', 0) -- u32 frag count
    superblock = superblock .. love.data.pack('string', '<i2', 1) -- u16 compressor, 1 = GZIP
    superblock = superblock .. love.data.pack('string', '<i2', 17) -- u16 block log
    superblock = superblock .. love.data.pack('string', '<i2', flags) -- u16 flags
    superblock = superblock .. love.data.pack('string', '<i2', 1) -- u16 id count
    superblock = superblock .. love.data.pack('string', '<i2', 4) -- u16 major version
    superblock = superblock .. love.data.pack('string', '<i2', 0) -- u16 minor version
    superblock = superblock .. root_inode -- u64 root inode id
    superblock = superblock .. love.data.pack('string', '<i8', #archive_data + 96) -- u64 bytes used
    superblock = superblock .. love.data.pack('string', '<i8', id_table_index) -- u64 id table index
    superblock = superblock .. love.data.pack('string', '<i8', -1) -- u64 xattr table index
    superblock = superblock .. love.data.pack('string', '<i8', inode_table_index) -- u64 id table index
    superblock = superblock .. love.data.pack('string', '<i8', dir_table_index) -- u64 id table index
    superblock = superblock .. love.data.pack('string', '<i8', -1) -- u64 frag table index
    superblock = superblock .. love.data.pack('string', '<i8', export_table_index) -- u64 export table index

    -- @TODO add padding to match multiple of block size?
    -- have seen this mentioned but not actually implemented
    local final_data = superblock .. archive_data

    -- write final data
    local success, err = love.filesystem.write(output, final_data)
    print('love.squashfs > compressed to: "' .. output .. '"')
    return success, err

  end,


  --[[
    @method - SquashFS:decompress()
    @desc - decompresses a squashfs binary into an output folder
    @param {string} target - path to squashfs binary
    @param {string} output - output folder to unsquash to
    @return {bool,string} - returns true/false for success and err if any
    ]]
  decompress = function(self, target, output)

    -- read the target binary file to start with
    local data = love.filesystem.read(target)
    print('love.squashfs > decompressing: "' .. target .. '", ' .. tostring(#data) .. ' bytes')

    -- first read the superblock, 96bytes
    local magic = data:sub(1, 4)
    if magic ~= 'hsqs' then
      print('love.squashfs > ERRO: this is not a squashfs binary file')
      return nil, 'Error: Invalid squashfs binary'
    end
    local inode_count = self:_readUInt32(data,  5)
    local mod_time =    self:_readUInt32(data,  9)
    local block_size =  self:_readUInt32(data, 13)
    local frag_count =  self:_readUInt32(data, 17)
    local compressor =  self:_readUInt16(data, 21)
    if compressor ~= 1 then
      print('love.squashfs > ERRO: unsupported compression type', compressor)
      return nil, 'Error: Unsupported compression type: ' .. tostring(compressor)
    end
    local block_log = self:_readUInt16(data, 23)
    if math.log(block_size, 2) ~= block_log then
      print('love.squashfs > ERRO: block log doesnt match block size')
      return nil, 'Error: Corrupted squashfs archive'
    end
    local flags =         self:_readUInt16(data, 25)
    local idcount =       self:_readUInt16(data, 27)
    local major_version = self:_readUInt16(data, 29)
    local minor_version = self:_readUInt16(data, 31)
    if major_version ~= 4 and minor_version ~= 0 then
      local actual = tostring(major_version) .. '.' .. tostring(minor_version)
      print('love.squashfs > WARN: invalid version, should be 4.0 but read ' .. actual)
      return nil, 'Error: Invalid version for squashfs: ' .. actual
    end
    local root_inode =    self:_readUInt64(data, 33)
    local bytes_used =    self:_readUInt64(data, 41)
    local id_table =      self:_readUInt64(data, 49)
    local xattr_table =   self:_readUInt64(data, 57)
    local inode_table =   self:_readUInt64(data, 65)
    local dir_table =     self:_readUInt64(data, 73)
    local frag_table =    self:_readUInt64(data, 81)
    local export_table =  self:_readUInt64(data, 89)

    --print(
    --  'inode_table: ' .. tostring(inode_table) .. '\n' ..
    --  'dir_table: ' .. tostring(dir_table) .. '\n' ..
    --  'frag_table: ' .. tostring(frag_table) .. '\n' ..
    --  'export_table: ' .. tostring(export_table) .. '\n' ..
    --  'id_table: ' .. tostring(id_table) .. '\n' ..
    --  'xattr_table: ' .. tostring(xattr_table) .. '\n' ..
    --  'bytes_used: ' .. tostring(bytes_used)
    --)

    -- handle id tables, just so we know whats expected for reverse-engineering
    -- if we read the value at that position we get 1024
    local id_block_index = self:_readUInt64(data, id_table+1)
    local id_metadata = self:_readMBlock(data, id_block_index)
    print(id_block_index, #id_metadata)
    for ii=1,idcount do
      local start = 1+((ii-1)*4)
      local val = id_metadata:sub(start, start+3)
      local offset = self:_readUInt32(val, 1)
      print('love.squashfs > id: ', offset)
    end

    -- handle export table parsing for now, more just to sense check what we make
    -- but could use this to make the later stuff more efficient
    if export_table ~= -1 then
      local export_table_data = data:sub(export_table+1, id_table)
      local export_block_index = self:_readUInt64(export_table_data, 1)
      local export_metadata = self:_readMBlock(data, export_block_index+1)
      local export_ids = 0
      for ei=1,inode_count do
        local start = 1+((ei-1)*8)
        local val = export_metadata:sub(start, start+7)
        local offset = self:_readUInt64(val, 1)
        if offset ~= nil then export_ids = export_ids + 1 end
      end
      print('love.squashfs > export table read: ' .. tostring(export_ids) .. '/' .. tostring(inode_count))
    end


    print('love.squashfs > block size: ', block_size)

    -- process fragment table to read fragment table entries/headers
    local fragment_table_data = data:sub(frag_table + 1, export_table)
    local fragment_blocks = math.ceil(frag_count / 512)
    local fragment_headers = {}
    -- 1 fragment metadatablock can hold 512 fragment header entries
    for fblock=1,fragment_blocks do
      local fblock_offset = 16 * (fblock-1)
      -- read the fragment block metadata, decompressing into a list of fragment headers
      local entry_start = self:_readUInt64(fragment_table_data, 1+fblock_offset)
      local mblock_data = self:_readMBlock(data, entry_start+1)
      local fragments = #mblock_data / 16
      if #mblock_data % 16 ~= 0 then
        print('love.squahsfs > WARN: incorrect fragment metadatablock size', #mblock_data)
      end
      -- read each fragment header, and get the fragment data from the binary
      for frag=1,fragments do
        local frag_offset = 16 * (frag-1)
        local fragment_header =   mblock_data:sub(1 + frag_offset, 16 + frag_offset)
        local fragment_start =    self:_readUInt64(fragment_header, 1)
        local fragment_size =     self:_readUInt32(fragment_header, 9)
        local fragment_unused =   self:_readUInt32(fragment_header, 13)
        local fragment_data = data:sub(fragment_start + 1, fragment_start + fragment_size)
        -- not all fragments need to be compressed if they're < than the block size
        if pcall(love.data.decompress, 'string', 'zlib', fragment_data) then
          fragment_data = love.data.decompress('string', 'zlib', fragment_data)
        end
        if fragment_unused ~= 0 then
          print('love.squashfs > WARN: invalid fragment entry!')
        end
        -- save for later for quick lookups
        table.insert(fragment_headers, {
          start = fragment_start,
          size = fragment_size,
          data = fragment_data,
          offset = 1 + frag_offset
        })
      end
    end
    if frag_count ~= #fragment_headers then
      print('love.squashfs > WARN: frag header count doesnt match superblock')
    end

    -- process directory metadata table to read directory table entries/headers
    local dir_end = frag_table
    if frag_table == -1 then dir_end = export_table end
    if export_table == -1 then dir_end = id_table end
    local dir_table_data = data:sub(dir_table+1, dir_end)
    local dir_blocks = math.ceil(#dir_table_data/ 8000)
    if dir_blocks > 1 then
      print('love.squashfs > TODO: handle multiple dir table blocks')
    end
    local dir_mblock_data = self:_readMBlock(dir_table_data, 1)
    print('love.squashfs > directory data: ', #dir_table_data, #dir_mblock_data)

    -- read inodes from inode table
    -- inodes are stored like all metadata in squashfs, i.e. split into 8kb blocks
    -- and compressed individually. each block starts with a 16 byte data size, 
    -- followed by the data for that block
    local inode_table_data = data:sub(inode_table+1, dir_table)
    local inode_blocks = math.ceil(#inode_table_data / 8000)
    local inode_data = self:_readMBlock(inode_table_data, 1)
    -- @TODO handle multiple inode metadatablocks
    if inode_blocks > 1 then
      print('love.squashfs > TODO: need to implement multiple inode metadatablocks')
    end

    -- with our uncompressed inode data we can then read the inode headers 
    -- each header starts with a 16 byte 'type' that tells use how long the 
    -- inode is and the properties we can expect - some header types like file 
    -- and symlink have a dynamic size based on another property so need to make
    -- sure to update offset correctly as we go
    local inode_headers = {}
    local inode_names = {}
    local parent_nodes = {}
    local offset = 0
    -- for each inode that should be in the file
    for n=1,inode_count do
      -- get basic data from the common inode header
      local node_type =   self:_readUInt16(inode_data, 1 + offset)
      local node_perms =  self:_readUInt16(inode_data, 3 + offset) -- perms as dec 
      local node_uid =    self:_readUInt16(inode_data, 5 + offset) -- seems to be 0?
      local node_gid =    self:_readUInt16(inode_data, 7 + offset) -- seems to be 0?
      local node_number = self:_readUInt16(inode_data, 13 + offset)
      local node_len =    self._inodeLength[node_type]
      if node_len == nil then
        print('love.squashfs > WARN: undefined node type', node_type)
      else
            
        -- basic directory
        if node_type == 1 then
          -- get directory properties
          local block_index =   self:_readUInt32(inode_data, 17 + offset)
          local link_count =    self:_readUInt32(inode_data, 21 + offset)
          local file_size =     self:_readUInt16(inode_data, 25 + offset) - 3
          local block_offset =   self:_readUInt16(inode_data, 27 + offset)
          local parent_inode =  self:_readUInt32(inode_data, 29 + offset)
          -- use data to get into the directory table metadata
          -- read data to get list of files for the directory inode 
          local dir_count = self:_readUInt32(dir_mblock_data, 1 + block_offset) + 1
          local dir_start = self:_readUInt32(dir_mblock_data, 5 + block_offset)
          local dir_inodes = self:_readUInt32(dir_mblock_data, 9 + block_offset)
          -- for each dir header entry we can get the actual name of the thing
          -- as well as a reference to it's parent inode 
          -- should always be at least 1 dir_count
          local dir_offset = 0
          local raw_data = 12
          for dinode=1,dir_count do
            -- read entry properties
            local dnode_offset = self:_readUInt16(dir_mblock_data, 13 + block_offset + dir_offset)
            local dnode_inode = self:_readUInt16(dir_mblock_data, 15 + block_offset + dir_offset)
            local dnode_type = self:_readUInt16(dir_mblock_data, 17 + block_offset + dir_offset)
            local dnode_namelen = self:_readUInt16(dir_mblock_data, 19 + block_offset + dir_offset)
            local dnode_name = dir_mblock_data:sub(21 + block_offset + dir_offset, 20 + block_offset + dir_offset + dnode_namelen+1)
            -- store reference to parent + name for inode
            if dnode_type > 15 then
              print('invalid directory entry')
              return nil, 'Error: Failed to parse directory entry'
            end
            parent_nodes[dir_inodes + dnode_inode] = node_number
            parent_nodes[node_number] = parent_inode
            inode_names[dir_inodes + dnode_inode] = dnode_name
            dir_offset = dir_offset + 8 + dnode_namelen+1
            raw_data = raw_data + 8 + #dnode_name
          end
          -- store the header entry for later
          table.insert(inode_headers, {
            name = '',
            path = '',
            ntype = 'dir',
            type = node_type,
            data = '',
            size = file_size,
            count = dir_count,
            raw = raw_data,
            number = node_number,
            parent_inode = parent_inode,
            perms = node_perms,
          })
    
        -- basic file
        elseif node_type == 2 then
          -- read file properties
          local block_start =   self:_readUInt32(inode_data, 17 + offset)
          local frag_index =    self:_readUInt32(inode_data, 21 + offset)
          local frag_offset =   self:_readUInt32(inode_data, 25 + offset)
          local file_size =     self:_readUInt32(inode_data, 29 + offset)
          -- calculate no. blocks needed for the file + any fragments
          local block_no = math.ceil(file_size / block_size)
          local tail_end = file_size % block_size
          if frag_index >= 0 then
            block_no = math.floor(file_size / block_size)
          end
          -- block sizes is a dynamic property, 4 bytes per block
          local block_sizes = block_no * 4
          local fragment_data = ''
          local file_data = ''
          -- check fragment if we have one
          -- sometimes files will just be stored as a fragment if the total file
          -- is < block_size, it's up to the squashfs implementation really
          if frag_index ~= -1 then
            local fragment_header = fragment_headers[frag_index + 1]
            local fragment_offset = -1
            local fragment_leading = 1
            if frag_offset == 0 then
              fragment_offset = 0
              fragment_leading = 0
            end
            -- read fragment using the headers we got earlier
            fragment_data = fragment_header.data:sub(
              frag_offset + fragment_leading, 
              frag_offset + fragment_leading + fragment_offset + tail_end
            )
          end
          -- if we have some blocks then read the block data 1 by 1
          if block_no > 0 then
            local fblock_start = block_start + 0
            for fblock=1,block_no do
              -- get block data
              local fblock_offset = (fblock-1)*4
              local fblock_size = self:_readUInt32(inode_data, 33 + offset + fblock_offset)
              -- sometimes the fblock_size might be read as greater than possible
              -- make sure to cap the block size otherwise things get messy
              if fblock_size > block_size then fblock_size = block_size end
              local fblock_cdata = data:sub(fblock_start+1, fblock_start+fblock_size)
              -- blocks do not have to be compressed, you could read from the size header
              -- but im lazy so just attempt to decompress and if we can we will
              local is_compressed = pcall(love.data.decompress, 'string', 'zlib', fblock_cdata)
              local fblock_data = fblock_cdata
              if is_compressed then
                fblock_data = love.data.decompress('string', 'zlib', fblock_cdata)
              end
              -- add block data to the file's data
              file_data = file_data .. fblock_data
              fblock_start = fblock_start + fblock_size
            end
          end
          -- final file will be all block data + fragment data
          -- sense check file data retrieved here
          local final_data = file_data .. fragment_data
          if file_size ~= #final_data then
            -- this shouldnt happen, if it did we've either lost data or added junk data
            print('love.squashfs > ERROR: file data doesnt match size expected', n, file_size, #final_data, file_size - #final_data)
            return nil
          end
          -- for the next inode header need to offset by the block size bytes
          -- as this will vary based on the file
          node_len = node_len + block_sizes
          table.insert(inode_headers, {
            name = '',
            path = '',
            ntype = 'fil',
            type = node_type,
            number = node_number,
            blocks = block_no,
            block_index = block_start,
            frag_index = frag_index,
            frag_offset = frag_offset,
            data = final_data,
            size = file_size,
            perms = node_perms,
          })

        -- basic symlink 
        elseif node_type == 3 then
          -- get symlink properties
          local symlink_size = self:_readUInt32(inode_data, 21 + offset)
          local symlink_path = inode_data:sub(offset + 25, offset + 24 + symlink_size)
          -- for the next inode header need to offset by the symlink path bytes
          node_len = node_len + symlink_size
          table.insert(inode_headers, {
            name = '',
            path = '',
            ntype = 'sym',
            type = node_type,
            number = node_number,
            data = symlink_path,
            size = symlink_size,
            perms = node_perms,
          })

        else
          print('love.squashfs > WARN: unimplemented node type', node_type)
          break
        end

        -- move to next inode header
        offset = offset + node_len

      end
    end

    print('love.squashfs > inodes parsed: ' .. tostring(#inode_headers) .. '/' .. tostring(inode_count))
    if #inode_headers ~= inode_count then
      return nil, 'Error: Failed to read all inodes: ' .. tostring(#inode_headers) .. '/' .. tostring(inode_count)
    end
    
    -- for each header, resolve the actual path of the file using our parent mappings
    -- then we can create the actual file/dir/symlink
    local files = 0
    local dirs = 0
    local syms = 0
    for i=1,#inode_headers do
      local inode = inode_headers[i]
      local number = inode.number
      -- get perms as common chmod number, i.e. 493 => 755
      local perms = self:_decToOct(inode.perms)
      -- get the name + the path
      inode.name = inode_names[number] or '' -- root inode will have no name
      inode.path = self:_resolveNodePath(parent_nodes, inode_names, number, inode_count, output)
      -- make the directory we need for the inode generally
      love.filesystem.createDirectory(inode.path)

      -- for normal files just write the data we decompressed
      if inode.ntype == 'fil' then
        love.filesystem.write(inode.path .. '/' .. inode.name, inode.data)
        -- print('> file', inode.name, #inode.data)
        local fullpath = love.filesystem.getSaveDirectory() .. '/' .. inode.path .. '/' .. inode.name
        if love.system.getOS() ~= 'Windows' then
          os.execute('chmod ' .. tostring(perms) .. ' "' .. fullpath .. '"')
        end
        files = files + 1

      -- for directories just make the new folder
      elseif inode.ntype == 'dir' then
        love.filesystem.createDirectory(inode.path .. '/' .. inode.name)
        local fullpath = love.filesystem.getSaveDirectory() .. '/' .. inode.path .. '/' .. inode.name
        if love.system.getOS() ~= 'Windows' then
          os.execute('chmod ' .. tostring(perms) .. ' "' .. fullpath .. '"')
        end
        dirs = dirs + 1
      end
    end

    -- now do symlinks as all our files are ready
    -- need to sort in order otherwise windows tries to symlink 
    -- thinks before they exist (when using syms of syms)
    table.sort(inode_headers, function(fa, fb)
      if #fa.data < #fb.data then return false end
      if #fa.data > #fb.data then return true end
      return false
    end)
    for i=1,#inode_headers do
      local inode = inode_headers[i]
      local number = inode.number
      -- get perms as common chmod number, i.e. 493 => 755
      local perms = self:_decToOct(inode.perms)
      -- get the name + the path
      inode.name = inode_names[number] or '' -- root inode will have no name
      inode.path = self:_resolveNodePath(parent_nodes, inode_names, number, inode_count, output)
      -- make the directory we need for the inode generally
      love.filesystem.createDirectory(inode.path)

      -- for symlinks we need to use terminal to set the link
      -- we do this after files/dirs cos windows can be funny about the order of the table
      if inode.ntype == 'sym' then
        -- get relative full path for os.execute
        local savedir = love.filesystem.getSaveDirectory()
        local symlink_path = savedir .. '/' .. inode.path .. '/' .. inode.name
        local target_path = savedir .. '/' .. inode.path .. '/' .. inode.data

        -- if manual symlinks then output the symlinks we should make later
        if self.manual_symlink == true then
          local output_path = output:gsub('%-', '%--')
          local manual_path = inode.path:gsub(output_path, '')
          local symlink_local = manual_path .. '/' .. inode.name
          print('love.squashfs > ', symlink_local, manual_path)
          table.insert(self.symlinks, {symlink_local:sub(2, #symlink_local), inode.data})

        -- otherwise create symlink based on symlink entry data 
        else
          -- this is a relative path from the path of the file
          -- windows needs mklink instead of ln, which requires admin permissions
          -- so will have to Run As Administrator to use
          local linker = 'ln -s -f "' .. target_path .. '" "' .. symlink_path .. '"'
          if love.system.getOS() == 'Windows' then
            -- we also have to work out if out symlink is for a directory OR a file
            -- as mklink needs a flag for directories
            local info = love.filesystem.getInfo(inode.path .. '/' .. inode.data)
            local flag = ''
            if info.type == 'directory' then
              flag = '/D'
            end
            linker = 'mklink ' .. flag .. ' "' .. symlink_path .. '" "' .. target_path .. '"'
          end
          os.execute(linker)
        end
        syms = syms + 1
      end
    end

    -- some final output logs
    print('love.squashfs > created ' .. tostring(files) .. ' files')
    print('love.squashfs > created ' .. tostring(dirs) .. ' directories')
    print('love.squashfs > created ' .. tostring(syms) .. ' symlinks')
    print('love.squashfs > decompressed to: ' .. output)

    -- return success
    return true, nil

  end,


  --[[
    @method - SquashFS:_readDirectory()
    @desc - reads a folder in the order squashfs expects, i.e. dir contents then
            the dir itself for inode numbering
    @param {string} target - target path to read
    @param {number} count - used recursively to handle counter
    @param {string} count - used recursively to handle paths
    @param {bool} count - used recursively to handle root
    @param {number} count - used recursively to handle parent
    @return {table} - returns a list of inode paths ready to squash 
    ]]
  _readDirectory = function(self, target, count, paths, root, parent)
    if count == nil then count = 0 end
    if paths == nil then paths = {} end
    if root == nil then root = true end
    if parent == nil then parent = 0 end
    local root_dir = love.filesystem.getDirectoryItems(target)
    for _, path in pairs(root_dir) do
      -- ignore any ds_store that might exist on mac
      if path ~= '.DS_Store' then
        count = count + 1
        local info = love.filesystem.getInfo(target .. '/' .. path)
        local inode = {
          name = path,
          path = target .. '/' .. path,
          type = info.type,
          number = count,
          modtime = info.modtime,
          parent = parent,
          root = root
        }
        if info.type == 'directory' then
          local npaths, ncount = self:_readDirectory(target .. '/' .. path, count, paths, false, count)
          paths = npaths
          count = ncount
        end
        table.insert(paths, inode)
      end
    end
    return paths, count
  end,


  --[[
    @method - SquashFS:_resolveNodePath()
    @desc - resolves an inode path all the way back to the root inode
    @param {table} mapping - inode mapping to get parent path
    @param {table} names - used recursively to handle counter
    @param {number} inode_number - inode number for parent
    @param {number} limit - root inode limit
    @param {string} output - output path to make sure its appended at start
    @param {string} path - node path as a list
    @return {string} - returns the node paths a full/path/string
    ]]
  _resolveNodePath = function(self, mapping, names, inode_number, limit, output, path)
    local parent = mapping[inode_number]
    local name = names[parent] or ''
    if path == nil then path = {} end
    if name ~= '' then table.insert(path, 1, name) end
    if parent > limit or parent == 0 then
      table.insert(path, 1, output)
      return table.concat(path, '/')
    else
      return self:_resolveNodePath(mapping, names, parent, limit, output, path)
    end
  end,


  --[[
    @prop - SquashFS:_inodeLength()
    @desc - used to set a baseline for each of the inode types,
            and to easily flag when an inode type isn't implemented yet in the console
    ]]
  _inodeLength = {
    16 + 16, -- Basic Directory
    16 + 16, -- Basic File (+N where N == #filename)
    16 + 8, -- Basic Symlink (+N where N == #symlink_target)
  },


  --[[
    @method - SquashFS:_decToOct()
    @desc - permission values are stored as dec in the squashfs inodes
            but for chmod we need the oct value
    @param {int} dec - dec value to turn into oct
    @return {int} - returns the oct value
    ]]
  _decToOct = function(self, dec)
    local valstr = "0123456789ABCDEF"
    local result = ""
    while dec > 0 do
      local n = dec % 8
      result = string.sub(valstr, n + 1, n + 1) .. result
      dec = math.floor(dec / 8)
    end
    return result
  end,


  --[[
    @method - SquashFS:_resolveSymlink()
    @desc - internal method to get the full path of a symlink using terminal
            currently LÖVE (which is using physfs) doesnt return the actual
            resolved symlink path 
    @param {string} path - full path of symlink to resolve
    @return {string} - returns resolved path
    ]]
  _resolveSymlink = function(self, path)
    local cmd = 'readlink "' .. path .. '"'
    local dir = path:sub(1, path:find("/[^/]*$") - 1)
    -- on windows we need to run dir on the containing directory
    -- as otherwise running dir directly on a symlink dir will just dir the symlink target
    if love.system.getOS() == 'Windows' then
      cmd = 'dir "' .. string.gsub(dir, '/', '\\') .. '"'
    end
    local handle = io.popen(cmd)
    if handle == nil then return '' end
    local result = handle:read("*a")
    handle:close()
    if love.system.getOS() == 'Windows' then
      -- remove backslash to keep paths consistent
      path = string.gsub(path, '\\', '/')
      dir = string.gsub(dir, '\\', '/')
      result = string.gsub(result, '\\', '/')
      local syminfo = path:sub(path:find("/[^/]*$"), #path)
      syminfo = ' ' .. syminfo:sub(2, #syminfo) .. ' %['
      syminfo = syminfo:gsub('%-', '%%-')
      local target = result:sub(result:find(syminfo) + #syminfo - 1, #result)
      target = target:sub(1, target:find('%]') - 1)
      return string.gsub(target, '\\', '/')
    end
    return result
  end,


  --[[
    @method - SquashFS:_stripAppImage()
    @desc - v2 appimages are just a appimage header with a squashfs binary 
            appended so we can actually strip the squashfs data right out 
            used by love-build to get the data from love.AppImage source
    @param {string} path - path to AppImage to strip
    @param {string} output - output file to put the binary squashfs data
    @return {nil}
    ]]
  _stripAppImage = function(self, path, output)
    local appimagedata, err = love.filesystem.read(path)
    if appimagedata == nil then
      print(err)
    end
    --appimage ELF itself has a hsqs key, so remove that first
    appimagedata = appimagedata:gsub('=hsqs', '=====')
    -- strip out squashfs format using hsqs header and write to new file
    local fstart, _ = appimagedata:find('hsqs')
    local squashdata = appimagedata:sub(fstart, #appimagedata)
    love.filesystem.write(output, squashdata)
  end,


  -- helpers for reading uint vals
  _readUInt64 = function(self, str, start)
    return self:_readUInt(str, start, 8)
  end,
  _readUInt32 = function(self, str, start)
    return self:_readUInt(str, start, 4)
  end,
  _readUInt16 = function(self, str, start)
    return self:_readUInt(str, start, 2)
  end,
  _readUInt = function(self, str, start, size)
    return love.data.unpack('<i' .. tostring(size), str:sub(start, start + (size-1)))
  end,


  --[[
    @method - SquashFS:_readMBlock()
    @desc - squashfs metadatablocks are max 8kb sized compressed blocks, 
            prepended by a 16 uint with the total compressed metadata size 
            following the 2 byte header
    @param {string} str - string to read mblock from
    @param {string} start - start position of mblock
    @return {string} - returns the mblock data
    ]]
  _readMBlock = function(self, str, start)
    local header = self:_readUInt16(str, start)
    local size = bit.band(header, 0x7FFF)
    local is_compressed = bit.band(header, 0x8000) == 0
    local compressed = str:sub(start+2, start+1+size)
    if pcall(love.data.decompress, 'string', 'zlib', compressed) then
      return love.data.decompress('string', 'zlib', compressed)
    else
      -- if compression failed and bit was unset then it should of been compressed
      -- so maybe the format read was incorrect, or position was invalid
      if is_compressed == true then
        print('love.squashfs > WARN: metadatablock was not compressed')
      end
      return compressed
    end
  end,
  _writeMBlock = function(self, str, dont_compress)
    local cdata = love.data.compress('string', 'zlib', str)
    if dont_compress then cdata = str end
    -- always compressed so dont set upper bit
    local size = love.data.pack('string', '<i2', #cdata)
    return size .. cdata
  end


}
