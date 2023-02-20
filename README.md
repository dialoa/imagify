Imagify - Pandoc/Quarto filter to convert selected LaTeX into images
====================================================================

[![GitHub build status][CI badge]][CI workflow]

Lua filter to convert some or all LaTeX code in a document into 
images. 

[CI badge]: https://img.shields.io/github/actions/workflow/status/tarleb/lua-filter-template/ci.yaml?branch=main
[CI workflow]: https://github.com/tarleb/lua-filter-template/actions/workflows/ci.yaml

Overview
--------------------------------------------------------------------

Imagify turns selected (or all) LaTeX elements in a document into 
images. Out of the box it tries to match the document's settings
as closely as possible (fonts, LaTeX packages etc.), but its conversion
options are fully customizable. 

In HTML output images can be embedded within the document itself.

Requirements: a LaTeX installation with the `latexmk` and `dvisvgm`
tools. 

Limitations:

* So far designed with HTML output in mind, LaTeX to SVG conversion.
* In other output formats the images will be inserted / linked as PDFs,
  and may display in wrong sizes or not at all. 

Installation
------------------------------------------------------------------

### Plain pandoc

Pass the filter to pandoc via the `--lua-filter` (or `-L`) command
line option.

    pandoc --lua-filter imagify.lua ...

### Quarto

Users of Quarto can install this filter as an extension with

    quarto install extension dialoa/imagify

and use it by adding `imagify` to the `filters` entry
in their YAML header:

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

Basic usage
------------------------------------------------------------------

In your markdown source, enclose a section of your document within
a Div with class `imagify`:


``` markdown
::: imagify

... (text and LaTeX) ...

:::
```

In non-LaTeX output, any LaTeX math or raw LaTeX element will
be converted into an image, placed within an `_imagify` folder in
your current working directory.

Images are generated using the LaTeX options specified
in your document's metadata, if any. 
(See the [Pandoc manual][PMan] for details.) 

[PMan]: https://pandoc.org/MANUAL.html#variables-for-latex

If a LaTeX element is or contains a TikZ picture, the TikZ
package is loaded. If you need a specific library, place
a `\usetikzlibrary` command at the beginning of your picture
code.

Options are specified via `imagify` and `imagify-classes` metadata
variables. For instance, temporarily disable Imagify with:

```
imagify: none
```

Set Imagify to convert all LaTeX in a document, though this
will be slow if it contains many formulas with:

```
imagify: all
```

Set the images to be embedded in HTML output with:

``` yaml
imagify:
  embed: true
```

Change the images' zoom factor with:

``` yaml
imagify:
  zoom: 1.6
```

The default is 1.5, which seems to work well with Pandoc's default 
standalone HTML output.

If image conversion fails, you can set the debug option 
that will give you the `.tex` files that the filter
produces and passes to LaTeX:

``` yaml
imagify:
  debug: true
```

The `.tex` files are placed in the output folder 
(by default `_imagify` in your working directory). 
You can try to compile them yourself and see how to 
change them. 

Create custom imagifying classes with different
options with the `imagify-class` variable:

``` yaml
imagify:
  zoom: 1.6
imagify-classes:
  mybigimage: 
    zoom: 2
  mysmallimage:
    zoom: 1
```

You can also specify rendering options on a Div itself:

``` markdown

::: {.imagify zoom='2' debug='true'}

... (text with LaTeX element)

:::

Options reference
------------------------------------------------------------------

()

License
------------------------------------------------------------------

This pandoc Lua filter is published under the MIT license, see
file `LICENSE` for details.
