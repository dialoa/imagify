FROM pandoc/latex:latest
RUN update-tlmgr-latest --update && \
    tlmgr install \
    standalone \
    dvisvgm
ENTRYPOINT [ "/usr/local/bin/pandoc" ]