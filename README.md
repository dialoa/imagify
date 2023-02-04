Greetings, a Lua Filter Template
==================================================================

[![GitHub build status][CI badge]][CI workflow]

Greetings is a friendly Lua filter that adds a welcoming message
to the document.

[CI badge]: https://img.shields.io/github/workflow/status/dialoa/imagify/CI?logo=github
[CI workflow]: https://github.com/dialoa/imagify/actions/workflows/ci.yaml


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
