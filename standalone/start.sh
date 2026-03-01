#!/bin/bash
# ============================================================
# Hytale F2P Dedicated Server Startup Script (v2.0)
# ============================================================
# Place in same directory as HytaleServer.jar and Assets.zip
# Usage: ./start.sh [additional server args...]
#
# Required files in same directory:
#   - HytaleServer.jar
#   - Assets.zip
#
# The script will automatically download dualauth-agent.jar
# from GitHub if not present.
# ============================================================

set -e

# Configuration (edit these or set as environment variables)
HYTALE_AUTH_DOMAIN="${HYTALE_AUTH_DOMAIN:-auth.sanasol.ws}"
AUTH_SERVER="${AUTH_SERVER:-https://$HYTALE_AUTH_DOMAIN}"
SERVER_NAME="${SERVER_NAME:-My Hytale Server}"
ASSETS_PATH="${ASSETS_PATH:-./Assets.zip}"
BIND_ADDRESS="${BIND_ADDRESS:-0.0.0.0:5520}"
AUTH_MODE="${AUTH_MODE:-authenticated}"

# DualAuth Agent configuration
AGENT_JAR="dualauth-agent.jar"
AGENT_VERSION_FILE="dualauth-agent.version"
AGENT_URL="https://github.com/sanasol/hytale-auth-server/releases/latest/download/dualauth-agent.jar"
AGENT_VERSION_API="https://api.github.com/repos/sanasol/hytale-auth-server/releases/latest"

echo "============================================================"
echo "  Hytale F2P Dedicated Server"
echo "============================================================"
echo ""

# Check for required tools
if ! command -v curl &>/dev/null; then
    echo "[ERROR] curl is required but not found"
    exit 1
fi

if ! command -v java &>/dev/null; then
    echo "[ERROR] java is required but not installed"
    echo "[ERROR] Install Java 21+: sudo apt install openjdk-21-jre"
    exit 1
fi

# Check for required files
if [ ! -f "HytaleServer.jar" ]; then
    echo "[ERROR] HytaleServer.jar not found in current directory"
    echo "[ERROR] Please run this script from the directory containing HytaleServer.jar"
    exit 1
fi

if [ ! -f "$ASSETS_PATH" ]; then
    echo "[ERROR] Assets.zip not found at: $ASSETS_PATH"
    echo "[ERROR] Please ensure Assets.zip is in the current directory or set ASSETS_PATH"
    exit 1
fi

# Check for agent updates or download if missing
NEEDS_DOWNLOAD=false
LOCAL_VERSION=""
if [ -f "$AGENT_JAR" ]; then
    AGENT_SIZE=$(stat -c%s "$AGENT_JAR" 2>/dev/null || stat -f%z "$AGENT_JAR" 2>/dev/null || echo 0)
    if [ "$AGENT_SIZE" -lt 10000 ]; then
        echo "[WARN] Agent JAR seems too small (${AGENT_SIZE} bytes), re-downloading..."
        rm -f "$AGENT_JAR"
        NEEDS_DOWNLOAD=true
    else
        [ -f "$AGENT_VERSION_FILE" ] && LOCAL_VERSION=$(cat "$AGENT_VERSION_FILE")
        # Check for updates
        echo "[INFO] Checking for agent updates..."
        REMOTE_VERSION=$(curl -sf "$AGENT_VERSION_API" --connect-timeout 5 --max-time 10 2>/dev/null | grep -o '"tag_name":"[^"]*"' | cut -d'"' -f4)
        if [ -n "$REMOTE_VERSION" ]; then
            if [ "$LOCAL_VERSION" = "$REMOTE_VERSION" ]; then
                echo "[INFO] DualAuth Agent up to date ($LOCAL_VERSION)"
            else
                echo "[INFO] Agent update available: ${LOCAL_VERSION:-unknown} -> $REMOTE_VERSION"
                NEEDS_DOWNLOAD=true
            fi
        else
            echo "[INFO] Could not check for updates, using existing agent (${LOCAL_VERSION:-unknown version})"
        fi
    fi
else
    NEEDS_DOWNLOAD=true
fi

if [ "$NEEDS_DOWNLOAD" = true ]; then
    ACTION="Downloading"
    [ -f "$AGENT_JAR" ] && ACTION="Updating"
    echo "[INFO] ${ACTION} DualAuth Agent..."
    echo "[INFO]   URL: $AGENT_URL"
    curl -L -o "${AGENT_JAR}.tmp" "$AGENT_URL" --connect-timeout 15 --max-time 120
    if [ $? -ne 0 ] || [ ! -f "${AGENT_JAR}.tmp" ]; then
        echo "[ERROR] Failed to download DualAuth Agent"
        rm -f "${AGENT_JAR}.tmp"
        if [ -f "$AGENT_JAR" ]; then
            echo "[INFO] Using existing agent despite update failure"
        else
            echo "[ERROR] Please download manually from: $AGENT_URL"
            exit 1
        fi
    else
        mv -f "${AGENT_JAR}.tmp" "$AGENT_JAR"
        [ -n "$REMOTE_VERSION" ] && echo "$REMOTE_VERSION" > "$AGENT_VERSION_FILE"
        echo "[INFO] DualAuth Agent ${ACTION,,} successfully (${REMOTE_VERSION:-latest})"
    fi
