
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

["module"] = function()
--------------------
-- Module: 'module'
--------------------

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

@author Julien Dutant <julien.dutant@kcl.ac.uk>
@copyright 2021 Julien Dutant
@license MIT - see LICENSE file for details.
@release 0.1

Pre-renders specified Math and Raw elements as images. 

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

-- # Global variables

local stringify = pandoc.utils.stringify
local pandoctype = pandoc.utils.type
local system = pandoc.system
local path = pandoc.path
local mediabag = pandoc.mediabag

---@class filterOptions filter's general setup.
---@field scope string 'manual', 'all', 'none', imagify all/no/selected elements.
---@field lazy boolean do not regenerate image files if they exist (default true)
---@field output_folder string directory for output
---@field output_folder_exists bool Internal variable to avoid repeated checks
---@field ligbs_path nil | string, path to Ghostscript library
---@field optionsForClass map of renderOptions for specific Span/Div classes 
--                            whose LaTeX elements are to be imagified.
---@field extensionForOutput map of image format (SVG or PDF) to use for some output formats.
local filterOptions = {
  scope = 'manual',
  lazy = true,
  libgs_path = nil,
  output_folder = '',
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

---@class globalRenderOptions
---The following fields, plus a number of Pandoc metadata
---keys like header-includes, fontenc, colorlinks etc. 
---See getRenderOptions() for details.
---@field force bool imagify even when targeting LaTeX
---@field embed bool whether to embed (if possible) or output as file
---@field template string identifier of a Pandoc template (default 'default')
---@field pdf_engine string latex command to be used
---@field converter string pdf/dvi to svg converter (default 'dvisvgm')
---@field zoom string to apply when converting pdf/dvi to svg
---@field vertical_align string vertical align value (HTML output)
---@field block_style string style to apply to blockish elements (DisplayMath, RawBlock)
local globalRenderOptions = {
  force = false,
  embed = true,
  template = 'default',
  pdf_engine = 'latex',
  converter = 'dvisvgm',
  zoom = '1.5',
  vertical_align = 'baseline',
  block_style = 'display:block; margin: .5em auto;'
}

---@class Templates
---Templates.id = { source = string, compiled = Template}
---default key reserved for Pandoc's default template
local Templates = {
  default = {},
}

-- # Helper functions

-- ## Debugging

---message: send message to std_error
---comment
---@param type 'INFO'|'WARNING'|'ERROR'
---@param text string error message
local function message (type, text)
    local level = {INFO = 0, WARNING = 1, ERROR = 2}
    if level[type] == nil then type = 'ERROR' end
    if level[PANDOC_STATE.verbosity] <= level[type] then
        io.stderr:write('[' .. type .. '] Imagify: ' 
            .. text .. '\n')
    end
end

-- ## common Lua

---tfind: finds a value in an array
---comment
---@param tbl table
---@return result number|false 
local function tfind(tbl, needle)
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
---@param list string<> list of strings
---@param separator string separator (optional)
local function concatStrings(list, separator)
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
local function mergeMapInto(new,old)
  local result = {} -- we need to clone
  if type(old) == 'table' then 
    for k,v in pairs(old) do result[k] = v end
  end
  if type(new) == 'table' then
    for k,v in pairs(new) do result[k] = v end
  end
  return result
end

-- ## Pandoc AST functions

--outputIsLaTeX: checks whether the target output is in LaTeX
---@return bool
local function outputIsLaTeX()
  return FORMAT:match('latex') or FORMAT:match('beamer') or false
end

--- ensureList: ensures an object is a pandoc.List.
---@param obj any|nil
local function ensureList(obj)

  return pandoctype(obj) == 'List' and obj
    or pandoc.List:new{obj} 

end

--- latexType: identify the Pandoc type of a LaTeX element.
---@param elem pandoc.Math|pandoc.RawBlock|pandoc.Rawinline element
---@return string|nil 'InlineMath', 'DisplayMath', 'Rawblock', 'RawInline'
-- or nil if the element isn't a LaTeX-containing element.
local function latexType(elem)
  return elem.mathtype == 'InlineMath' and 'InlineMath'
  or elem.mathtype == 'DisplayMath' and 'DisplayMath'
  or (elem.format == 'tex' or elem.format == 'latex')
  and (elem.t == 'RawBlock' and 'RawBlock'
    or elem.t == 'RawInline' and 'RawInline')
  or nil
end

---extractLaTeX: extract LaTeX from (List of) Blocks or Inlines
---@param obj pandoc.List | pandoc.Blocks | pandoc.Inlines 
---@return string 
local function extractLaTeX(obj)
  local obj_type = pandoc.utils.type(obj)
  local result = ''
  print(obj_type)

  extractor = function(el) 
    if el.format == 'tex' or el.format == 'latex' then
      result = result .. el.text .. '\n'
    end
  end
  filter = {
    RawBlock = extractor,
    RawInline = extractor,
  }

  if obj_type == 'List' then
    for _,elem in ipairs(obj) do
      result = result .. extractLaTeX(elem)
    end
  elseif obj_type == 'Blocks' then
    pandoc.Div(obj):walk(filter)
  elseif obj_type == 'Inlines' then
    pandoc.Div(obj):walk(filter)
  end

  return result

end

-- ## File functions

---fileExists: checks whether a file exists
local function fileExists(filepath)
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
local function makeAbsolute(filepath, root)
  root = root or system.get_working_directory()
  return path.is_absolute(filepath) and filepath
    or path.join{ root, filepath}
end

---folderExists: checks whether a folder exists
local function folderExists(folderpath)

  -- the empty path always exists
  if folderpath == '' then return true end

  -- normalize folderpath
  folderpath = folderpath:gsub('[/\\]$','')..path.separator
  local ok, err, code = os.rename(folderpath, folderpath)
  -- err = 13 permission denied
  return ok or err == 13 or false
end

---ensureFolderExists: create a folder if needed
local function ensureFolderExists(folderpath)
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
---@return nil | string status error message
local function writeToFile(contents, filepath)
  local f = io.open(filepath, 'w')
	if f then 
	  f:write(contents)
	  f:close()
  else
    return 'File not found'
  end
end

---readFile: read file as string.
---@param filepath string file path
---@return string contents or empty string if failure
local function readFile(filepath)
	local contents
	local f = io.open(filepath, 'r')
	if f then 
		contents = f:read('a')
		f:close()
	end
	return contents or ''
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

-- ## Smart imagifying functions

---usesTikZ: tell whether a source contains a TikZ picture
---@param source string LaTeX source
---@return bool result
local function usesTikZ(source)
  return source:match('\\begin{tikzpicture}') and true or false
end

-- ## Converter functions

local function dvisvgmVerbosity()
	return PANDOC_STATE.verbosity == 'ERROR' and '1'
				or PANDOC_STATE.verbosity == 'WARNING' and '2'
				or PANDOC_STATE.verbosity == 'INFO' and '4'
        or '2'
end

---runLaTeX: runs latex engine on file
---@param source string filepath of the source file
---@param options table options
--    format = output format, 'dvi' or 'pdf',
--    pdf_engine = pdf engine, 'latex', 'pdflatex', 'xelatex', 'xetex', '' etc. 
---@return string|nil filepath path to the output file if successful
local function runLaTeX(source, options)
	options = options or {}
  local format = options.format or 'pdf'
  local pdf_engine = options.pdf_engine or 'latex'
  local outfile = stripExtension(source, {'tex','latex'})
  local ext = pdf_engine == 'xelatex' and format == 'dvi' and '.xdv'
                or '.'..format
  -- additional options must come *after* -<engine> and *before* <source>
  local cmd = pandoc.List:new({
    'latexmk -'..pdf_engine, 
    '--interaction=nonstopmode',
    source})
  local success = ''
  
  -- latexmk silent mode
  if PANDOC_STATE.verbosity == 'ERROR' then
    cmd:insert(2, '-silent')
  end

  -- xelatex doesn't accept `output-format`,
  -- generates both .pdf and .xdv
  if pdf_engine ~= 'xelatex' then
    cmd:insert(2, '--output-format='..format)
  end

  success = pcall(function (cmd)
    os.execute(concatStrings(cmd))    
  end)

  if success then

    return outfile..ext

  else
    message('ERROR', 'LaTeX generation failed. See LaTeX log below (if it exists).')
    local log = readFile(outfile..'.log')
    if log then print(log) end

  end

end

--- toSVG: convert latex output to SVG.
-- @param source string source filepath
-- @param options table of options:
--    output = string output filepath (directory must exist),
--    zoom = string zoom factor, e.g. 1.5
-- @return string output filepath
-- @note Ghostcript library required to convert PDF files.
--        See divsvgm manual for more details.
local function toSVG(source, options)
  if source == nil then return end
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

	pandoc.pipe('dvisvgm', cmd_opts, '')

	return outfile

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
---   scope: 'all'|'manual'|'none'|nil
---   libgs_path: string
---   output_folder: string
---@param opts table options map from meta.imagify
---@return table result map of options
local function getFilterOptions(opts)
  local result = {}
  local stringKeys = {'scope', 'libgs-path', 'output-folder'}
  local boolKeys = {'lazy'}

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
    or opts.scope == 'none' and 'none'
  ) or nil

  result.libgs_path = opts['libgs-path'] and opts['libgs-path']

  result.output_folder = opts['output-folder'] and opts['output-folder']

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
    'keep-sources',
  }
  local renderStringKeys = {
    'pdf-engine',
    'converter',
    'zoom', 
    'vertical-align',
    'block-style',
  }
  local renderListKeys = {
    'classoption',
    'link',
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
    pdf_engine = {'latex', 'pdflatex', 'xelatex', 'lualatex'},
    converter = {'dvisvgm'},
  }

  -- boolean values
  -- convert "xx-yy" to "xx_yy" keys
  for _,key in ipairs(renderBooleanlKeys) do
    if opts[key] ~= nil and pandoctype(opts[key]) == 'boolean' then
      result[key:gsub('-','_')] = opts[key]
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
---@param meta pandoc.Meta doc's metadata
local function init(meta)
  -- If `meta.imagify` isn't a map assume it's a `scope` value 
  local userOptions = meta.imagify 
    and (pandoctype(meta.imagify) == 'table' and meta.imagify
      or {scope = stringify(meta.imagify)}
    ) 
    or {}
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

  globalRenderOptions = mergeMapInto(
    getRenderOptions(userOptions),
    globalRenderOptions
  )

  if userOptions.classes then
    filterOptions.classes = readImagifyClasses(userOptions.classes)
  end


