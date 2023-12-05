Imagify - Pandoc/Quarto filter to convert selected LaTeX into images
====================================================================

[![GitHub build status][CI badge]][CI workflow]

Lua filter to convert some or all LaTeX code in a document into 
images. 

Copyright 2022-2023 Philosophie.ch <https://philosophie.ch>. 
Maintained by Julien Dutant <https://github.com/jdutant>.

[CI badge]: https://img.shields.io/github/actions/workflow/status/dialoa/imagify/ci.yaml?branch=main
[CI workflow]: https://github.com/dialoa/imagify/actions/workflows/ci.yaml

Overview
--------------------------------------------------------------------

Imagify turns selected LaTeX elements into images in non-LaTeX/PDF
output. It also allows you to use `.tex` or `.tikz` elements as
image sources files, which is useful to create cross-referenceable
figures with [Pandoc-crossref][] or [Quarto][].

By default, Imagify tries to match the document's LaTeX output settings 
(fonts, LaTeX packages, etc.). Its rendering options otherwise 
extensively configurable, and different rendering options can 
be used for different elements. It can embed its images within HTML 
output or provide them as separate image files. 

Requirements: [Pandoc][] or [Quarto][], a LaTeX installation 
(with `dvisvgm` and, recommended, `latexmk`, which are included
in common LaTeX distributions).

Limitations:

* So far designed with HTML output in mind, LaTeX to SVG conversion,
  and LaTeX/PDF outputs with separate `.tikz` or `.tex` files as
  image sources. 
  In other output formats, the images will be inserted or linked as PDFs
  and may display in wrong sizes or not at all. 
* Embedding within HTML output isn't compatible with Pandoc's 
  `extract-media` option.

Installation
------------------------------------------------------------------

### Plain pandoc

Pass the filter to Pandoc via the `--lua-filter` (or `-L`) command
line option.

    pandoc --lua-filter imagify.lua ...

### Quarto

Install this filter as a Quarto extension with

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

### Imagifying

LaTeX elements to be imagified should be placed in a Div block
with class `imagify`. In markdown source:

~~~~~ markdown
::: imagify

This display LaTeX formmula will be imagified:

$$\binom{n}{k} = \frac{n!}{k!(n-k)!}$$

As well as this TikZ picture:

\begin{tikzpicture}
\draw (-2,0) -- (2,0);
\filldraw [gray] (0,0) circle (2pt);
\draw (-2,-2) .. controls (0,0) .. (2,-2);
\draw (-2,2) .. controls (-1,0) and (1,0) .. (2,2);
\end{tikzpicture}

And this raw LaTeX block:

```{=latex}
\fitchprf{
  \pline{A} \\
  \pline{A \rightarrow B}
}
{ \pline{B} }
```

This image with a `.tikz` source file will be imagified
too. In LaTeX/PDF output it will turned into an imported
PDF image too.

