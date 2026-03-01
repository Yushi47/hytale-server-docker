@echo off
setlocal enabledelayedexpansion

:: ============================================================
:: Hytale F2P Dedicated Server Startup Script (v2.0)
:: ============================================================
:: Place in same directory as HytaleServer.jar and Assets.zip
:: Usage: start.bat [additional server args...]
::
:: Required files in same directory:
::   - HytaleServer.jar
::   - Assets.zip
::
:: The script will automatically download dualauth-agent.jar
:: from GitHub if not present.
:: ============================================================

:: Configuration (edit these or set as environment variables)
if not defined HYTALE_AUTH_DOMAIN set "HYTALE_AUTH_DOMAIN=auth.sanasol.ws"
if not defined AUTH_SERVER set "AUTH_SERVER=https://%HYTALE_AUTH_DOMAIN%"
if not defined SERVER_NAME set "SERVER_NAME=My Hytale Server"
if not defined ASSETS_PATH set "ASSETS_PATH=.\Assets.zip"
if not defined BIND_ADDRESS set "BIND_ADDRESS=0.0.0.0:5520"
if not defined AUTH_MODE set "AUTH_MODE=authenticated"

:: DualAuth Agent configuration
set "AGENT_JAR=dualauth-agent.jar"
set "AGENT_VERSION_FILE=dualauth-agent.version"
set "AGENT_URL=https://github.com/sanasol/hytale-auth-server/releases/latest/download/dualauth-agent.jar"
set "AGENT_VERSION_API=https://api.github.com/repos/sanasol/hytale-auth-server/releases/latest"

echo ============================================================
echo   Hytale F2P Dedicated Server
echo ============================================================
echo.

:: Check for required tools
where curl >nul 2>&1
if errorlevel 1 (
    echo [ERROR] curl is required but not found
    echo [ERROR] Please ensure you have Windows 10 or later, or install curl
    pause
    exit /b 1
)

where java >nul 2>&1
if errorlevel 1 (
    echo [ERROR] java is required but not installed
    echo [ERROR] Download Java 21+ from https://adoptium.net/
    pause
    exit /b 1
)

:: Check for required files
if not exist "HytaleServer.jar" (
    echo [ERROR] HytaleServer.jar not found in current directory
    echo [ERROR] Please run this script from the directory containing HytaleServer.jar
    pause
    exit /b 1
)

if not exist "%ASSETS_PATH%" (
    echo [ERROR] Assets.zip not found at: %ASSETS_PATH%
    echo [ERROR] Please ensure Assets.zip is in the current directory or set ASSETS_PATH
    pause
    exit /b 1
)

:: Check for agent updates or download if missing
set "NEEDS_DOWNLOAD=0"
set "LOCAL_VERSION="
set "REMOTE_VERSION="
if exist "%AGENT_JAR%" (
    for %%A in ("%AGENT_JAR%") do set "AGENT_SIZE=%%~zA"
    if !AGENT_SIZE! LSS 10000 (
        echo [WARN] Agent JAR seems too small ^(!AGENT_SIZE! bytes^), re-downloading...
        del "%AGENT_JAR%" 2>nul
        set "NEEDS_DOWNLOAD=1"
    ) else (
        if exist "%AGENT_VERSION_FILE%" (
            set /p LOCAL_VERSION=<"%AGENT_VERSION_FILE%"
        )
        echo [INFO] Checking for agent updates...
        set "TEMP_VER=%TEMP%\agent_ver_%RANDOM%.json"
        curl -sf "%AGENT_VERSION_API%" --connect-timeout 5 --max-time 10 -o "!TEMP_VER!" 2>nul
        if exist "!TEMP_VER!" (
            for /f "delims=" %%i in ('powershell -Command "try { $j = Get-Content '!TEMP_VER!' | ConvertFrom-Json; $j.tag_name } catch { '' }" 2^>nul') do set "REMOTE_VERSION=%%i"
            del "!TEMP_VER!" 2>nul
        )
        if defined REMOTE_VERSION (
            if "!LOCAL_VERSION!"=="!REMOTE_VERSION!" (
                echo [INFO] DualAuth Agent up to date ^(!LOCAL_VERSION!^)
            ) else (
                echo [INFO] Agent update available: !LOCAL_VERSION! -^> !REMOTE_VERSION!
                set "NEEDS_DOWNLOAD=1"
            )
        ) else (
            echo [INFO] Could not check for updates, using existing agent
        )
    )
) else (
    set "NEEDS_DOWNLOAD=1"
)

