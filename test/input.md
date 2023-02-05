---
title: "Imagify Example"
imagify:
  scope: all
  output-folder: tex2img
  classes: 
    pre-render:
        zoom: 2
        block-style: "border: 1px solid red;"
  zoom: 1.5
---

Imagify the following span: [the formula $E = mc^2$]{.imagify}. 

:::: imagify

Test this one: $$P = \frac{T}{V}$$

::: {.pre-render zoom='4'}

Imagify the following too $$P = \frac{T}{V}$$

:::

::::

