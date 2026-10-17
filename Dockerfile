# ghcr.io/vishisht16/syg: the release binary, alone, on an empty image. Built by
# the release workflow from the archives it publishes (image/linux/ARCH/syg),
# with the runner's CA bundle (image/ca-certificates.crt) for HTTPS.
#
#   docker run --rm -v "$PWD:/src" -w /src ghcr.io/vishisht16/syg:1 check
FROM scratch
ARG TARGETARCH
COPY image/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
COPY image/linux/${TARGETARCH}/syg /usr/local/bin/syg
# A container is usually a CI job: no installation ID is kept, and the image
# has nowhere to keep one. Usage statistics follow the same rules as anywhere
# else; SYG_TELEMETRY=off turns them off.
ENV SYG_CONFIG_DIR=/tmp/syg
WORKDIR /src
ENTRYPOINT ["/usr/local/bin/syg"]
CMD ["help"]
