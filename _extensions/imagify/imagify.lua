
---------------------------------------------------------
----------------Auto generated code block----------------
---------------------------------------------------------

do
    local searchers = package.searchers or package.loaders
    local origin_seacher = searchers[2]
    searchers[2] = function(path)
        local files =
        {
------------------------
-- Modules part begin --
------------------------

["common"] = function()
--------------------
-- Module: 'common'
--------------------
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
---@param list string[]  list of strings
---@param separator string separator (optional)
---@return string result
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

end,

["file"] = function()
--------------------
-- Module: 'file'
--------------------
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

end,

----------------------
-- Modules part end --
----------------------
        }
        if files[path] then
            return files[path]
        else
            return origin_seacher(path)
        end
    end
end
---------------------------------------------------------
----------------Auto generated code block----------------
---------------------------------------------------------
--[[-- # Imagify - Pandoc / Quarto filter to convert selected 
  LaTeX elements into images.

@author Julien Dutant <julien.dutant@philosophie.ch>
@copyright 2021-2023 Philosophie.ch
@license MIT - see LICENSE file for details.
@release 0.3.0

Converts some or all LaTeX code in a document into 
images.

@todo reader user templates from metadata

@note Rendering options are provided in the doc's metadata (global),
      as Div / Span attribute (regional), on a RawBlock/Inline (local).
      They need to be kept track of, then merged before imagifying.
      The more local ones override the global ones. 
@note LaTeX Raw elements may be tagged as `tex` or `latex`. LaTeX code
      directly inserted in markdown (without $...$ or ```....``` wrappers)
      is parsed by Pandoc as Raw element with tag `tex` or `latex`.
]]

PANDOC_VERSION:must_be_at_least(
  '2.19.0',
  'The Imagify filter requires Pandoc version >= 2.19'
)

-- # Modules

require 'common'
require 'file'

-- # Global variables

local stringify = pandoc.utils.stringify
local pandoctype = pandoc.utils.type
local system = pandoc.system
local path = pandoc.path

--- renderOptions type
--- Contains the fields below plus a number of Pandoc metadata
---keys like header-includes, fontenc, colorlinks etc. 
---See getRenderOptions() for details.
---@alias ro_force boolean imagify even when targeting LaTeX
---@alias ro_embed boolean whether to embed (if possible) or output as file
---@alias ro_debug boolean debug mode (keep .tex source, crash on fail)
---@alias ro_template string identifier of a Pandoc template (default 'default')
---@alias ro_pdf_engine 'latex'|'pdflatex'|'xelatex'|'lualatex' latex engine to be used
---@alias ro_svg_converter 'dvisvgm' pdf/dvi to svg converter (default 'dvisvgm')
---@alias ro_zoom string to apply when converting pdf/dvi to svg
---@alias ro_vertical_align string vertical align value (HTML output)
---@alias ro_block_style string style to apply to blockish elements (DisplayMath, RawBlock)
---@alias renderOptsType {force: ro_force, embed: ro_embed, debug: ro_debug, template: ro_template, pdf_engine: ro_pdf_engine, svg_converter: ro_svg_converter, zoom: ro_zoom, vertical_align: ro_vertical_align, block_style: ro_block_style, }
---@type renderOptsType
local globalRenderOptions = {
  force = false,
  embed = true,
  debug = false,
  template = 'default',
  pdf_engine = 'latex',
  svg_converter = 'dvisvgm',
  zoom = '1.5',
  vertical_align = 'baseline',
  block_style = 'display:block; margin: .5em auto;'
}

