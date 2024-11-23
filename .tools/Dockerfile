FROM pandoc/latex:latest

# Currently pandoc uses TexLive 2022, need to point there
RUN tlmgr option repository https://ftp.tu-chemnitz.de/pub/tug/historic/systems/texlive/2024/tlnet-final \
    && tlmgr install \
    standalone \
    dvisvgm
ENTRYPOINT [ "/usr/local/bin/pandoc" ]