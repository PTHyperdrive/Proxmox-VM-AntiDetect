@echo off
REM ---------------------------------------------------------------
REM  proxmox-atd :: Docker Build Wrapper (Windows)
REM  Convenience script to build inside Docker from Windows
REM
REM  Usage:
REM    docker-build.bat                         Build all targets
REM    docker-build.bat --target qemu           QEMU only
REM    docker-build.bat --target kernel         Kernel only
REM    docker-build.bat --no-cache              Force rebuild image
REM
REM  Artifacts will appear in .\build-output\artifacts\
REM  Part of: https://github.com/proxmox-atd
REM ---------------------------------------------------------------
setlocal enabledelayedexpansion

set "SCRIPT_DIR=%~dp0"
set "IMAGE_NAME=atd-builder"
set "CONTAINER_NAME=atd-build-%RANDOM%"
set "OUTPUT_DIR=%SCRIPT_DIR%build-output"
set "NO_CACHE="
set "ORCHESTRATOR_ARGS="

REM ── Parse arguments ──
:parse_args
if "%~1"=="" goto done_args
if /i "%~1"=="--no-cache" (
    set "NO_CACHE=--no-cache"
    shift
    goto parse_args
)
if defined ORCHESTRATOR_ARGS (
    set "ORCHESTRATOR_ARGS=!ORCHESTRATOR_ARGS! %~1"
) else (
    set "ORCHESTRATOR_ARGS=%~1"
)
shift
goto parse_args
:done_args

echo.
echo +======================================================+
echo ^|  proxmox-atd :: Docker Build (Windows)                ^|
echo +======================================================+
echo.

REM ── Check Docker is available ──
where docker >nul 2>&1
if %errorlevel% neq 0 (
    echo [XX] Docker not found. Install Docker Desktop for Windows.
    echo      https://docs.docker.com/desktop/install/windows-install/
    exit /b 1
)

REM ── Check Docker daemon is running ──
docker info >nul 2>&1
if %errorlevel% neq 0 (
    echo [XX] Docker daemon is not running. Start Docker Desktop first.
    exit /b 1
)

REM ── Build the Docker image ──
echo [^>^>] Building Docker image: %IMAGE_NAME% ...
docker build %NO_CACHE% -t "%IMAGE_NAME%" "%SCRIPT_DIR%."
if %errorlevel% neq 0 (
    echo [XX] Docker image build failed.
    exit /b 1
)
echo [OK] Docker image ready
echo.

REM ── Create output directory ──
if not exist "%OUTPUT_DIR%" mkdir "%OUTPUT_DIR%"

REM ── Run the build ──
echo [^>^>] Starting build container ...
if defined ORCHESTRATOR_ARGS (
    echo      Args: %ORCHESTRATOR_ARGS%
) else (
    echo      Args: ^<default: --target all^>
)
echo.

if defined ORCHESTRATOR_ARGS (
    docker run --rm --name "%CONTAINER_NAME%" -v "%OUTPUT_DIR%:/build/build-output" -e "CI=1" "%IMAGE_NAME%" %ORCHESTRATOR_ARGS%
) else (
    docker run --rm --name "%CONTAINER_NAME%" -v "%OUTPUT_DIR%:/build/build-output" -e "CI=1" "%IMAGE_NAME%"
)

set "BUILD_RC=%errorlevel%"

echo.
if %BUILD_RC% equ 0 (
    echo [OK] Build complete! Artifacts:
    if exist "%OUTPUT_DIR%\artifacts" (
        dir /b "%OUTPUT_DIR%\artifacts\"
    ) else (
        echo [!!] No artifacts found in %OUTPUT_DIR%\artifacts\
    )
) else (
    echo [XX] Build failed with exit code %BUILD_RC%
)

exit /b %BUILD_RC%