---@alias fo_scope 'manual'|'all'|'images'|'none', # imagify scope
---@alias fo_lazy boolean, # do not regenerate existing image files
---@alias fo_no_html_embed boolean, # prohibit html embedding
---@alias fo_output_folder string, # path for outputs
---@alias fo_output_folder_exists boolean, # Internal var to avoid repeat checks
---@alias fo_libgs_path string|nil, # path to Ghostscript lib
---@alias fo_optionsForClass { string: renderOptsType}, # renderOptions for imagify classes
---@alias fo_extensionForOutput { default: string, string: string }, # map of image formats (svg|pdf) for some output formats 
---@alias filterOptsType { scope : fo_scope, lazy: fo_lazy, no_html_embed : fo_no_html_embed, output_folder: fo_output_folder, output_folder_exists: fo_output_folder_exists, libgs_path: fo_libgs_path, optionsForClass: fo_optionsForClass, extensionForOutput: fo_extensionForOutput }
---@type filterOptsType
local filterOptions = {
  scope = 'manual', 
  lazy = true,
  no_html_embed = false,
  libgs_path = nil,
  output_folder = '_imagify',
  output_folder_exists = false,
  optionsForClass = {},
  extensionForOutput = {
    default = 'svg',
    html = 'svg',
    html4 = 'svg',
    html5 = 'svg',
    latex = 'pdf',
    beamer = 'pdf',
    docx = 'pdf',  
  }
}

---@alias tplId string template identifier, 'default' reserved for Pandoc's default template
---@alias to_source string template source code
---@alias to_template pandoc.Template compiled template
---@alias templateOptsType { default: table, string: { source: to_source, compiled: to_template}}
---@type templateOptsType
local Templates = {
  default = {},
}

-- ## Pandoc AST functions

--outputIsLaTeX: checks whether the target output is in LaTeX
---@return boolean
local function outputIsLaTeX()
  return FORMAT:match('latex') or FORMAT:match('beamer') or false
end

--- ensureList: ensures an object is a pandoc.List.
---@param obj any|nil
local function ensureList(obj)

  return pandoctype(obj) == 'List' and obj
    or pandoc.List:new{obj} 

end

---imagifyType: whether an element is imagifiable LaTeX and which type
---@alias imagifyType nil|'InlineMath'|'DisplayMath'|'RawBlock'|'RawInline'|'TexImage'|'TikzImage'
---@param elem pandoc.Math|pandoc.RawBlock|pandoc.RawInline|pandoc.Image element
---@return imagifyType elemType to imagify or nil
function imagifyType(elem)
  return elem.t == 'Image' and (
      elem.src:match('%.tex$') and 'TexImage'
      or elem.src:match('%.tikz') and 'TikzImage'
    )
    or elem.mathtype == 'InlineMath' and 'InlineMath'
    or elem.mathtype == 'DisplayMath' and 'DisplayMath'
    or (elem.format == 'tex' or elem.format == 'latex')
      and (
        elem.t == 'RawBlock' and 'RawBlock'
        or elem.t == 'RawInline' and 'RawInline'
      )
    or nil
end

-- ## Smart imagifying functions

---usesTikZ: tell whether a source contains a TikZ picture
---@param source string LaTeX source
---@return boolean result
local function usesTikZ(source)
  return (source:match('\\begin{tikzpicture}') 
    or source:match('\\tikz')) and true
    or false
end

-- ## Converter functions

local function dvisvgmVerbosity()
	return PANDOC_STATE.verbosity == 'ERROR' and '1'
				or PANDOC_STATE.verbosity == 'WARNING' and '2'
				or PANDOC_STATE.verbosity == 'INFO' and '4'
        or '2'
end

---getCodeFromFile: get source code from a file
---uses Pandoc's resource paths if needed
---@param src string source file name/path
---@return string|nil result file contents or nil if not found
function getCodeFromFile(src)
  local result

  if fileExists(src) then
    result = readFile(src)
  else
    for _,item in ipairs(PANDOC_STATE.resource_path) do
      if fileExists(path.join{item, src}) then
        result = readFile(path.join{item, src}) 
        break
      end
    end
  end

  return result

end

