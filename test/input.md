---
title: "Imagify Example"
## For LaTeX/PDF output unimagified bits require TikZ and fitch.sty
header-includes: |
  ```{=latex}
  \usepackage{tikz}
  \usepackage{test/fitch}
  ```
---

Imagify the following span: [the formula $E = mc^2$]{.imagify}. 

::: imagify

For some inline formulas, such as $x=\frac{-b\pm\sqrt[]{b^2-4ac}}{2a}$, the default `baseline`
vertical alignment is not ideal. You can adjust it manually, using a negative
value to lower the image below the baseline: 
[$x=\frac{-b\pm\sqrt[]{b^2-4ac}}{2a}$]{.imagify vertical-align="-.5em"}. In this case,
 I've specified a `-0.5em` value, which is about half a baseline down. 

:::

To check that the filter processes elements of arbitrary depth, we've 
placed the next bit within a dummy Div block. 

:::: arbitraryDiv

The display formula below is not explicitly marked to be imagified. 
However, it will be imagified in the filter's `scope` option is set
to `all`:
$$P = \frac{T}{V}$$

::: {.highlightme zoom='1'}

This next formula is imagified with options provided for elements
of a custom class, `highlightme`: 
$$P = \frac{T}{V}$$.
They display the formula as an inline instead of a block and
add a red border. They also specify a large zoom (4) but we've
overridden it and locally specified a zoom of 1.

:::

The filter automatically recognize TikZ pictures and loads the TikZ package
with the `tikz` option for the `standalone`. When `dvisvgm` is used for 
conversion to SVG, the required `dvisvgm` option is set too:

\usetikzlibrary{intersections}
\begin{tikzpicture}[scale=3,line cap=round,
% Styles
axes/.style=,
important line/.style={very thick}]

% Colors
  \colorlet{anglecolor}{green!50!black}
  \colorlet{sincolor}{red}
  \colorlet{tancolor}{orange!80!black}
  \colorlet{coscolor}{blue}

% The graphic
\draw[help lines,step=0.5cm] (-1.4,-1.4) grid (1.4,1.4);
\draw (0,0) circle [radius=1cm];
\begin{scope}[axes]
  \draw[->] (-1.5,0) -- (1.5,0) node[right] {$x$} coordinate(x axis);
  \draw[->] (0,-1.5) -- (0,1.5) node[above] {$y$} coordinate(y axis);
  \foreach \x/\xtext in {-1, -.5/-\frac{1}{2}, 1}
    \draw[xshift=\x cm] (0pt,1pt) -- (0pt,-1pt) node[below,fill=white] {$\xtext$};
  \foreach \y/\ytext in {-1, -.5/-\frac{1}{2}, .5/\frac{1}{2}, 1}
    \draw[yshift=\y cm] (1pt,0pt) -- (-1pt,0pt) node[left,fill=white] {$\ytext$};
\end{scope}

\filldraw[fill=green!20,draw=anglecolor] (0,0) -- (3mm,0pt) arc [start angle=0, end angle=30, radius=3mm];
\draw (15:2mm) node[anglecolor] {$\alpha$};
\draw[important line,sincolor] (30:1cm) -- node[left=1pt,fill=white] {$\sin \alpha$} (30:1cm |- x axis); \draw[important line,coscolor] (30:1cm |- x axis) -- node[below=2pt,fill=white] {$\cos \alpha$} (0,0);

\path [name path=upward line] (1,0) -- (1,1);
\path [name path=sloped line] (0,0) -- (30:1.5cm);

\draw [name intersections={of=upward line and sloped line, by=t}] [very thick,orange] (1,0) -- node [right=1pt,fill=white] {$\displaystyle \tan \alpha \color{black}=\frac{{\color{red}\sin \alpha}}{\color{blue}\cos \alpha}$} (t);
\draw (0,0) -- (t);
\end{tikzpicture}

::::

We can also use separate `.tex` and `.tikz` files as sources for images. The 
filter converts them to PDF (for LaTeX/PDF output) or SVG as required. 
That is useful to create cross-referencable figures 
with Pandoc-Crossref and Quarto.  

![Figure 1 is a separate tikz file](figure1.tikz)

![Figure 2 is a separate tex file](figure2.tex)

Currently, these should not contain a LaTeX preamble or `\begin{document}`.
There is no difference between `.tikz` and `.tex` sources here. A TikZ 
picture in a `.tikz` file should still have `\begin{tikzpicture}` or `\tikz` commands.

::: {.fitch}

We can also use LaTeX packages that are provided in the document's folder, 
here `fitch.sty` (a package not available on CTAN):

$$\begin{nd}
  \hypo[~] {1} {A \lor B}
  \open
  \hypo[~] {2} {A}
  \have[~] {3} {C} 
  \close
  \open
  \hypo[~] {4} {B}
  \have[~] {5} {D}
  \close
  \have[~] {6} {C \lor D}
\end{nd}$$

:::
