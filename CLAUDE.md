# Hytale Server Docker

Fork used for distribution. Downloads DualAuth ByteBuddy Agent from `hytale-auth-server` GitHub releases at build time.

## DualAuth ByteBuddy Agent

Runtime class transformation — original `HytaleServer.jar` stays pristine (no JAR modification).

**Two deployment modes:**
- **Agent mode** (recommended): `-javaagent:dualauth-agent.jar` JVM flag, loads before server
- **Plugin mode**: Drop JAR into `mods/` folder, uses dynamic attach after server starts (for hosts that block startup args)

**Paths:**
- Docker image: `/opt/dualauth-agent/dualauth-agent.jar`
- Runtime fallback: downloads from GitHub releases to `${SERVER_DIR}/dualauth-agent.jar`

**Startup commands:**
```bash
# Agent mode
java -javaagent:dualauth-agent.jar -jar HytaleServer.jar

# Plugin mode (JAR in mods/)
java -XX:+EnableDynamicAgentLoading -jar HytaleServer.jar
```

## Dual Auth Architecture
- Agent intercepts JWTValidator at class load time via ByteBuddy
- Accepts tokens from both `hytale.com` (official) and F2P domain
- Supports Omni-Auth (embedded JWK in tokens) and federated JWKS discovery
- ThreadLocal context management with connection boundary resets

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `HYTALE_DUAL_AUTH` | `true` | Enable dual auth agent |
| `HYTALE_AUTH_DOMAIN` | `auth.sanasol.ws` | F2P domain (4-16 chars) |
| `HYTALE_AUTO_FETCH_TOKENS` | `true` | Auto-fetch F2P tokens on startup |
| `HYTALE_SERVER_NAME` | `Hytale Server` | Server name for token requests |
| `HYTALE_TRUST_ALL_ISSUERS` | `true` | Trust any issuer with valid JWKS |
| `HYTALE_TRUST_OFFICIAL` | `true` | Trust official hytale.com tokens |
| `HYTALE_TRUSTED_ISSUERS` | `` | Comma-separated trusted issuer URLs |
| `HYTALE_ISSUER_BLACKLIST` | `` | Comma-separated blocked issuers |
| `HYTALE_KEYS_CACHE_TTL` | `3600` | JWKS cache TTL in seconds |
| `DUALAUTH_LOGGING_ENABLED` | `false` | Enable agent debug logging |

## Pterodactyl Eggs (Self-Hosting)

Located in `pterodactyl/`:
- `egg-hytale-server.json` — F2P server egg (ByteBuddy agent, auto-update, DualAuth)
- `egg-hytale-server-official.json` — Official licensed server egg
- `README.md` — Egg installation guide

These are **public self-hosting eggs** for users running their own Pterodactyl panels.
The private free-hosting egg is in the `hytale-free-hosting` repo.

## Standalone Scripts

Located in `standalone/`:
- `start.sh` — Linux/macOS standalone server start script with auto-update
- `start.bat` — Windows standalone server start script with auto-update

For users running servers without Docker or Pterodactyl.

## GitHub Repository
https://github.com/sanasol/hytale-server-docker