---runLaTeX: runs latex engine on file
---@param source string filepath of the source file
---@param options table options
--    format = output format, 'dvi' or 'pdf',
--    pdf_engine = pdf engine, 'latex', 'xelatex', 'xetex', '' etc.
--    texinputs = value for export TEXINPUTS 
---@return boolean success, string result result is filepath or LaTeX log if failed
local function runLaTeX(source, options)
	options = options or {}
  local format = options.format or 'pdf'
  local pdf_engine = options.pdf_engine or 'latex'
  local outfile = stripExtension(source, {'tex','latex'})
  local ext = pdf_engine == 'xelatex' and format == 'dvi' and '.xdv'
                or '.'..format
  local texinputs = options.texinputs or nil
  -- Latexmk: extra options come *after* -<engine> and *before* <source>
  local latex_args = pandoc.List:new{ '--interaction=nonstopmode' }
  local latexmk_args = pandoc.List:new{ '-'..pdf_engine }
  -- Export the TEXINPUTS variable
  local env = texinputs and 'export TEXINPUTS='..texinputs..'; '
    or ''
  -- latex command run, for debug purposes
  local cmd
  
  -- @TODO implement verbosity in latex
  -- latexmk silent mode
  if PANDOC_STATE.verbosity == 'ERROR' then
    latexmk_args:insert('-silent')
  end

  -- xelatex doesn't accept `output-format`,
  -- generates both .pdf and .xdv
  if pdf_engine ~= 'xelatex' then
    latex_args:insert('--output-format='..format)
  end


  -- try Latexmk first, latex engine second
  -- two runs of latex engine
  cmd = env..'latexmk '..concatStrings(latexmk_args..latex_args, ' ')
    ..' '..source
  local success, err, code = os.execute(cmd)

  if not success and code == 127 then
    cmd = pdf_engine..' '
    ..concatStrings(latex_args, ' ')
    ..' '..source..' 2>&1 > /dev/null '..'; '
    cmd = cmd..cmd -- two runs needed
    success = os.execute(env..cmd)
  end

  if success then

    return true, outfile..ext

  else

    local result = 'LaTeX compilation failed.\n'
      ..'Command used: '..cmd..'\n'
    local src_code = readFile(source)
    if src_code then 
      result = result..'LaTeX source code:\n'
      result = result..src_code
    end
    local log = readFile(outfile..'.log')
    if log then 
      result = result..'LaTeX log:\n'..log
    end
    return false, result

  end

end

---toSVG: convert latex output to SVG.
---Ghostcript library required to convert PDF files.
--        See divsvgm manual for more details.
-- Options:
--    *output*: string output filepath (directory must exist),
--    *zoom*: string zoom factor, e.g. 1.5.
---@param source string filepath of dvi, xdv or svg file
---@param options { output : string, zoom: string} options
---@return success boolean, result string filepath
local function toSVG(source, options)
  if source == nil then return nil end
	local options = options or {}
	local outfile = options.output 
    or stripExtension(source, {'pdf', 'svg', 'xdv'})..'.svg'
	local source_format = source:match('%.pdf$') and 'pdf'
										or source:match('%.dvi$') and 'dvi'
										or source:match('%.xdv$') and 'dvi'
	local cmd_opts = pandoc.List:new({'--optimize', 
		'--verbosity='..dvisvgmVerbosity(),
--  '--relative',
--  '--no-fonts', 
    '--font-format=WOFF', 
		source
	})

  -- @TODO doesn't work on my machine, why?
  if filterOptions.libgs_path and filterOptions.libgs_path ~= '' then
    cmd_opts:insert('--libgs='..filterOptions.libgs_path)
  end

  -- note "Ghostcript required to process PDF files"
  if source_format == 'pdf' then
    cmd_opts:insert('--pdf')
  end

  if options.zoom then
    cmd_opts:insert('--zoom='..options.zoom)
  end

	cmd_opts:insert('--output='..outfile)

  success = os.execute('dvisvgm'
    ..' '..concatStrings(cmd_opts, ' ')
  )

  if success then

    return success, outfile

  else

    return success, 'DVI/PDF to SVG conversion failed\n'

  end

end

--- getSVGFromFile: extract svg tag (with contents) from a SVG file.
-- Assumes the file only contains one SVG tag.
-- @param filepath string file path
local function getSVGFromFile(filepath)
	local contents = readFile(filepath)

	return contents and contents:match('<svg.*</svg>')
	
end


