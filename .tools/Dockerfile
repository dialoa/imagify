FROM pandoc/latex:latest
RUN tlmgr install \
    standalone \
    dvisvgm
ENTRYPOINT [ "/usr/local/bin/pandoc" ]