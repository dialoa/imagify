---
title: "Imagify Example"
---

Imagify the following span: [the formula $E = mc^2$]{.imagify}. 

:::: arbitraryDiv

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