--- urlEncode: URL-encodes a string
-- See <https://github.com/stuartpb/tvtropes-lua/blob/master/urlencode.lua>
-- Modified to handle UTF-8: %w matches UTF-8 starting bytes, which should
-- be encoded. We specify safe alphanumeric chars explicitly instead.
-- @param str string
local function urlEncode(str)

  --Ensure all newlines are in CRLF form
  str = string.gsub (str, "\r?\n", "\r\n")

  --Percent-encode all chars other than unreserved 
  --as per RFC 3986, Section 2.3
  --<https://www.rfc-editor.org/rfc/rfc3986#section-2.3>
  str = str:gsub("[^0-9a-zA-Z%-._~]",
    function (c) return string.format ("%%%02X", string.byte(c)) end)
  
  return str

end

-- # Main filter functions

-- ## Functions to read options

---getFilterOptions: read render options
---returns a map:
---   scope: fo_scope
---   libgs_path: string
---   output_folder: string
---@param opts table options map from meta.imagify
---@return table result map of options
local function getFilterOptions(opts)
  local stringKeys = {'scope', 'libgs-path', 'output-folder'}
  local boolKeys = {'lazy'}
  local result = {}

  for _,key in ipairs(boolKeys) do
    if opts[key] ~= nil and pandoctype(opts[key]) == 'boolean' then
      result[key] = opts[key]
    end
  end

  for _,key in ipairs(stringKeys) do
    opts[key] = opts[key] and stringify(opts[key]) or nil
  end

  result.scope = opts.scope and (
    opts.scope == 'all' and 'all'
    or (opts.scope == 'selected' or opts.scope == 'manual') and 'manual'
    or opts.scope == 'images' and 'images'
    or opts.scope == 'none' and 'none'
  ) or nil

  result.libgs_path = opts['libgs-path'] and opts['libgs-path'] or nil

  result.output_folder = opts['output-folder'] 
    and opts['output-folder'] or nil

  return result

end

---getRenderOptions: read render options
---@param opts table options map, from doc metadata or elem attributes
---@return table result renderOptions map of options
local function getRenderOptions(opts)
  local result = {}
  local renderBooleanlKeys = {
    'force',
    'embed',
    'debug',
  }
  local renderStringKeys = {
    'pdf-engine',
    'svg-converter',
    'zoom', 
    'vertical-align',
    'block-style',
  }
  local renderListKeys = {
    'classoption',
  }
  -- Pandoc metadata variables used by the LaTeX template
  local renderMetaKeys = {
    'header-includes',
    'mathspec',
    'fontenc',
    'fontfamily',
    'fontfamilyoptions',
    'fontsize',
    'mainfont', 'sansfont', 'monofont', 'mathfont', 'CJKmainfont',
    'mainfontoptions', 'sansfontoptions', 'monofontoptions', 
    'mathfontoptions', 'CJKoptions',
    'microtypeoptions',
    'colorlinks',
    'boxlinks',
    'linkcolor', 'filecolor', 'citecolor', 'urlcolor', 'toccolor',
    -- 'links-as-note': not visible in standalone LaTeX class
    'urlstyle',
  }
  checks = {
    pdf_engine = {'latex', 'xelatex', 'lualatex'},
    svg_converter = {'dvisvgm'},
  }

  -- boolean values
  -- @TODO these may be passed as strings in Div attributes
  -- convert "xx-yy" to "xx_yy" keys
  for _,key in ipairs(renderBooleanlKeys) do
    if opts[key] ~= nil then
      if pandoctype(opts[key]) == 'boolean' then
        result[key:gsub('-','_')] = opts[key]
      elseif pandoctype(opts[key]) == 'string' then 
        if opts[key] == 'false' or opts[key] == 'no' then
          result[key:gsub('-','_')] = false
        else
          result[key:gsub('-','_')] = true
        end
      end
    end
  end
  
  -- string values
  -- convert "xx-yy" to "xx_yy" keys
  for _,key in ipairs(renderStringKeys) do
    if opts[key] then
      result[key:gsub('-','_')] = stringify(opts[key])
    end
  end

  -- list values
  for _,key in ipairs(renderListKeys) do
    if opts[key] then
      result[key:gsub('-','_')] = ensureList(opts[key])
    end
  end

  -- meta values
  -- do not change the key names
  for _,key in ipairs(renderMetaKeys) do
    if opts[key] then
      result[key] = opts[key]
    end
  end

  -- apply checks
  for key, accepted_vals in pairs(checks) do
    if result[key] and not tfind(accepted_vals, result[key]) then
      message('WARNING', 'Option '..key..'has an invalid value: '
        ..result[key]..". I'm ignoring it."
    )
      result[key] = nil
    end
  end

  -- Special cases
  -- `embed` not possible with `extract-media` on
  if result.embed and filterOptions.no_html_embed then
    result.embed = nil
  end

  return result

