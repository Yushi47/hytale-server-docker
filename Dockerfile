# Download DualAuth ByteBuddy Agent from GitHub releases
FROM eclipse-temurin:25-jdk AS agent-downloader

RUN apt-get update && apt-get install -y --no-install-recommends curl ca-certificates \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /build
ARG DUALAUTH_AGENT_URL=https://github.com/sanasol/hytale-auth-server/releases/latest/download/dualauth-agent.jar
RUN curl -sfL "${DUALAUTH_AGENT_URL}" -o dualauth-agent.jar \
  && java -jar dualauth-agent.jar --version

# Runtime stage
FROM eclipse-temurin:25-jre

RUN apt-get update \
  && apt-get install -y --no-install-recommends tini ca-certificates curl unzip zip perl jq \
  && rm -rf /var/lib/apt/lists/*

RUN groupadd -f hytale \
  && if ! id -u hytale >/dev/null 2>&1; then useradd -m -u 1000 -o -g hytale -s /usr/sbin/nologin hytale; fi \
  && touch /etc/machine-id \
  && chown hytale:hytale /etc/machine-id

RUN mkdir -p /data \
  && chown -R hytale:hytale /data

VOLUME ["/data"]
WORKDIR /data

COPY scripts/entrypoint.sh /usr/local/bin/hytale-entrypoint
COPY scripts/cfg-interpolate.sh /usr/local/bin/hytale-cfg-interpolate
COPY scripts/auto-download.sh /usr/local/bin/hytale-auto-download
COPY scripts/f2p-download.sh /usr/local/bin/hytale-f2p-download
COPY scripts/curseforge-mods.sh /usr/local/bin/hytale-curseforge-mods
COPY scripts/prestart-downloads.sh /usr/local/bin/hytale-prestart-downloads
COPY scripts/hytale-cli.sh /usr/local/bin/hytale-cli
COPY scripts/healthcheck.sh /usr/local/bin/hytale-healthcheck
RUN chmod 0755 /usr/local/bin/hytale-entrypoint /usr/local/bin/hytale-cfg-interpolate /usr/local/bin/hytale-auto-download /usr/local/bin/hytale-f2p-download /usr/local/bin/hytale-curseforge-mods /usr/local/bin/hytale-prestart-downloads /usr/local/bin/hytale-cli /usr/local/bin/hytale-healthcheck

# Install DualAuth ByteBuddy Agent (runtime patching, no JAR modification)
COPY --from=agent-downloader /build/dualauth-agent.jar /opt/dualauth-agent/dualauth-agent.jar

USER hytale

HEALTHCHECK --interval=30s --timeout=5s --start-period=10m --retries=3 CMD ["/usr/local/bin/hytale-healthcheck"]

ENTRYPOINT ["/usr/bin/tini","--","/usr/local/bin/hytale-entrypoint"]
