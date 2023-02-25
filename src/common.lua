---message: send message to std_error
---comment
---@param type 'INFO'|'WARNING'|'ERROR'
---@param text string error message
function message (type, text)
    local level = {INFO = 0, WARNING = 1, ERROR = 2}
    if level[type] == nil then type = 'ERROR' end
    if level[PANDOC_STATE.verbosity] <= level[type] then
        io.stderr:write('[' .. type .. '] Imagify: ' 
            .. text .. '\n')
    end
end

---tfind: finds a value in an array
---comment
---@param tbl table
---@return number|false result
function tfind(tbl, needle)
  local i = 0
  for _,v in ipairs(tbl) do
    i = i + 1
    if v == needle then
      return i
    end
  end
  return false
end 

---concatStrings: concatenate a list of strings into one.
---@param list [ string ] list of strings
---@param separator string separator (optional)
function concatStrings(list, separator)
  separator = separator and separator or ''
  local result = ''
  for _,str in ipairs(list) do
    result = result..separator..str
  end
  return result
end

---mergeMapInto: returns a new map resulting from merging a new one
-- into an old one. 
---@param new table|nil map with overriding values
---@param old table|nil map with original values
---@return table result new map with merged values
function mergeMapInto(new,old)
  local result = {} -- we need to clone
  if type(old) == 'table' then 
    for k,v in pairs(old) do result[k] = v end
  end
  if type(new) == 'table' then
    for k,v in pairs(new) do result[k] = v end
  end
  return result
end