end

---readImagifyClasses: read user's specification of custom classes
-- This can be a string (single class), a pandoc.List of strings
-- or a map { class = renderOptionsForClass }.
-- We update `filterOptions.classes` accordingly.
---@param opts pandoc.List|pandoc.MetaMap|string
local function readImagifyClasses(opts)
  -- ensure it's a list or table
  if pandoctype(opts) ~= 'List' and pandoctype(opts) ~= 'table' then
    opts = pandoc.List:new({ opts })
  end

  if pandoctype(opts) == 'List' then
    for _, val in ipairs(opts) do
      local class = stringify(val)
      filterOptions.optionsForClass[class] = {}
    end
  elseif pandoctype(opts) == 'table' then
    for key, val in pairs(opts) do
      local class = stringify(key)
      filterOptions.optionsForClass[class] = getRenderOptions(val)
    end
  end

end

---init: read metadata options.
-- Classes in `imagify-classes:` override those in `imagify: classes:`
-- If `meta.imagify` isn't a map assume it's a `scope` value 
-- Special cases:
--    filterOptions.no_html_embed: Pandoc can't handle URL-embedded images when extract-media is on
---@param meta pandoc.Meta doc's metadata
local function init(meta)
  local userOptions = meta.imagify 
    and (pandoctype(meta.imagify) == 'table' and meta.imagify
      or {scope = stringify(meta.imagify)}
    ) 
    or {}
  local userClasses = meta['imagify-classes'] 
    and pandoctype(meta['imagify-classes'] ) == 'table' 
    and meta['imagify-classes']
    or nil
  local rootKeysUsed = {
    'header-includes',
    'mathspec',
    'fontenc',
    'fontfamily',
    'fontfamilyoptions',
    'fontsize',
    'mainfont', 'sansfont', 'monofont', 'mathfont', 'CJKmainfont',
    'mainfontoptions', 'sansfontoptions', 'monofontoptions', 
    'mathfontoptions', 'CJKoptions',
    'microtypeoptions',
    'colorlinks',
    'boxlinks',
    'linkcolor', 'filecolor', 'citecolor', 'urlcolor', 'toccolor',
    -- 'links-as-note': no footnotes in standalone LaTeX class
    'urlstyle',
  }
  
  -- pass relevant root options unless overriden in meta.imagify
  for _,key in ipairs(rootKeysUsed) do
    if meta[key] and not userOptions[key] then 
      userOptions[key] = meta[key]
    end
  end

  filterOptions = mergeMapInto(
    getFilterOptions(userOptions),
    filterOptions
  )

  if meta['extract-media'] and FORMAT:match('html') then
    filterOptions.no_html_embed = true
  end

  globalRenderOptions = mergeMapInto(
    getRenderOptions(userOptions),
    globalRenderOptions
  )

  if userOptions.classes then
    filterOptions.classes = readImagifyClasses(userOptions.classes)
  end

  if userClasses then 
    filterOptions.classes = readImagifyClasses(userClasses)
  end

end

-- ## Functions to convert images

---getTemplate: get a compiled template
---@param id string template identifier (key of Templates)
---@return pandoc.Template|nil tpl result
local function getTemplate(id)
  if not Templates[id] then
    return nil
  end

  -- ensure there's a non-empty source, otherwise return nil
  -- special case: default template, fill in source from Pandoc
  if id == 'default' and not Templates[id].source then
    Templates[id].source = pandoc.template.default('latex')
  end

  if not Templates[id].source or Templates[id].source == '' then
    return nil
  end

  -- compile if needed and return

  if not Templates[id].compiled then
    Templates[id].compiled = pandoc.template.compile(
      Templates[id].source)
  end

  return Templates[id].compiled

