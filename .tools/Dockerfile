FROM pandoc/latex:latest

# If pandoc/latex uses an older TeXLive, this needs to be changed
RUN tlmgr option repository https://mirror.ctan.org/systems/texlive/tlnet \
    && tlmgr install \
    standalone \
    dvisvgm

ENTRYPOINT [ "/usr/local/bin/pandoc" ]