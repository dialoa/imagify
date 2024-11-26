Imagify - Pandoc/Quarto filter to convert selected LaTeX into images
====================================================================

[![GitHub build status][CI badge]][CI workflow]

[CI badge]: https://img.shields.io/github/actions/workflow/status/dialoa/imagify/ci.yaml?branch=main
[CI workflow]: https://github.com/dialoa/imagify/actions/workflows/ci.yaml

Lua filter to convert some or all LaTeX and TikZ elements in a document into 
images. Also enables using `.tex`/`.tikz` files as image sources. 

Copyright 2021-2023 [Philosophie.ch][Philoch] under MIT License, see
LICENSE file for details.

Maintained by [Julien Dutant][JDutant].

Overview
--------------------------------------------------------------------

Imagify turns selected LaTeX elements into images in non-LaTeX/PDF
output. This is useful for web output if you use MathJAX but it 
doesn't handle all of your LaTeX code.

It also allows you to use `.tex` or `.tikz` elements as
image source files, which is useful to create cross-referenceable
figures with [Pandoc-crossref][] or [Quarto][] without having
to convert your LaTeX/TikZ code into images first.

Imagify tries to match your document's LaTeX output settings 
(fonts, LaTeX packages, etc.). Its rendering options are otherwise 
extensively configurable, and different rendering options can 
be used for different elements. It can embed its images within HTML 
output or provide them as separate image files. 

Requirements: [Pandoc][] or [Quarto][], a LaTeX installation 
(with `dvisvgm` and, recommended, `latexmk`, which are included
in common LaTeX distributions).

Limitations
------------------------------------------------------------------

* So far designed with HTML output in mind, LaTeX to SVG conversion,
  and LaTeX/PDF outputs with separate `.tikz` or `.tex` files as
  image sources. 
  In other output formats, the images will be inserted or linked as PDFs
  and may display in wrong sizes or not at all. 
* Embedding within HTML output isn't compatible with Pandoc's 
  `extract-media` option.

Use cases
------------------------------------------------------------------

The filter is used to produce the academic journal [Dialectica][].
See for instance [this 
article](https://dialectica.philosophie.ch/dialectica/article/download/20/66).

Demonstration
------------------------------------------------------------------

See the manual's [example HTML output][ImagifyExample].

For a quick try-out, clone the repository and try:

Pandoc
: make generate && open example-pandoc/expected.html

Or:

Quarto
: make quarto && open example-quarto/example.html

You'll need either [Pandoc][] or [Quarto][] and a 
standard LaTeX distribution (that includes [dvisvgm][DvisvgmCTAN]).

Installation and usage
------------------------------------------------------------------

See the [manual][ImagifyManual].

CI Tests
--------

CI tests run on the
[pandoc/latex][https://hub.docker.com/r/pandoc/latex] Docker image.
The [Dockerfile](.tools/Dockerfile) installs two LaTeX packages not
included from the current TeXLive repository at
[https://mirror.ctan.org/systems/texlive/tlnet](CTAN). If the pandoc/latex Docker
image is not yet updated to the latest TeXLive version, the Dockerfile should point to a suitable TexLive repository archive.

Issues and contributing
------------------------------------------------------------------

Issues and PRs welcome.

Acknowledgements
------------------------------------------------------------------

Development funded by [Philosophie.ch][Philoch].

[ImagifyManual]: https://dialoa.github.io/imagify/
[ImagifyExample]: https://dialoa.github.io/imagify/output.html
[Dialectica]: https://dialectica.philosophie.ch
[Philoch]: https://philosophie.ch
[JDutant]: https://github.com/jdutant
[Pandoc]: https://www.pandoc.org
[Pandoc-crossref]: https://github.com/lierdakil/pandoc-crossref
[Quarto]: https://quarto.org/
[QuartoDivFigure]: https://quarto.org/docs/authoring/cross-references-divs.html
[DvisvgmCTAN]: https://ctan.org/pkg/dvisvgm

