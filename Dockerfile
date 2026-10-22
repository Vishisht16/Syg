# ghcr.io/vishisht16/syg: the release binary, alone, on an empty image. Built by
# the release workflow from the archives it publishes (image/linux/ARCH/syg,
# and image/doc: the EULA, the privacy statement and the third-party notices),
# with the runner's CA bundle (image/ca-certificates.crt) and its notice, for
# HTTPS (.github/actions/image). It runs as a user of its own, not root, and
# needs no capabilities and no writable file system; to write into a mounted
# directory, run it as the directory's owner:
#
#   docker run --rm -v "$PWD:/src:ro" ghcr.io/vishisht16/syg:1 check
#   docker run --rm --user "$(id -u):$(id -g)" -v "$PWD:/src" ghcr.io/vishisht16/syg:1 build -o out
FROM scratch
ARG TARGETARCH
COPY image/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
COPY image/ca-certificates.copyright /usr/share/doc/ca-certificates/copyright
COPY image/doc/ /usr/share/doc/syg/
COPY image/linux/${TARGETARCH}/syg /usr/local/bin/syg
# A container is usually a CI job: no installation ID is kept, and the image
# has nowhere to keep one. Usage statistics follow the same rules as anywhere
# else; SYG_TELEMETRY=off turns them off.
ENV SYG_CONFIG_DIR=/tmp/syg
USER 65532:65532
WORKDIR /src
ENTRYPOINT ["/usr/local/bin/syg"]
CMD ["help"]