end

---buildTeXDoc: turns LaTeX element into a LaTeX doc source.
---@param code string LaTeX code
---@param renderOptions table render options
---@param elemType string 'InlineMath', 'DisplayMath', 'RawInline', 'RawBlock'
local function buildTeXDoc(code, renderOptions, elemType)
  local endFormat = filterOptions.extensionForOutput[FORMAT]
    or filterOptions.extensionForOutput.default
  elemType = elemType and elemType or 'InlineMath'
  code = code or ''
  renderOptions = renderOptions or {}
  local template = renderOptions.template or 'default'
  local svg_converter = renderOptions.svg_converter or 'dvisvgm'
  local doc = nil
  
  -- wrap DisplayMath and InlineMath in math mode
  -- for display math we must use \displaystyle 
  --  see <https://tex.stackexchange.com/questions/50162/how-to-make-a-standalone-document-with-one-equation>
  if elemType == 'DisplayMath' then
    code = '$\\displaystyle\n'..code..'$'
  elseif elemType == 'InlineMath' then
    code = '$'..code..'$'
  end

  doc = pandoc.Pandoc(
    pandoc.RawBlock('latex', code),
    pandoc.Meta(renderOptions)
  )

  -- modify the doc's meta values as required
  --@TODO set class option class=...
  --Standalone tikz needs \standaloneenv{tikzpicture}
  local headinc = ensureList(doc.meta['header-includes'])
  local classopt = ensureList(doc.meta['classoption'])

  -- Standalone class `dvisvgm` option: make output file
  -- dvisvgm-friendly (esp TikZ images).
  -- Not compatible with pdflatex
  if endFormat == 'svg' and svg_converter == 'dvisvgm' then
    classopt:insert(pandoc.Str('dvisvgm'))
  end
  
  -- The standalone class option `tikz` needs to be activated
  -- to avoid an empty page of output.
  if usesTikZ(code) then
    headinc:insert(pandoc.RawBlock('latex', '\\usepackage{tikz}'))
    classopt:insert{
      pandoc.Str('tikz')
    }
  end

  doc.meta['header-includes'] = #headinc > 0 and headinc or nil
  doc.meta.classoption = #classopt > 0 and classopt or nil
  doc.meta.documentclass = 'standalone'
  
  return pandoc.write(doc, 'latex', {
    template = getTemplate(template),
  })

end

---createUniqueName: return unique identifier for an image source.
---Combines LaTeX sources and rendering options.
---@param source string LaTeX source for the image
---@param renderOptions table render options
---@return string filename without extension
local function createUniqueName(source, renderOptions)
  return pandoc.sha1(source .. 
    '|Zoom:'..renderOptions.zoom)
end

