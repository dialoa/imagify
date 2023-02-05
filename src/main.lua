--[[-- # Imagify - Pandoc / Quarto filter to convert selected 
  LaTeX elements into images.

@author Julien Dutant <julien.dutant@kcl.ac.uk>
@copyright 2021 Julien Dutant
@license MIT - see LICENSE file for details.
@release 0.1

Pre-renders specified Math and Raw elements as images. 

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
---@field output_folder string directory for output
---@field output_folder_exists bool Internal variable to avoid repeated checks
---@field ligbs_path nil | string, path to Ghostscript library
---@field optionsForClass map of renderOptions for Span/Div classes 
--                            whose LaTeX elements are to be imagified.
---@field extensionForOutput map of image format (SVG or PDF) to use for some output formats.
local filterOptions = {
  scope = 'manual',
  libgs_path = nil,
  output_folder = '',
  output_folder_exists = false,
  optionsForClass = {
    imagify = {},
  },
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
---@field scope string 'manual', 'all', 'none', imagify all/no/selected elements.
---@field force bool imagify even when targeting LaTeX
---@field embed bool whether to embed (if possible) or output as file
---@field pdf_engine string latex command to be used
---@field zoom string to apply when converting pdf/dvi to svg
---@field header_includes string header includes (replace)
---@field add_to_header string header includes (append to those automatically computed)
---@field vertical_align string vertical align value (HTML output)
---@field block_style string style to apply to blockish elements (DisplayMath, RawBlock)
local globalRenderOptions = {
  force = false,
  embed = true,
  pdf_engine = 'xelatex',
  zoom = '1.5',
  header_includes = [[\usepackage{amsmath,amssymb}
\usepackage{unicode-math}
\setmathfont[]{STIX Two Math}
]],
  vertical_align = 'baseline',
  block_style = 'display:block; margin: .5em auto;'
}

-- # Helper functions

-- ## common Lua

---mergeMapInto: returns the result of merging a new map 
-- into an old one without modifying the old one. Not recursive.
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
---@param obj any
local function ensureList(obj)

  return pandoctype(obj) == 'List' and obj
    or pandoc.List:new(obj) 

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

---useTikZ: tell whether a source contains a TikZ picture
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
---@return string filepath of the output
local function runLaTeX(source, options)
	local options = options or {}
  local format = options.format or 'pdf'
  local pdf_engine = options.pdf_engine or 'latex'
  local xetex = pdf_engine:match('^xe')
  local outfile = stripExtension(source, {'tex','latex'})
  local ext = xetex and format == 'dvi' and '.xdv'
                or '.'..format
  local cmd_opts = pandoc.List:new({'--interaction=nonstopmode', source})

  if xetex then
    if format == 'dvi' then
      cmd_opts:insert(1, '--no-pdf')
    end
  else
    cmd_opts:insert(1, '--output-format='..format)
  end

  pandoc.pipe(pdf_engine, cmd_opts, '')

  return outfile..ext

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
	local options = options or {}
	local outfile = options.output 
    or stripExtension(source, {'pdf', 'svg', 'xdv'})..'.svg'
	local source_format = source:match('%.pdf$') and 'pdf'
										or source:match('%.dvi$') and 'dvi'
										or source:match('%.xdv$') and 'dvi'
	local cmd_opts = pandoc.List:new({'--optimize', 
		'--verbosity='..dvisvgmVerbosity(),
--    '--relative',
--  '--no-fonts', 
    '--font-format=WOFF', 
		source
	})

  -- @TODO doesn't work, why?
  if filterOptions.libgs_path and filterOptions.libgs_path ~= '' then
    cmd_opts:insert('--libgs='..filterOptions.libgs_path)
  end

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

-- ## Functions to read and compile options

---buildDefaultTeXPreamble: build a default TeX preamble.
---@param meta Pandoc.Meta
---@return string preamble LaTeX preamble, `\documentclass` included
local function buildDefaultTeXPreamble(meta)
	local template = pandoc.template.compile(preambleTemplate)

	return pandoc.write(pandoc.Pandoc({},meta), 'latex', {template = template})

end

---getRenderOptions: read render options
---@param opts table options map, from doc metadata or elem attributes
---@param table renderOptions map of options
local function getRenderOptions(opts)
  local result = {}

  -- string values
  -- convert "xx-yy" to "xx_yy" keys
  local renderStringKeys = { 
    'zoom', 
    'pdf-engine', 
    'vertical-align',
    'block-style',
  }

  for _,key in ipairs(renderStringKeys) do
    if opts[key] then
      result[key:gsub('-','_')] = stringify(opts[key])
    end
  end

  return result

end

---normalizeOptionsMap: normalize user metadata options.
---@param map Inlines|Blocks|pandoc.MetaMap value of meta.imagify
---@return map userOptions
local function normalizeOptionsMap(map)
  -- keys that must have a string value
  local stringKeys = {'scope', 'libgs-path', 'output-folder'}
  
  -- if only a string, assume it's a `scope` value
  if pandoctype(map) == 'Inlines' or 
    pandoctype(map) == 'Blocks' 
    or pandoctype(map) == 'string' then
      return { scope = stringify(map) }
  end

  for _,key in ipairs(stringKeys) do
    if map[key] and type(map[key]) ~= 'string' then
      map[key] = stringify(map[key]) 
    end
  end

  return map
end

---readImagifyClasses: read user's specification of custom classes
-- This can be a string (single class), a pandoc.List of strings
-- or a map { class = renderOptionsForClass }.
-- We update `filterOptions.classes` accordingly.
---@param opts pandoc.List|pandoc.MetaMap|string
local function readImagifyClasses(opts)
  if pandoctype(opts) ~= 'List' and pandoctype(opts) ~= 'table' then
    opts = pandoc.List:new({ stringify(opts) })
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

--- init: read metadata options.
---@param meta pandoc.Meta doc's metadata
local function init(meta)
  userOptions = meta.imagify and normalizeOptionsMap(meta.imagify)
    or {}

  filterOptions.scope = userOptions.scope == 'all' and 'all'
        or userOptions.scope == 'none' and 'none'
        or userOptions.scope == 'selected' and 'manual' -- alias
        or 'manual'

  filterOptions.force = userOptions.force and userOptions.force ~= 'false'
        and userOptions.force ~= 'no'
        or false

  filterOptions.libgs_path = userOptions['libgs-path'] and userOptions['libgs-path']
        or nil

  filterOptions.output_folder = userOptions['output-folder'] and userOptions['output-folder']

  globalRenderOptions = mergeMapInto(getRenderOptions(userOptions),
    globalRenderOptions)

  if userOptions.classes then
    filterOptions.classes = readImagifyClasses(userOptions.classes)
  end


end

-- ## Functions to handle preamble templates

local function addTemplate(source)
  templates:insert({ source = source, compiled = nil})
end

local function getTemplate(n)
  if templates[n] then
    templates[n].compiled = templates[n].compiled
      or pandoc.template.compile(templates[n].source)
    return templates[n].compiled
  else
    return nil
  end
end

-- ## Functions to convert images

---buildTeXDoc: turns LaTeX element into a LaTeX doc source.
---@param text string LaTeX code
---@param renderOptions table render options
---@param elemType string 'InlineMath', 'DisplayMath', 'RawInline', 'RawBlock'
local function buildTeXDoc(text, renderOptions, elemType)
  local elemType = elemType and elemType or 'InlineMath'
  local text = text or ''
  local renderOptions = renderOptions or {}
  local classopts = ''
  local preamble = renderOptions.header_includes or ''
  local before = ''
  local after = ''
  local template = [[\documentclass[%s]{standalone}
    %s
    \begin{document}
    %s
    %s
    %s
    \end{document}
  ]]
  
  -- wrap DisplayMath and InlineMath in math mode
  -- for display math we use \displaystyle 
  --  see <https://tex.stackexchange.com/questions/50162/how-to-make-a-standalone-document-with-one-equation>
  if elemType == 'DisplayMath' then
    text = '$\\displaystyle\n'..text..'$'
  elseif elemType == 'InlineMath' then
    text = '$'..text..'$'
  end

  return template:format(classopts, preamble, before, text, after)

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


---latexToImage: convert LaTeX to image.
--  The image can be exported as SVG string or as a SVG or PDF file.
---@param source string LaTeX source document
---@param renderOptions table rendering options
---@return string result file contents or filepath or ''.
--- latexToImage: convert LaTeX to image.
-- The image can be exported as SVG string (`raw`), or as file in 
-- the mediabag (`media`) the filesystem (`file`). 
-- @param source string LaTeX source document
-- @param options table of conversion options.
--      export = string 'mediabag' or 'file' or 'raw'
--      format = string, 'svg' or 'pdf'
--      filepath = string, output file path
--      pdf_engine = 'latex', 'pdflatex', 'xelatex', 'lualatex'. 
--     }
-- @return string filepath if file, svg code if raw
local function latexToImage(source, renderOptions)
	local options = renderOptions or {}
  local ext = filterOptions.extensionForOutput[FORMAT]
    or filterOptions.extensionForOutput.default
  local embed = options.embed and ext == 'svg' and FORMAT:match('html') or false
  local pdf_engine = options.pdf_engine or 'latex'
  local latex_out_format = ext == 'svg' and 'dvi' or 'pdf'
  local folder, folderAbs, file, fileAbs = '', '', '', ''
  local result = ''

  -- it not embedding prepare folder and file names
  -- we need absolute paths to move things out of the temp dir
  if not embed then
    folder = filterOptions.output_folder or ''
    folderAbs = path.is_absolute(folder) and folder
      or path.join{ system.get_working_directory(), folder}
    file = createUniqueName(source, renderOptions)..'.'..ext
    fileAbs = path.join{folderAbs, file}
    file = path.join{folder, file}

    -- don't regenerate files that already exist
    if fileExists(file) then 
      return file
    end

  end

	system.with_temporary_directory('imagify', function (tmpdir)
			system.with_working_directory(tmpdir, function()

      	writeToFile(source, 'source.tex')

        -- result = 'source.dvi'|'source.xdv'|'source.pdf'
				result = runLaTeX('source.tex', {
					format = latex_out_format,
					pdf_engine = pdf_engine,
				})

        if ext == 'svg' then

          -- result = 'source.svg'
					result = toSVG(result, {
            zoom = renderOptions.zoom,
          })

        end

        if embed then

          -- read svg contents and cleanup
          result = "<?xml version='1.0' encoding='UTF-8'?>\n"
            .. getSVGFromFile(result)

          -- URL encode
          result = 'data:image/svg+xml,'..urlEncode(result)

        else

          if not filterOptions.output_folder_exists then
            ensureFolderExists(folderAbs)
            filterOptions.output_folder_exists = true
          end

          os.rename(result, fileAbs)
          result = file

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

--- toImage: convert to pandoc.Image using specified rendering options.
---@param elem pandoc.Math|pandoc.RawInline|pandoc.RawBlock
---@param renderOptions table rendering options
---@return pandoc.Image elem
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
  img = createImageElemFrom(code, result, renderOptions, elemType)
 
  return elemType == 'RawBlock' and pandoc.Para(img)
    or img

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
    -- apply class rendering options
    local opts = mergeMapInto(filterOptions.optionsForClass[class], 
                    renderOptions)
    -- apply any locally specified rendering options
    opts = mergeMapInto(getRenderOptions(elem.attributes), opts) 
    --- recursive scanner with updated options
    local scan = function (elem) return scanContainer(elem, opts) end
    --- imagifier with updated options
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

