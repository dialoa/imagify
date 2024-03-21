-- ## File functions

local system = pandoc.system
local path = pandoc.path

---fileExists: checks whether a file exists
function fileExists(filepath)
  local f = io.open(filepath, 'r')
  if f ~= nil then
    io.close(f)
    return true
  else 
    return false
  end
end

---makeAbsolute: make filepath absolute
---@param filepath string file path
---@param root string|nil if relative, use this as root (default working dir) 
function makeAbsolute(filepath, root)
  root = root or system.get_working_directory()
  return path.is_absolute(filepath) and filepath
    or path.join{ root, filepath}
end

---folderExists: checks whether a folder exists
function folderExists(folderpath)

  -- the empty path always exists
  if folderpath == '' then return true end

  -- normalize folderpath
  folderpath = folderpath:gsub('[/\\]$','')..path.separator
  local ok, err, code = os.rename(folderpath, folderpath)
  -- err = 13 permission denied
  return ok or err == 13 or false
end

---ensureFolderExists: create a folder if needed
function ensureFolderExists(folderpath)
  local ok, err, code = true, nil, nil

  -- the empty path always exists
  if folderpath == '' then return true, nil, nil end

  -- normalize folderpath
  folderpath = folderpath:gsub('[/\\]$','')

  if not folderExists(folderpath) then
    ok, err, code = os.execute('mkdir '..folderpath)
  end

  return ok, err, code
end

---writeToFile: write string to file.
---@param contents string file contents
---@param filepath string file path
---@param mode string 'b' for binary, any other value text mode
---@return nil | string status error message
function writeToFile(contents, filepath, mode)
  local mode = mode == 'b' and 'wb' or 'w'
  local f = io.open(filepath, mode)
	if f then 
	  f:write(contents)
	  f:close()
  else
    return 'File not found'
  end
end

---readFile: read file as string (default) or binary.
---@param filepath string file path
---@param mode string 'b' for binary, any other value text mode
---@return string contents or empty string if failure
function readFile(filepath, mode)
  local mode = mode == 'b' and 'rb' or 'r'
	local contents
	local f = io.open(filepath, mode)
	if f then 
		contents = f:read('a')
		f:close()
	end
	return contents or ''
end

---copyFile: copy file from source to destination
---Lua's os.rename doesn't work across volumes. This is a 
---problem when Pandoc is run within a docker container:
---the temp files are in the container, the output typically
---in a shared volume mounted separately.
---We use copyFile to avoid this issue.
---@param source string file path
---@param destination string file path
function copyFile(source, destination, mode)
  local mode = mode == 'b' and 'b' or ''
  writeToFile(readFile(source, mode), destination, mode)
end

-- stripExtension: strip filepath of the filename's extension
---@param filepath string file path
---@param extensions string[] list of extensions, e.g. {'tex', 'latex'}
---  if not provided, any alphanumeric extension is stripped
---@return string filepath revised filepath
function stripExtension(filepath, extensions)
  local name, ext = path.split_extension(filepath)
  ext = ext:match('^%.(.*)')

  if extensions then
    extensions = pandoc.List(extensions)
    return extensions:find(ext) and name
      or filepath
  else
    return name
  end
end