---latexToImage: convert LaTeX to image.
--  The image can be exported as SVG string or as a SVG or PDF file.
---@param source string LaTeX source document
---@param renderOptions table rendering options
---@return success boolean, string result result is file contents or filepath or error message.
local function latexToImage(source, renderOptions)
  local renderOptions = renderOptions or {}
  local ext = filterOptions.extensionForOutput[FORMAT]
    or filterOptions.extensionForOutput.default
  local lazy = filterOptions.lazy
  local embed = renderOptions.embed
    and ext == 'svg' and FORMAT:match('html') and true 
    or false
  local pdf_engine = renderOptions.pdf_engine or 'latex'
  local latex_out_format = ext == 'svg' and 'dvi' or 'pdf'
  local debug = renderOptions.debug or false
  local folder = filterOptions.output_folder or ''
  local jobOutFolder = makeAbsolute(PANDOC_STATE.output_file 
    and path.directory(PANDOC_STATE.output_file) ~= '.'
    and path.directory(PANDOC_STATE.output_file) or '')
  local texinputs = renderOptions.texinputs or nil
  -- to be created
  local folderAbs, file, fileAbs, texfileAbs = '', '', '', ''
  local fileRelativeToJob = ''
  local success, result

  -- default texinputs: all sources folders and output folder
  -- and directory folder?
  if not texinputs then 
    texinputs = system.get_working_directory()..'//:'
    for _,filepath in ipairs(PANDOC_STATE.input_files) do
      texinputs = texinputs
        .. makeAbsolute(filepath and path.directory(filepath) or '')
        .. '//:'
    end
    texinputs = texinputs.. jobOutFolder .. '//:'
  end

  -- if we output files prepare folder and file names
  -- we need absolute paths to move things out of the temp dir
  if not embed or debug then
    folderAbs = makeAbsolute(folder)
    filename = createUniqueName(source, renderOptions)
    fileAbs = path.join{folderAbs, filename..'.'..ext}
    file = path.join{folder, filename..'.'..ext}
    texfileAbs = path.join{folderAbs, filename..'.tex'}

    -- ensure the output folder exists (only once)
    if not filterOptions.output_folder_exists then
      ensureFolderExists(folderAbs)
      filterOptions.output_folder_exists = true
    end

    -- path to the image relative to document output
    fileRelativeToJob = path.make_relative(fileAbs, jobOutFolder)

    -- if lazy, don't regenerate files that already exist
    if not embed and lazy and fileExists(fileAbs) then 
      success, result = true, fileRelativeToJob
      return success, result
    end

  end

	system.with_temporary_directory('imagify', function (tmpdir)
			system.with_working_directory(tmpdir, function()

      	writeToFile(source, 'source.tex')

        -- debug: copy before, LaTeX may crash
        if debug then
          writeToFile(source, texfileAbs)
        end

        -- result = 'source.dvi'|'source.xdv'|'source.pdf'|nil
				success, result = runLaTeX('source.tex', {
					format = latex_out_format,
					pdf_engine = pdf_engine,
          texinputs = texinputs
				})

        -- further conversions of dvi/pdf?

        if success and ext == 'svg' then

					success, result = toSVG(result, {
            zoom = renderOptions.zoom,
          })

        end

        -- embed or save

        if success then

          if embed and ext == 'svg' then

            -- read svg contents and cleanup
            result = "<?xml version='1.0' encoding='UTF-8'?>\n"
              .. getSVGFromFile(result)

            -- URL encode
            result = 'data:image/svg+xml,'..urlEncode(result)

          else

            --- File copy 
            --- not os.rename, which doesn't work across volumes
            --- binary in case the output is PDF
            copyFile(result, fileAbs, 'b')
            result = fileRelativeToJob

          end
          
        end

    end)
  end)

  return success, result

end

---createImageElemFrom(src, renderOptions, elemType)
---@param text string source code for the image
---@param src string URL (possibly URL encoded data)
---@param renderOptions table render Options
---@param elemType string 'InlineMath', 'DisplayMath', 'RawInline', 'RawBlock'
---@return pandoc.Image img
local function createImageElemFrom(text, src, renderOptions, elemType)
  local title = text or ''
  local caption = '' -- for future implementation (Raw elems attribute?)
  local block = elemType == 'DisplayMath' or elemType == 'RawBlock'
  local style = ''
  local block_style = renderOptions.block_style
    or 'display: block; margin: .5em auto; '
  local vertical_align = renderOptions.vertical_align
    or 'baseline'

  if block then
    style = style .. block_style
  else
    style = style .. 'vertical-align: '..vertical_align..'; '
  end

  return pandoc.Image(caption, src, title, { style = style })

end  

