FROM pandoc/latex:latest

# Currently pandoc uses TexLive 2022, need to point there
RUN tlmg option repository https://ftp.math.utah.edu/pub/tex/historic/systems/texlive/2022/ \
    tlmgr install \
    standalone \
    dvisvgm
ENTRYPOINT [ "/usr/local/bin/pandoc" ]