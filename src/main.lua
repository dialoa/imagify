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

---@alias fo_scope 'manual'|'all'|'none', # imagify scope
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

--- latexType: identify the Pandoc type of a LaTeX element.
---@param elem pandoc.Math|pandoc.RawBlock|pandoc.RawInline element
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

-- ## Smart imagifying functions

---usesTikZ: tell whether a source contains a TikZ picture
---@param source string LaTeX source
---@return boolean result
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
    success = os.execute(env..cmd..cmd)
  end

  if success then

    return true, outfile..ext

  else

    local result = 'LaTeX compilation failed.\n'
      ..'Command used: '..cmd..'\n'
    log = readFile(outfile..'.log')
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
---   scope: 'all'|'manual'|'none'|nil
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
-- classes in `imagify-classes:` override those in `imagify: classes:`
-- Special cases:
--    filterOptions.no_html_embed: Pandoc can't handle URL-embedded images when extract-media is on
---@param meta pandoc.Meta doc's metadata
local function init(meta)
  -- If `meta.imagify` isn't a map assume it's a `scope` value 
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
  local svg_converter = renderOptions.svg_converter or 'dvisvgm'
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
  if endFormat == 'svg' and svg_converter == 'dvisvgm' then
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
  local jobFolder = makeAbsolute(PANDOC_STATE.output_file 
    and path.directory(PANDOC_STATE.output_file) or '')
  local texinputs = renderOptions.texinputs
    or jobFolder..'//:' 
  -- to be created
  local folderAbs, file, fileAbs, texfileAbs = '', '', '', ''
  local fileRelativeToJob = ''
  local success, result

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
    fileRelativeToJob = path.make_relative(fileAbs, jobFolder)

    -- if lazy, don't regenerate files that already exist
    if not embed and lazy and fileExists(fileAbs) then 
      return fileRelativeToJob
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

            os.rename(result, fileAbs)
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
---@return pandoc.Image|pandoc.Inlines elem
local function toImage(elem, renderOptions)
  local elemType = latexType(elem)
  local code = elem.text or ''
  local doc = ''
  local success, result, img

  -- prepare LaTeX source document
  doc = buildTeXDoc(code, renderOptions, elemType)

  -- convert to file or string
  success, result = latexToImage(doc, renderOptions)

  -- prepare Image element
  if success then 
    img = createImageElemFrom(code, result, renderOptions, elemType)
    if elemType == 'RawBlock' then
      img = pandoc.Para(img)
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
      if latexType(el) then 
        return toImage(el, opts)
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

  if scope == 'none' or (outputIsLaTeX() and not force) then
      return nil
  end

  -- whole doc wrapped in a Div to use the recursive scanner
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