if "!NEEDS_DOWNLOAD!"=="1" (
    set "ACTION=Downloading"
    if exist "%AGENT_JAR%" set "ACTION=Updating"
    echo [INFO] !ACTION! DualAuth Agent...
    echo [INFO]   URL: %AGENT_URL%
    curl -L -o "%AGENT_JAR%.tmp" "%AGENT_URL%" --connect-timeout 15 --max-time 120
    if errorlevel 1 (
        del "%AGENT_JAR%.tmp" 2>nul
        if exist "%AGENT_JAR%" (
            echo [INFO] Using existing agent despite update failure
        ) else (
            echo [ERROR] Failed to download DualAuth Agent
            echo [ERROR] Please download manually from: %AGENT_URL%
            pause
            exit /b 1
        )
    ) else (
        if exist "%AGENT_JAR%" del "%AGENT_JAR%"
        move /Y "%AGENT_JAR%.tmp" "%AGENT_JAR%" >nul
        if defined REMOTE_VERSION echo !REMOTE_VERSION!>"%AGENT_VERSION_FILE%"
        echo [INFO] DualAuth Agent !ACTION:~0,1!!ACTION:~1! successfully ^(!REMOTE_VERSION!^)
    )
) else (
    echo [INFO] DualAuth Agent found: %AGENT_JAR%
)

:: Generate or load server ID
set "SERVER_ID_FILE=.server-id"
if exist "%SERVER_ID_FILE%" (
    set /p SERVER_ID=<"%SERVER_ID_FILE%"
    echo [INFO] Using existing server ID: !SERVER_ID!
) else (
    for /f "delims=" %%i in ('powershell -Command "[guid]::NewGuid().ToString()"') do set "SERVER_ID=%%i"
    echo !SERVER_ID!>"%SERVER_ID_FILE%"
    echo [INFO] Generated new server ID: !SERVER_ID!
)

:: Fetch server tokens
echo.
echo [INFO] Fetching server tokens from %AUTH_SERVER%...
echo [INFO]   Server ID: !SERVER_ID!
echo [INFO]   Server Name: %SERVER_NAME%

set "TEMP_RESPONSE=%TEMP%\hytale_auth_response_%RANDOM%.json"

curl -s -X POST "%AUTH_SERVER%/server/auto-auth" ^
    -H "Content-Type: application/json" ^
    -d "{\"server_id\": \"!SERVER_ID!\", \"server_name\": \"%SERVER_NAME%\"}" ^
    --connect-timeout 10 ^
    --max-time 30 ^
    -o "%TEMP_RESPONSE%" 2>nul

if errorlevel 1 (
    echo [ERROR] Failed to connect to auth server at %AUTH_SERVER%
    del "%TEMP_RESPONSE%" 2>nul
    pause
    exit /b 1
)

:: Check for valid response
findstr /C:"sessionToken" "%TEMP_RESPONSE%" >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Invalid response from auth server:
    type "%TEMP_RESPONSE%"
    del "%TEMP_RESPONSE%" 2>nul
    pause
    exit /b 1
)

:: Extract tokens using PowerShell
for /f "delims=" %%i in ('powershell -Command "$json = Get-Content '%TEMP_RESPONSE%' | ConvertFrom-Json; $json.sessionToken"') do set "SESSION_TOKEN=%%i"
for /f "delims=" %%i in ('powershell -Command "$json = Get-Content '%TEMP_RESPONSE%' | ConvertFrom-Json; $json.identityToken"') do set "IDENTITY_TOKEN=%%i"

del "%TEMP_RESPONSE%" 2>nul

if "!SESSION_TOKEN!"=="" (
    echo [ERROR] Could not extract session token from response
    pause
    exit /b 1
)

if "!IDENTITY_TOKEN!"=="" (
    echo [ERROR] Could not extract identity token from response
    pause
    exit /b 1
)

echo [INFO] Successfully fetched server tokens

:: Build JVM arguments
set "JAVA_ARGS="
if defined JVM_XMS set "JAVA_ARGS=!JAVA_ARGS! -Xms%JVM_XMS%"
if defined JVM_XMX set "JAVA_ARGS=!JAVA_ARGS! -Xmx%JVM_XMX%"

echo.
echo [INFO] Starting Hytale Server...
echo [INFO]   Agent: %AGENT_JAR%
echo [INFO]   Assets: %ASSETS_PATH%
echo [INFO]   Bind: %BIND_ADDRESS%
echo [INFO]   Auth mode: %AUTH_MODE%
echo.

:: Start the server with DualAuth Agent
java %JAVA_ARGS% -javaagent:"%AGENT_JAR%" -jar HytaleServer.jar ^
    --assets "%ASSETS_PATH%" ^
    --bind "%BIND_ADDRESS%" ^
    --auth-mode "%AUTH_MODE%" ^
    --session-token "!SESSION_TOKEN!" ^
    --identity-token "!IDENTITY_TOKEN!" ^
    %*

echo.
echo ============================================================
echo   Server has stopped. Exit code: %ERRORLEVEL%
echo ============================================================
pause

endlocal