![Figure: a TikZ image](figure1.tikz){#fig-1 .some-attributes}

:::
~~~~~

1. LaTeX math and raw LaTeX elements in the Div are converted to images
unless the output format is LaTeX/PDF. 
1. Image elements with a `.tikz` or `.tex` source in the Div are 
    converted to images in all output formats. Attributes on the image
    are preserved. This is useful for cross-referencing with Pandoc-Crossref
    or Quarto. 

Images files are placed in
an `_imagify` folder created in your current working directory. 
See the `test/input.md` file for an example. 

Images are generated using any Pandoc LaTeX output options specified
in your document's metadata suited for a `standalone` class document, 
such as `fontfamily`, `fontsize` etc. See the [Pandoc manual][PManTeX] 
for details.

If a LaTeX element is or contains a TikZ picture, the TikZ
package is loaded. If you need a specific library, place
a `\usetikzlibrary` command at the beginning of your picture
code.

For Image elements with a `.tikz` or `.tex` source file,
the source file should not include a LaTeX preamble nor
`\begin{document}...\end{document}`. The two extensions
are treated the same way: if the file contains `\tikz`
or `\begin{tikzpicture}` then TikZ is loaded. 

Custom LaTeX packages not included in standard LaTeX 
distribution (e.g. `fitch.sty`) can be used, provided
you place them in the source file's folder or one of 
its subfolder, or specify an appropriate location
via the `texinputs` option. 

### Warning: standalone class restrictions

LaTeX elements are imagified using [LaTeX's `standalone`
class][Standalone], which imposes some unexpected restrictions. 
If you're only imagifying inline (`$...$`) or display (`$$...$$`) 
formulas weaved in your document, Imagify handles them
for you. 

However, if you imagify Raw LaTeX
or from a separate `.tex` or `.tikz` file, your LaTeX
code must be compatible with the standalone class. The most
common error is to enter display formulas:

```
source.md

![Figure 1: my equation](figure.tex)

figure1.tex

$$
my fancy formula
$$

```
When Imagify converts `figure1.tex` LaTeX crashes because 
the `standalone` class doesn't accept paragraph elements 
like display formulas. What you need instead is an inline
formula in 'display style':

``` latex
figure1.tex

$\displaystyle
my fancy formula
$
```

### Imagifying options

Options are specified via `imagify` and `imagify-classes` 
metadata variables. For instance, temporarily disable 
Imagify with:

``` yaml
imagify: none
```

Set Imagify to convert all LaTeX in a document with:

``` yaml
imagify: all
```

This probably not a good idea if your document contains
many LaTeX elements that could be rendered by MathJAX
or equivalent. 

Set the images to be embedded in the HTML output file,
rather than provided as separate files, with:

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
You can try to compile them yourself and see what 
changes or packages are needed.

Create custom imagifying classes with their own
rendering options with the `imagify-class` variable:

``` yaml
imagify:
  zoom: 1.6
imagify-classes:
  mybigimage: 
    zoom: 2
  mysmallimage:
    zoom: 1
```

*Note*. If a Div has multiple imagify-classes, only
the first encountered is used. This may not be the 
first one you specified. If a Div has the class `imagify`
and a specific imagify-class, the latter is used.

You can further specify rendering options on a Div itself:

~~~~~ markdown
::: {.imagify zoom='2' debug='true'}

... (text with LaTeX element)

:::
~~~~~

Rendering options are applied in a cascading manner. 
To determine which options apply to given LaTeX element, 
we apply in that order:

- the Document's LaTeX options (`fontsize` etc)
- Imagify options
- For each imagify-class Div containing the element, starting
  with the widest-scope one, we apply its class options first, 
  then any option locally specified on the Div itself.  

Options reference
------------------------------------------------------------------

Options are provided in the document's metadata. These are provided
either in a YAML block in markdown source, or as a separate 
YAML file loaded with the pandoc option `--metadata-file`. Here is
an example:

~~~~~ yaml
fontsize: 12pt
header-includes:
  ``` {=latex}
  \usepackage
  ```
imagify:
  scope: all
  debug: true
  embed: true
  lazy: true
  output-folder: _imagify_files
  pdf-engine: xelatex
  keep-sources: false
  zoom: 1.5
imagify-classes: 
  pre-render:
      zoom: 4 # will show if it's not overriden
      block-style: "border: 1px solid red;"
  fitch:
    debug: false
    header-includes: \usepackage{fitch}
~~~~~

### `imagify` and `imagify-classes`

`imagify`
: string or map. If string, assumed to be a `scope` option.
  If map, filter options and global rendering options.

`imagify-class`
: map of class-name: map of rendering options.

### Filter options

Specified within the `imagify` key.

`scope`
: string `all`, `none`, `selected` (alias `manual`). Default `selected`.

`lazy`
: boolean. If set to true, existing images won't be regenerated 
  unless there is a change of code or zoom. Default true.

`output-folder`
: string, path to the folder where images should be output. 
  Default `_imagify`.

`ligs-path`
: string, path to the Ghostscript library. Default nil.
  This is not the Ghostscript program, but its library. It's
  passed to `dvisvgm`. See [DvisvgmMan] for details.

### Rendering options

These can differ from one imagified element to another.

Specified within the `imagify` metadata
key, within a key of the `imagify-class` map, or on
as attributes of an imagify class Div elements.

#### Conversion

`debug`
: boolean. Save the `.tex` files used to generate images 
  in the output folder (see `output_folder` filter option). 
  Default: false. 

`force`
: imagify even when the output is LaTeX/PDF. Default: false.

`pdf-engine`
: string, one of `latex`, `xelatex`, `lualatex`.
  Which engine to use when converting LaTeX to `dvi` or `pdf`.
  Defaults to `latex`.

  Pandoc/Quarto filters cannot read which engine you specify to
  Pandoc, so if e.g. `xelatex` is needed you must specify this 
  option explicitly.

`svg-converter`
: string, DVI/PDF to SVG converter. Only `dvisvgm` available 
  for the moment.

<!-- not implemented yet
`template`
: string, Pandoc template for 
-->

#### SVG image

`zoom`
: number, zoom to apply when converting the DVI/PDF output
  to SVG image. Defaults to `1.5`.

#### HTML specific

`embed`
: boolean. In HTML output, embed the images within the file itself
  using [data URLs](https://developer.mozilla.org/en-US/docs/Web/HTTP/Basics_of_HTTP/Data_URLs). Default: false.

`vertical-align`
: string, CSS vertical align property for the generated image elements. 
  See [CSS reference](https://developer.mozilla.org/en-US/docs/Web/CSS/vertical-align) for details. Defaults to 
  `baseline`.

`block-style`
: string, CSS style applied to images generated from Display Math elements
  and LaTeX RawBlock elements. Defaults to 
  `display:block; margin: .5em auto;`.

#### header-includes

Specified at the metadata root, within the `imagify`
key, within a key of the `imagify-class` map, or on
as attributes of an imagify class Div elements.

As the document `header-includes` is often used to include 
LaTeX packages, the filter's default behaviour is to
picks it up and insert it in the `.tex` files used to
generate images. You can override that by specifying
a custom or empty `header-includes` in the imagify 
key:

``` yaml
header-includes: |
  This content only goes in the document's header.
imagify:
  header-includes: |
    This content is used in imagify's .tex files.
```

An empty line ensures no header content is included:

``` yaml
header-includes: |
  This content only goes in the document's header.
imagify:
  header-includes: 
```

Different header-includes can be specified for each
imagify class or even on a Div attributes.

#### Pandoc's LaTeX options

Specified at the metadata root, within the `imagify`
key, within a key of the `imagify-class` map, or on
as attributes of an imagify class Div elements.

The following Pandoc LaTeX output options are read: 

- `classoption` (for the `standalone` class)
- `mathspec`,
- `fontenc`,
- `fontfamily`,
- `fontfamilyoptions`,
- `fontsize`
- `mainfont`, `sansfont`, `monofont`, `mathfont`, `CJKmainfont`,
- `mainfontoptions`, `sansfontoptions`, `monofontoptions`, 
  `mathfontoptions`, `CJKoptions`,
- `microtypeoptions`,
- `colorlinks`,
- `boxlinks`,
- `linkcolor`, `filecolor`, `citecolor`, `urlcolor`, `toccolor`,
- `urlstyle`.

See [Pandoc manual][PManTeX] for details. 

These are passed to the default Pandoc template 
that is used to create. The document class is set
to `standalone`.


[Pandoc]: https://www.pandoc.org
[Pandoc-crossref]: https://github.com/lierdakil/pandoc-crossref
[Quarto]: https://quarto.org/
[DvisvgmMan]: https://dvisvgm.de/Manpage/
[Standalone]: https://ctan.org/pkg/standalone
[PManTeX]: https://pandoc.org/MANUAL.html#variables-for-latex
