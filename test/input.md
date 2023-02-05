---
title: "Imagify Example"
imagify:
  scope: all
  output-folder: tex2img
  pdf-engine: latex
  keep-sources: false
  classes: 
    pre-render:
        zoom: 4 # will show if it's not overriden
        block-style: "border: 1px solid red;"
  zoom: 1.5
---

Imagify the following span: [the formula $E = mc^2$]{.imagify}. 

:::: imagify

Imagify a display formula: $$P = \frac{T}{V}$$

::: {.pre-render zoom='1'}

Imagify the following too, with a class-selected block style (red border,
inline) and a locally specified zoom of 1. $$P = \frac{T}{V}$$

:::

The filter automatically recognize TikZ pictures and loads the TikZ package
with the `tikz` option for the `standalone`. When `dvisvgm` is used for 
conversion to SVG, the required `dvisvgm` option is set too:

\begin{tikzpicture}
  \draw (-1.5,0) -- (1.5,0);
  \draw (0,-1.5) -- (0,1.5);
\end{tikzpicture}.

::::
