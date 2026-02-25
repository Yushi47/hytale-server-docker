# Hytale Server Docker

**Production-ready Docker image for Hytale game servers with automatic download.**

No official Hytale authentication required - server files are downloaded automatically. Supports both F2P and official licensed clients.

[![Docker Image](https://img.shields.io/badge/ghcr.io-sanasol%2Fhytale--server--docker-blue)](https://ghcr.io/sanasol/hytale-server-docker)

[TG Group](https://t.me/sanhostnet) | [TG Channel](https://t.me/hf2p_og) | [Community Chat](https://chat.sanhost.net/invite/Tfz4jCK4)

---

## Quick Start (F2P Mode - Default)

**No setup required!** Server downloads automatically on first run.

### Using Pre-built Image

**One-liner:**
```bash
docker run -d -p 5520:5520/udp -v ./data:/data --name hytale ghcr.io/sanasol/hytale-server-docker:latest
```

**Or with Docker Compose:**
```yaml
# compose.yaml
services:
  hytale:
    image: ghcr.io/sanasol/hytale-server-docker:latest
    ports:
      - "5520:5520/udp"
    volumes:
      - ./data:/data
    tty: true
    stdin_open: true
    restart: unless-stopped
```

```bash
docker compose up -d
```

First run will automatically download:
- `HytaleServer.jar` (~80MB)
- `Assets.zip` (~3.3GB)

### Build from Source

```bash
git clone https://github.com/sanasol/hytale-server-docker.git
cd hytale-server-docker
docker compose up -d
```

---

## Download Modes

### F2P Download (Default)

Downloads pre-patched server from F2P host. **No authentication required.**

```yaml
environment:
  HYTALE_F2P_DOWNLOAD: "true"  # Default
  HYTALE_F2P_DOWNLOAD_BASE: "https://download.sanasol.ws/download"
```

### Official Hytale Download

Downloads from official Hytale servers. **Requires device code authentication.**

```yaml
environment:
  HYTALE_F2P_DOWNLOAD: "false"
  HYTALE_AUTO_DOWNLOAD: "true"
```

On first run, check logs for device code authentication URL.

---

## Configuration

### Essential Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `HYTALE_F2P_DOWNLOAD` | `true` | Enable F2P download (no auth required) |
| `HYTALE_AUTO_DOWNLOAD` | `false` | Enable official Hytale download (requires auth) |
| `HYTALE_AUTH_DOMAIN` | `auth.sanasol.ws` | F2P auth server domain |
| `HYTALE_AUTH_MODE` | `authenticated` | Server auth mode |
| `HYTALE_DUAL_AUTH` | `true` | Enable dual auth (official + F2P clients) |

### Omni-Auth (Decentralized) Options

| Variable | Default | Description |
|----------|---------|-------------|
| `HYTALE_TRUST_ALL_ISSUERS` | `true` | Accept tokens from any issuer with embedded JWK |
| `HYTALE_TRUSTED_ISSUERS` | *(empty)* | Comma-separated allowlist when TRUST_ALL=false |

See [Omni-Auth Documentation](https://github.com/sanasol/hytale-auth-server/blob/master/patcher/OMNI_AUTH.md) for implementation details.

### F2P Download Options

| Variable | Default | Description |
|----------|---------|-------------|
| `HYTALE_F2P_DOWNLOAD_BASE` | `https://download.sanasol.ws/download` | Base URL for downloads |
| `HYTALE_F2P_AUTO_UPDATE` | `true` | Check for updates on restart (compares remote ETag) |

### Server Options

| Variable | Default | Description |
|----------|---------|-------------|
| `HYTALE_BIND` | `0.0.0.0:5520` | Server bind address |
| `JVM_XMS` | - | JVM min heap (e.g., `2G`) |
| `JVM_XMX` | - | JVM max heap (e.g., `4G`) |

### Full Configuration Example

```yaml
services:
  hytale:
    image: ghcr.io/sanasol/hytale-server-docker:latest
    environment:
      # Download mode (F2P = default)
      HYTALE_F2P_DOWNLOAD: "true"

      # Auth configuration
      HYTALE_AUTH_DOMAIN: "auth.sanasol.ws"
      HYTALE_AUTH_MODE: "authenticated"
      HYTALE_DUAL_AUTH: "true"

      # Server settings
      HYTALE_ACCEPT_EARLY_PLUGINS: "true"

      # JVM memory
      JVM_XMS: "2G"
      JVM_XMX: "4G"
    ports:
      - "5520:5520/udp"
    volumes:
      - ./data:/data
      - ./backups:/backups
    tty: true
    stdin_open: true
    restart: unless-stopped
```

---

## Dual Authentication

By default, servers support **both** official Hytale clients and F2P clients simultaneously.

### F2P Clients
Connect directly using [Hytale F2P Launcher](https://github.com/amiayweb/Hytale-F2P) - no additional setup needed.

### Official/Licensed Clients

To allow players with official Hytale game licenses to connect, the **server admin** must run these commands in the **server console**:

```
/auth logout
/auth persistence Encrypted
/auth login device
```

Then complete the Hytale authentication process in your browser. This gives the server official Hytale tokens so it can authenticate licensed clients.

> **Note**: This only needs to be done once per server. Tokens persist between restarts.

### How It Works

The server automatically:
1. Downloads pre-patched JAR with dual auth support (or patches on first run)
2. Auto-fetches F2P server tokens internally (no external scripts needed)
3. Merges JWKS from both official and F2P backends
4. Routes authentication based on token issuer

### Omni-Auth (Decentralized Clients)

The server also supports **Omni-Auth** - clients that generate their own self-signed tokens with embedded JWK keys. This enables fully decentralized authentication without any central server.

By default (`HYTALE_TRUST_ALL_ISSUERS=true`), any Omni-Auth client is accepted. For stricter control:

```yaml
environment:
  HYTALE_TRUST_ALL_ISSUERS: "false"
  HYTALE_TRUSTED_ISSUERS: "127.0.0.1,localhost,myauth.example.com"
```

See [Omni-Auth Documentation](https://github.com/sanasol/hytale-auth-server/blob/master/patcher/OMNI_AUTH.md) for implementation details.

---

## CurseForge Mods

Automatic mod management is supported:

```yaml
environment:
  HYTALE_CURSEFORGE_MODS: "MOD_ID1 MOD_ID2"
  HYTALE_CURSEFORGE_API_KEY: "$2a$10$..."
```

See [`docs/image/curseforge-mods.md`](docs/image/curseforge-mods.md) for details.

---

## Pterodactyl Panel

Pterodactyl eggs for running Hytale servers on game panels.

| Egg | Description | Auth Required |
|-----|-------------|---------------|
| [`egg-hytale-server.json`](pterodactyl/egg-hytale-server.json) | **Recommended** - Auto-downloads server | No |
| [`egg-hytale-server-official.json`](pterodactyl/egg-hytale-server-official.json) | Downloads from official Hytale | Yes (device code) |

**Quick setup:**
1. Import egg in Admin Panel → Nests → Import Egg
2. Create server with **UDP port** allocation (Hytale uses UDP)
3. Start server - files download automatically

See [`pterodactyl/README.md`](pterodactyl/README.md) for detailed documentation.

---

## Building & Publishing

### Local Build

```bash
# Build for local use
./build.sh

# Build and push to GHCR
./build.sh --push

# Build with specific tag
./build.sh --push --tag v1.0.0
```

### GitHub Actions

Images are automatically built and pushed on:
- Push to `main`/`master` branch
- Version tags (`v*`)
- Manual workflow dispatch

---

## Public Test Server

Test without setting up your own server:

1. Download [Hytale F2P Launcher](https://github.com/amiayweb/Hytale-F2P/releases/tag/v2.0.2b)
2. Connect to: `ht.vboro.de:5720`

Features:
- All cosmetics unlocked
- Cosmetics saved by username
- No password (anyone can use any username)

---

## Related Projects

| Project | Description |
|---------|-------------|
| [hytale-auth-server](https://github.com/sanasol/hytale-auth-server) | F2P Authentication server |
| [Hytale F2P Launcher](https://github.com/amiayweb/Hytale-F2P) | Game launcher with F2P support |
| [Server List](https://santale.top) | Hytale server listing |

---

## Troubleshooting

### Server won't start

```bash
# Check logs
docker compose logs -f hytale

# Verify files downloaded
ls -la data/
ls -la data/server/
```

### Download fails

1. Check internet connectivity
2. Verify download URL is accessible:
   ```bash
   curl -I https://download.sanasol.ws/download/HytaleServer.jar
   ```
3. Try forcing re-download:
   ```yaml
   environment:
     HYTALE_F2P_AUTO_UPDATE: "true"
   ```

### Dual auth not working

1. Check if JAR is patched:
   ```bash
   docker exec hytale unzip -l /data/server/HytaleServer.jar | grep DualAuthContext
   ```
2. Delete patch flag and restart:
   ```bash
   rm data/server/.patched_dual_auth
   docker compose restart
   ```

---

## Documentation

- [`pterodactyl/README.md`](pterodactyl/README.md) - Pterodactyl Panel setup
- [`docs/image/quickstart.md`](docs/image/quickstart.md) - Getting started with Docker
- [`docs/image/configuration.md`](docs/image/configuration.md) - All environment variables
- [`docs/image/curseforge-mods.md`](docs/image/curseforge-mods.md) - Mod management
- [`docs/image/troubleshooting.md`](docs/image/troubleshooting.md) - Common issues
- [`docs/image/server-files.md`](docs/image/server-files.md) - Manual file provisioning

---

## License

See [`LICENSE`](LICENSE).

---

## Credits

Based on [Hybrowse/hytale-server-docker](https://github.com/Hybrowse/hytale-server-docker).
