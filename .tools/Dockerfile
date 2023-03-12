FROM pandoc/latex:latest
RUN tlmgr install \
    standalone
ENTRYPOINT [ "/usr/local/bin/pandoc" ]