else
    echo "[INFO] DualAuth Agent found: $AGENT_JAR"
fi

# Generate or load server ID
SERVER_ID_FILE=".server-id"
if [ -f "$SERVER_ID_FILE" ]; then
    SERVER_ID=$(cat "$SERVER_ID_FILE")
    echo "[INFO] Using existing server ID: $SERVER_ID"
else
    SERVER_ID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen 2>/dev/null || python3 -c "import uuid; print(uuid.uuid4())" 2>/dev/null)
    echo "$SERVER_ID" > "$SERVER_ID_FILE"
    echo "[INFO] Generated new server ID: $SERVER_ID"
fi

# Fetch server tokens
echo ""
echo "[INFO] Fetching server tokens from $AUTH_SERVER..."
echo "[INFO]   Server ID: $SERVER_ID"
echo "[INFO]   Server Name: $SERVER_NAME"

TEMP_RESPONSE=$(mktemp)

curl -s -X POST "$AUTH_SERVER/server/auto-auth" \
    -H "Content-Type: application/json" \
    -d "{\"server_id\": \"$SERVER_ID\", \"server_name\": \"$SERVER_NAME\"}" \
    --connect-timeout 10 \
    --max-time 30 \
    -o "$TEMP_RESPONSE"

if [ $? -ne 0 ]; then
    echo "[ERROR] Failed to connect to auth server at $AUTH_SERVER"
    rm -f "$TEMP_RESPONSE"
    exit 1
fi

# Check for valid response
if ! grep -q "sessionToken" "$TEMP_RESPONSE" 2>/dev/null; then
    echo "[ERROR] Invalid response from auth server:"
    cat "$TEMP_RESPONSE"
    rm -f "$TEMP_RESPONSE"
    exit 1
fi

# Extract tokens
if command -v python3 &>/dev/null; then
    SESSION_TOKEN=$(python3 -c "import json,sys; print(json.load(open('$TEMP_RESPONSE'))['sessionToken'])")
    IDENTITY_TOKEN=$(python3 -c "import json,sys; print(json.load(open('$TEMP_RESPONSE'))['identityToken'])")
elif command -v jq &>/dev/null; then
    SESSION_TOKEN=$(jq -r '.sessionToken' "$TEMP_RESPONSE")
    IDENTITY_TOKEN=$(jq -r '.identityToken' "$TEMP_RESPONSE")
else
    # Fallback: simple grep extraction
    SESSION_TOKEN=$(grep -o '"sessionToken":"[^"]*"' "$TEMP_RESPONSE" | cut -d'"' -f4)
    IDENTITY_TOKEN=$(grep -o '"identityToken":"[^"]*"' "$TEMP_RESPONSE" | cut -d'"' -f4)
fi

rm -f "$TEMP_RESPONSE"

if [ -z "$SESSION_TOKEN" ]; then
    echo "[ERROR] Could not extract session token from response"
    exit 1
fi

if [ -z "$IDENTITY_TOKEN" ]; then
    echo "[ERROR] Could not extract identity token from response"
    exit 1
fi

echo "[INFO] Successfully fetched server tokens"

# Build JVM arguments
JAVA_ARGS=""
[ -n "$JVM_XMS" ] && JAVA_ARGS="$JAVA_ARGS -Xms$JVM_XMS"
[ -n "$JVM_XMX" ] && JAVA_ARGS="$JAVA_ARGS -Xmx$JVM_XMX"

echo ""
echo "[INFO] Starting Hytale Server..."
echo "[INFO]   Agent: $AGENT_JAR"
echo "[INFO]   Assets: $ASSETS_PATH"
echo "[INFO]   Bind: $BIND_ADDRESS"
echo "[INFO]   Auth mode: $AUTH_MODE"
echo ""

# Start the server with DualAuth Agent
exec java $JAVA_ARGS -javaagent:"$AGENT_JAR" -jar HytaleServer.jar \
    --assets "$ASSETS_PATH" \
    --bind "$BIND_ADDRESS" \
    --auth-mode "$AUTH_MODE" \
    --session-token "$SESSION_TOKEN" \
    --identity-token "$IDENTITY_TOKEN" \
    "$@"
