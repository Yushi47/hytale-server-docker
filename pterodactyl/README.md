# Pterodactyl Eggs for Hytale Server

Pterodactyl Panel eggs for running Hytale game servers.

**Note**: These eggs are also included in [hytale-server-docker](https://github.com/sanasol/hytale-server-docker/tree/main/pterodactyl).

## Available Eggs

| Egg | Description | Auth Required |
|-----|-------------|---------------|
| [`egg-hytale-server.json`](egg-hytale-server.json) | **Recommended** - Auto-downloads server | No |
| [`egg-hytale-server-official.json`](egg-hytale-server-official.json) | Downloads from official Hytale | Yes (device code) |

Both eggs support **F2P and official licensed clients** connecting to the same server.

## Quick Start

1. Import egg in Admin Panel → Nests → Import Egg
2. Create server with **UDP port** allocation
3. Start - files download automatically

## Connecting Clients

### F2P Clients
Connect directly using [Hytale F2P Launcher](https://github.com/amiayweb/Hytale-F2P).

### Official Clients
Server admin runs these commands in **server console**:
```
/auth logout
/auth persistence Encrypted
/auth login device
```
This gives the server Hytale tokens to authenticate licensed clients.

### Omni-Auth (Decentralized)
Clients with self-signed embedded JWK tokens are supported. Configure via:
- `HYTALE_TRUST_ALL_ISSUERS` - Accept any issuer (default: true)
- `HYTALE_TRUSTED_ISSUERS` - Comma-separated allowlist when TRUST_ALL=false

See [Omni-Auth Documentation](https://github.com/sanasol/hytale-auth-server/blob/master/patcher/OMNI_AUTH.md).

## Documentation

See [hytale-server-docker/pterodactyl/README.md](https://github.com/sanasol/hytale-server-docker/tree/main/pterodactyl) for full documentation.

## Support

- Telegram Group: https://t.me/sanhostnet
- Telegram Channel: https://t.me/hf2p_og
- Community Chat: https://chat.sanhost.net/invite/Tfz4jCK4
<!-- - Discord: https://discord.gg/gME8rUy3MB -->
- Issues: https://github.com/sanasol/hytale-server-docker/issues