end

-- ## Functions to convert images

---getTemplate: get a compiled template
---@param id string template identifier (key of Templates)
---@return tpl Template|nil result
local function getTemplate(id)
  if not Templates[id] then
    return nil
  end

  -- ensure there's a non-empty source, otherwise return nil

  -- special case: default template, get source from Pandoc
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
---@param text string LaTeX code
---@param renderOptions table render options
---@param elemType string 'InlineMath', 'DisplayMath', 'RawInline', 'RawBlock'
local function buildTeXDoc(text, renderOptions, elemType)
  local endFormat = filterOptions.extensionForOutput[FORMAT]
    or filterOptions.extensionForOutput.default
  elemType = elemType and elemType or 'InlineMath'
  text = text or ''
  renderOptions = renderOptions or {}
  local template = renderOptions.template or 'default'
  local converter = renderOptions.converter or 'dvisvgm'
  local doc = nil
  
  -- wrap DisplayMath and InlineMath in math mode
  -- for display math we must use \displaystyle 
  --  see <https://tex.stackexchange.com/questions/50162/how-to-make-a-standalone-document-with-one-equation>
  if elemType == 'DisplayMath' then
    text = '$\\displaystyle\n'..text..'$'
  elseif elemType == 'InlineMath' then
    text = '$'..text..'$'
  end

  doc = pandoc.Pandoc(
    pandoc.RawBlock('latex', text),
    pandoc.Meta(renderOptions)
  )

  -- modify the doc's meta values as required
  --@TODO set class option class=...
  --Stanlone tikz needs \standaloneenv{tikzpicture}
  local headinc = ensureList(doc.meta['header-includes'])
  local classopt = ensureList(doc.meta['classoption'])

  -- Standalone class `dvisvgm` option: make output file
  -- dvisvgm-friendly (esp TikZ images).
  -- Not compatible with pdflatex
  if endFormat == 'svg' and converter == 'dvisvgm' then
    classopt:insert(pandoc.Str('dvisvgm'))
  end
  
  -- The standalone class option `tikz` needs to be activated
  -- to avoid an empty page of output.
  if usesTikZ(text) then
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

