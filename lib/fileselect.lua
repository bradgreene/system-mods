--- fileselect utility (modified for file previewing)

local fs = {}

function fs.enter(folder, callback, file_num)
  fs.folders = {}
  fs.list = {}
  fs.display_list = {}
  fs.lengths = {}
  fs.pos = 0
  fs.depth = 0
  fs.folder = folder
  fs.callback = callback
  fs.done = false
  fs.path = nil
  fs.parentdir = nil
  fs.file_num = nil

  if file_num then fs.file_num = file_num - 1 end
  
  if fs.folder:sub(-1,-1) ~= "/" then
    fs.folder = fs.folder .. "/"
  end
  
  local count = 0
  if fs.file_num then
    for match in string.gmatch(fs.folder, "([^/]*)/") do
      count = count + 1
      if count > 5 then
        fs.depth = fs.depth + 1
        fs.folders[fs.depth] = match .. "/"
        if count == 6 then
          i, j = string.find(fs.folder, match .. "/")
          fs.folder = string.sub(fs.folder, 1, i - 1)
        end
      end
    end
  end
  
  -- metro for file preview (short delay between file previews otherwise tape stops working)
  fs.preview_delay = metro.init(function() if fs.done == true then fs.exit() else audio.tape_play_open(fs.getdir() .. fs.file); audio.tape_play_start() end end, 0.4, 1)
  fs.preview_active = false
  
  fs.getlist()
  
  if norns.menu.status() == false then
    fs.key_restore = key
    fs.enc_restore = enc
    fs.redraw_restore = redraw
    key = fs.key
    enc = fs.enc
    redraw = norns.none
    norns.menu.init()
  else
    fs.key_restore = norns.menu.get_key()
    fs.enc_restore = norns.menu.get_enc()
    fs.redraw_restore = norns.menu.get_redraw()
    norns.menu.set(fs.enc, fs.key, fs.redraw)
  end

  fs.redraw()
end

function fs.exit()
  if norns.menu.status() == false then
    key = fs.key_restore
    enc = fs.enc_restore
    redraw = fs.redraw_restore
    norns.menu.init()
  else
    norns.menu.set(fs.enc_restore, fs.key_restore, fs.redraw_restore)
  end
  if fs.path then fs.callback(fs.path) else fs.callback("cancel") end
  metro.free(fs.preview_delay.id)
end

function fs.pushd(dir)
  local subdir = dir:match(fs.folder .. '(.*)')
  for match in subdir:gmatch("([^/]*)/") do
    fs.depth = fs.depth + 1
    fs.folders[fs.depth] = match .. "/"
  end
  fs.getlist()
  fs.redraw()
end

fs.getdir = function()
  local path = fs.folder
  for k,v in pairs(fs.folders) do
    path = path .. v
  end
  --print("path: "..path)
  return path
end

fs.getlist = function(n, depth)
  local dir = fs.getdir()
  fs.list = util.scandir(dir)
  fs.display_list = {}
  fs.lengths = {}
  
  if fs.file_num then
    fs.pos = fs.file_num
    fs.file_num = nil
  elseif n == 3 then
    fs.pos = 0
  end
  
  fs.len = #fs.list

  -- Generate display list and lengths
  for k, v in ipairs(fs.list) do
    local line = v
    local max_line_length = 128

    if string.sub(line, -1) ~= "/" then
      local _, samples, rate = audio.file_info(dir .. line)
      if samples > 0 and rate > 0 then
        fs.lengths[k] = util.s_to_hms(math.floor(samples / rate))
        max_line_length = 97
      end
    end
    
    if line == fs.parentdir then
      fs.pos = k - 1
    end

    line = util.trim_string_to_width(line, max_line_length)
    fs.display_list[k] = line
  end
end

fs.preview = function()
  fs.file = fs.list[fs.pos+1]
  if fs.lengths[fs.pos+1] then
    if fs.previewing ~= fs.pos then
      if fs.previewing then
        fs.preview_delay:stop()
      end
      audio.tape_play_stop()
      fs.previewing = fs.pos
      fs.redraw()
      -- short delay between file previews otherwise tape stops working
      fs.preview_delay:start()
    end
  end
end

fs.key = function(n,z)
  -- back
  if n==2 and z==1 then
    if fs.depth > 0 then
      fs.parentdir = fs.folders[fs.depth]
      fs.folders[fs.depth] = nil
      fs.depth = fs.depth - 1
      fs.getlist(n, fs.depth)
      fs.redraw()
    else
      fs.path = nil
      fs.exit()
    end
    if fs.previewing then
      -- stop previewing
      fs.preview_delay:stop()
      audio.tape_play_stop()
      fs.previewing = nil
      fs.redraw()
    end
  -- select
  elseif n==3 and z==1 then
    if fs.previewing then
      -- stop previewing
      fs.preview_delay:stop()
      audio.tape_play_stop()
      fs.previewing = nil
    end
    if #fs.list > 0 then
      fs.file = fs.list[fs.pos+1]
      if fs.file == "../" then
        fs.folders[fs.depth] = nil
        fs.depth = fs.depth - 1
        fs.getlist(n)
        fs.redraw()
      elseif string.find(fs.file,'/') then
        --print("folder")
        fs.depth = fs.depth + 1
        fs.folders[fs.depth] = fs.file
        fs.getlist(n)
        fs.redraw()
        if fs.preview_active == true then fs.preview() end
      else
        local path = fs.folder
        for k,v in pairs(fs.folders) do
          path = path .. v
        end
        fs.path = path .. fs.file
        fs.done = true
      end
    end
    if not fs.done then
        fs.redraw()
    end
  elseif z == 0 and fs.done == true then
    if fs.preview_active == true then fs.preview_delay:start() else fs.exit() end
  end
end

fs.enc = function(n,d)
  if n==2 then
    fs.pos = util.clamp(fs.pos + d, 0, fs.len - 1)
    fs.redraw()
    -- preview on file change
    if fs.previewing then fs.preview() end
  elseif n==3 and d > 0 then
    -- preview
    fs.preview_active = true
    fs.preview()
  elseif n == 3 and d < 0 then
    -- always stop previewing with left scroll
    if fs.previewing then
      fs.preview_delay:stop()
      audio.tape_play_stop()
      fs.previewing = nil
      fs.preview_active = false
      fs.redraw()
    end
  end
end

fs.redraw = function()
  screen.clear()
  screen.font_face(1)
  screen.font_size(8)
  if #fs.list == 0 then
    screen.level(4)
    screen.move(0,20)
    screen.text("(no files)")
  else
    for i=1,6 do
      if (i > 2 - fs.pos) and (i < fs.len - fs.pos + 3) then
        local list_index = i+fs.pos-2
        screen.move(0,10*i)
        if(i==3) then
          screen.level(15)
        else
          screen.level(4)
        end
        local text = fs.display_list[list_index]
        if fs.lengths[fs.pos+1] then
          if list_index-1 == fs.previewing then
            text = util.trim_string_to_width('* ' .. text, 97)
          end
        end
        screen.text(text)
        if fs.lengths[list_index] then
          screen.move(128,10*i)
          screen.text_right(fs.lengths[list_index])
        end
      end
    end
  end
  screen.update()
end

return fs