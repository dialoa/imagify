Imagify - Pandoc/Quarto filer convert LaTeX elements into images
====================================================================

[![GitHub build status][CI badge]][CI workflow]

Lua filter to convert some or all LaTeX code in a document into 
images. 

[CI badge]: https://img.shields.io/github/actions/workflow/status/tarleb/lua-filter-template/ci.yaml?branch=main
[CI workflow]: https://github.com/tarleb/lua-filter-template/actions/workflows/ci.yaml

## Overview

* Flexible scope: imagify all, selected only, Tikz only, none.
* Does not imagify when the target output is LaTeX/PDF, unless 
  unless otherwise specified. 
* In HTML, option to embed images within the output file.
* Image rendering options (e.g. zoom); can be specified on a specific
  element.

## Development notes

* Source: LaTeX, including TiKZ. 
* Possible outputs: svg, pdf. Apparently docx handles pdf. Make room to allow for png, just in case.
* Possible modes:
  * Embedded (HTML and EPUB? output only). As inline SVG, or as "src="data:". I've opted for src="data:", percent-encoded. This allows me to output an IMG element in the AST, rather than raw HTML.
  * File, mediabag
  * File, filesystem
* Output element: an Image element, in all cases.
  * Display math handled by adding the style attribute.
  * RawBlock handled by putting the image in a Para
* Elements to handle
  * All, selection

Filter Options
* If imagify is a string, assume it's mode.
* mode: manual (default), all. Future: auto. 
* classes: list of classes within which we imagify (applies to Div and Span). Or map class : options for the class
 libgs_path:

Rendering options
* format: svg, png
* output: embed, mediabag, file
** mode: manual (def), all. Whether to handle all elements. Future: "auto", reads the LaTeX and tries to figure out whether LaTeX can handle all
* preamble: LaTeX preamble. Append. Unless it's a map, with key mode: replace/append/prepend, value: content. 
* dir: path to save
* converter: dvisvgm, pdf2svg, magick, graphicsmagick, ... What to do if the convert clashes with the format style?
* zoom

Regional options: Div/Span attributes
Local options: RawBlock/RawInline attributes

## CONVERTER

dvisvgm: doesn't support lualatex-generated dvi well ('WARNING: font file ... not found).


Usage
------------------------------------------------------------------

The filter modifies the internal document representation; it can
be used with many publishing systems that are based on pandoc.

### Plain pandoc

Pass the filter to pandoc via the `--lua-filter` (or `-L`) command
line option.

    pandoc --lua-filter imagify.lua ...

### Quarto

Users of Quarto can install this filter as an extension with


    quarto install extension tarleb/imagify

and use it by adding `imagify` to the `filters` entry
in their YAML header.

``` yaml
---
filters:
  - imagify
---
```

### R Markdown

Use `pandoc_args` to invoke the filter. See the [R Markdown
Cookbook](https://bookdown.org/yihui/rmarkdown-cookbook/lua-filters.html)
for details.

``` yaml
---
output:
  word_document:
    pandoc_args: ['--lua-filter=imagify.lua']
---
```

License
------------------------------------------------------------------

This pandoc Lua filter is published under the MIT license, see
file `LICENSE` for details.