---toImage: convert to pandoc.Image using specified rendering options.
---Return the original element if conversion failed.
---@param elem pandoc.Math|pandoc.RawInline|pandoc.RawBlock|pandoc.Image
---@param elemType imagifyType type of element to imagify
---@param renderOptions table rendering options
---@return pandoc.Image|pandoc.Inlines|pandoc.Para|nil
local function toImage(elem, elemType, renderOptions)
  local code, doc
  local success, result, img

  -- get code, return nil if none
  if elemType == 'TexImage' or elemType == 'TikzImage' then
    code = getCodeFromFile(elem.src)
    if not code then
      message('ERROR', 'Image source file '..elem.src..' not found.')
    end
  else
    code = elem.text
  end
  if not code then return nil end

  -- prepare LaTeX source document
  doc = buildTeXDoc(code, renderOptions, elemType)

  -- convert to file or string
  success, result = latexToImage(doc, renderOptions)

  -- prepare Image element
  if success then
    if (elemType == 'TexImage' or elemType == 'TikzImage') then
      elem.src = result
      img = elem
    elseif elemType == 'RawBlock' then
      img = pandoc.Para(
        createImageElemFrom(code, result, renderOptions, elemType)
      )
    else
      img = createImageElemFrom(code, result, renderOptions, elemType)
    end
  else
    message('ERROR', result)
    img = pandoc.List:new {
      pandoc.Emph{ pandoc.Str('<LaTeX content not imagified>') },
      pandoc.Space(), pandoc.Str(code), pandoc.Space(),
      pandoc.Emph{ pandoc.Str('<end of LaTeX content>') },
    }
  end
 
  return img

end

-- ## Functions to traverse the document tree

---imagifyClass: find an element's imagify class, if any.
---If both `imagify` and a custom class is present, return the latter.
---@param elem pandoc.Div|pandoc.Span
---@return string 
local function imagifyClass(elem)
  -- priority to custom classes other than 'imagify'
  for _,class in ipairs(elem.classes) do
    if filterOptions.optionsForClass[class] then
      return class
    end
  end
  if elem.classes:find('imagify') then
    return 'imagify'
  end
  return nil
end

---scanContainer: read imagify options of a Span/Div, imagify if needed.
---@param elem pandoc.Div|pandoc.Span
---@param renderOptions table render options handed down from higher-level elems
---@return pandoc.Span|pandoc.Div|nil span modified element or nil if no change
local function scanContainer(elem, renderOptions)
  local class = imagifyClass(elem)

  if class then
    -- create new rendering options by applying the class options
    local opts = mergeMapInto(filterOptions.optionsForClass[class], 
      renderOptions)
    -- apply any locally specified rendering options
    opts = mergeMapInto(getRenderOptions(elem.attributes), opts)
    -- build recursive scanner from updated options
    local scan = function (elem) return scanContainer(elem, opts) end
    --- build imagifier from updated options
    local imagify = function(el) 
      local elemType = imagifyType(el)
      if opts.force == true or outputIsLaTeX() == false
        or (elemType == 'TexImage' or elemType == 'TikzImage') then
        return elemType and toImage(el, elemType, opts) or nil
      end
    end
    --- apply recursion first, then imagifier
    return elem:walk({
      Div = scan,
      Span = scan,
    }):walk({
      Math = imagify,
      RawInline = imagify,
      RawBlock = imagify,
      Image = imagify,
    })

  else

    -- recursion
    local scan = function (elem) return scanContainer(elem, renderOptions) end
    return elem:walk({
      Span = scan,
      Div = scan,
    })

  end

end

---main: process the main document's body.
-- Handles filterOptions `scope` and `force`
local function main(doc)
  local scope = filterOptions.scope
  local force = globalRenderOptions.force

  if scope == 'none' then
    return nil
  end

  -- whole doc wrapped in a Div to use the recursive scanner
  local div = pandoc.Div(doc.blocks)

  -- recursive scanning in modes other than 'images'
  -- if scope == 'all' we tag the whole doc as `imagify`
  if scope ~= 'images' then 
    
    if scope == 'all' then
      div.classes:insert('imagify')
    end
    
    div = scanContainer(div, globalRenderOptions)

  end

  -- imagify any leftover tikz / tex images
  -- using global render options
  div = div:walk({
    Image = function (elem)
      local elemType = imagifyType(elem)
      if elemType then 
        return toImage(elem, elemType, globalRenderOptions)
      end
    end,
  }) 

  return div and pandoc.Pandoc(div.content, doc.meta)
    or nil

end

-- # Return filter

return {
  {
    Meta = init,
    Pandoc = main,
  },
}