---createUniqueName: return a name that uniquely identify an image.
---Combines LaTeX sources and rendering options.
---@param source string LaTeX source for the image
---@param renderOptions table render options
---@return string filename without extension
local function createUniqueName(source, renderOptions)
  return pandoc.sha1(source .. 
    '|Zoom:'..renderOptions.zoom)
end

---findTarget: find linked file and return the source
-- and target for a `ln` command.
---@param link string 
---@return src string src of ln (must be a filename, no subdir)
---@return tar string target of ln (absolute path)
local function findTarget(link)
  link = stringify(link)
  local searchPath = pandoc.List:new{ '' }
  local src, tar = nil, nil

  for _, p in ipairs(searchPath) do
    if fileExists(path.join{ p, link }) then
      src = path.filename(link)
      tar = makeAbsolute(path.join{ p, path.directory(link)})
      break
    end
  end

  return src, tar
end

---latexToImage: convert LaTeX to image.
--  The image can be exported as SVG string or as a SVG or PDF file.
---@param source string LaTeX source document
---@param renderOptions table rendering options
---@return string result file contents or filepath or ''.
local function latexToImage(source, renderOptions)
  local options = renderOptions or {}
  local ext = filterOptions.extensionForOutput[FORMAT]
    or filterOptions.extensionForOutput.default
  local lazy = filterOptions.lazy
  local embed = options.embed
    and ext == 'svg' and FORMAT:match('html') and true 
    or false
  local pdf_engine = options.pdf_engine or 'latex'
  local latex_out_format = ext == 'svg' and 'dvi' or 'pdf'
  local linkedFiles = options.link or {}
  local keep_sources = options.keep_sources or false
  local folder = filterOptions.output_folder or ''
  local jobFolder = makeAbsolute(PANDOC_STATE.output_file 
    and path.directory(PANDOC_STATE.output_file) or '')
  local folderAbs, file, fileAbs, texfileAbs = '', '', '', ''
  local fileRelativeToJob = ''
  local symLinks = {}
  local result = ''

  -- Find any files to symlink and populate symLinks
  -- Look for them in working dir and sources dir 
  for _,link in ipairs(linkedFiles) do
    local src, tar = findTarget(link)
    if target then
      symLinks[src] = tar
    else
      message('WARNING', 'Could not find linked resource '..stringify(link)
        ..'. Imagifying might break down.')
    end
  end

  -- if we output files prepare folder and file names
  -- we need absolute paths to move things out of the temp dir
  if not embed or keep_sources then
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
    fileRelativeToJob = path.make_relative(fileAbs, jobFolder)

    -- if lazy, don't regenerate files that already exist
    if not embed and lazy and fileExists(fileAbs) then 
      return fileRelativeToJob
    end

  end

	system.with_temporary_directory('imagify', function (tmpdir)
			system.with_working_directory(tmpdir, function()

      	writeToFile(source, 'source.tex')

        -- keep_sources is for debugging, do it before LaTeX runs
        if keep_sources then
          writeToFile(source, texfileAbs)
        end

        -- create symlinks
        for src, tar in pairs(symLinks) do
          os.execute('ln -s '..src..' '..tar)
        end

        -- result = 'source.dvi'|'source.xdv'|'source.pdf'|nil
				result = runLaTeX('source.tex', {
					format = latex_out_format,
					pdf_engine = pdf_engine,
				})

        -- further conversions of dvi/pdf?

        if ext == 'svg' then

          -- result = 'source.svg'
					result = toSVG(result, {
            zoom = renderOptions.zoom,
          })

        end

        -- embed or save

        if result then

          if embed then

            -- read svg contents and cleanup
            result = "<?xml version='1.0' encoding='UTF-8'?>\n"
              .. getSVGFromFile(result)

            -- URL encode
            result = 'data:image/svg+xml,'..urlEncode(result)

          else

            os.rename(result, fileAbs)
            result = fileRelativeToJob

          end

        end

    end)
  end)

  return result

end

---createImageElemFrom(src, renderOptions, elemType)
---@param text string source code for the image
---@param src string URL (possibly URL encoded data)
---@param renderOptions table render Options
---@param elemType string 'InlineMath', 'DisplayMath', 'RawInline', 'RawBlock'
---@return pandoc.Image img
local function createImageElemFrom(text, src, renderOptions, elemType)
  local title = text or ''
  local caption = 'Image based on the LaTeX code:' .. title
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
---@param elem pandoc.Math|pandoc.RawInline|pandoc.RawBlock
---@param renderOptions table rendering options
---@return pandoc.Image|pandoc.Math|pandoc.RawInline|pandoc.RawBlock elem
local function toImage(elem, renderOptions)
  local elemType = latexType(elem)
  local code = elem.text or ''
  local doc = ''
  local result = ''
  local img = nil

  -- prepare LaTeX source document
  doc = buildTeXDoc(code, renderOptions, elemType)

  -- convert to file or string
  result = latexToImage(doc, renderOptions)

  -- prepare Image element
  if result then 
    img = createImageElemFrom(code, result, renderOptions, elemType)
    if elemType == 'RawBlock' then
      img = pandoc.Para(img)
    end
  else
    img = elem
  end
 
  return img
  
end

-- ## Functions to traverse the document tree

---imagifyClass: find an element's imagify class, if any.
---If both `imagify` and a custom class is present, return the latter.
---@param elem Pandoc.Div|pandoc.Span
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
---@param elem Pandoc.Div|pandoc.Span
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
    --- build recursive scanner from updated options
    local scan = function (elem) return scanContainer(elem, opts) end
    --- build imagifier from updated options
    local imagify = function(el) return toImage(el, opts) end
    --- apply recursion first, then imagifier
    return elem:walk({
      Div = scan,
      Span = scan,
    }):walk({
      Math = imagify,
      RawInline = imagify,
      RawBlock = imagify,  
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
  local force = filterOptions.force
  local div = nil

  if scope == 'none' or (outputIsLaTeX() and not force) then
      return nil
  end

  local div = pandoc.Div(doc.blocks)

  -- if scope == 'all' we tag the whole doc as `imagify`
  if scope == 'all' then 
    div.classes:insert('imagify')
  end

  div = scanContainer(div, globalRenderOptions)

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
