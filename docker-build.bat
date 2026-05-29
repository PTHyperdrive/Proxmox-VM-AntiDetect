@echo off
REM ---------------------------------------------------------------
REM  proxmox-atd :: Docker Build Wrapper (Windows)
REM  Convenience script to build inside Docker from Windows
REM
REM  Usage:
REM    docker-build.bat                         Build all (parallel)
REM    docker-build.bat --target qemu           QEMU only
REM    docker-build.bat --target edk2           EDK2 only
REM    docker-build.bat --target kernel         Kernel only
REM    docker-build.bat --target all            All sequential (1 container)
REM    docker-build.bat --no-cache              Force rebuild image
REM
REM  Default mode runs 2 containers in parallel:
REM    Container 1: QEMU + EDK2 (foreground, ~15 min)
REM    Container 2: Kernel      (background, ~60-120 min)
REM
REM  Artifacts will appear in .\build-output\artifacts\
REM  Part of: https://github.com/proxmox-atd
REM ---------------------------------------------------------------
setlocal enabledelayedexpansion

set "SCRIPT_DIR=%~dp0"
set "IMAGE_NAME=atd-builder"
set "OUTPUT_DIR=%SCRIPT_DIR%build-output"
set "NO_CACHE="
set "TARGET="
set "EXTRA_ARGS="

REM ── Parse arguments ──
:parse_args
if "%~1"=="" goto done_args
if /i "%~1"=="--no-cache" (
    set "NO_CACHE=--no-cache"
    shift
    goto parse_args
)
if /i "%~1"=="--target" (
    set "TARGET=%~2"
    shift
    shift
    goto parse_args
)
REM Collect any other args
if defined EXTRA_ARGS (
    set "EXTRA_ARGS=!EXTRA_ARGS! %~1"
) else (
    set "EXTRA_ARGS=%~1"
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

REM ── Determine build mode ──
if defined TARGET (
    goto single_target
) else (
    goto parallel_build
)

REM ================================================================
REM  SINGLE TARGET MODE: one container, one target
REM ================================================================
:single_target
echo [^>^>] Single target build: %TARGET%
echo.

set "CONTAINER_NAME=atd-%TARGET%-%RANDOM%"
docker run --rm --name "%CONTAINER_NAME%" -v "%OUTPUT_DIR%:/build/build-output" -e "CI=1" "%IMAGE_NAME%" --target %TARGET% %EXTRA_ARGS%
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

REM ================================================================
REM  PARALLEL BUILD MODE: 2 containers (firmware + kernel)
REM ================================================================
:parallel_build
echo [^>^>] Parallel build mode: QEMU+EDK2 ^| Kernel
echo     Container 1: QEMU + EDK2 (foreground)
echo     Container 2: Kernel      (background)
echo.

set "FW_CONTAINER=atd-firmware-%RANDOM%"
set "KN_CONTAINER=atd-kernel-%RANDOM%"

REM ── Start Kernel build in background (detached) ──
echo [^>^>] Starting kernel build (background): %KN_CONTAINER%
docker run -d --name "%KN_CONTAINER%" -v "%OUTPUT_DIR%:/build/build-output" -e "CI=1" "%IMAGE_NAME%" --target kernel %EXTRA_ARGS%
if %errorlevel% neq 0 (
    echo [XX] Failed to start kernel container
    exit /b 1
)
echo [OK] Kernel container started

REM ── Run QEMU + EDK2 in foreground ──
echo.
echo [^>^>] Starting QEMU + EDK2 build (foreground): %FW_CONTAINER%
docker run --rm --name "%FW_CONTAINER%" -v "%OUTPUT_DIR%:/build/build-output" -e "CI=1" "%IMAGE_NAME%" --target all --skip-kernel %EXTRA_ARGS%
set "FW_RC=%errorlevel%"

if %FW_RC% equ 0 (
    echo [OK] QEMU + EDK2 build complete
) else (
    echo [XX] QEMU + EDK2 build failed with exit code %FW_RC%
)

REM ── Wait for Kernel container ──
echo.
echo [^>^>] Waiting for kernel build to complete ...
for /f "tokens=*" %%i in ('docker wait "%KN_CONTAINER%"') do set "KN_RC=%%i"
if not defined KN_RC set "KN_RC=1"

REM ── Show kernel logs (last 80 lines) ──
echo.
echo [^>^>] Kernel build logs (last 80 lines):
docker logs --tail 80 "%KN_CONTAINER%" 2>&1

REM ── Clean up kernel container ──
docker rm "%KN_CONTAINER%" >nul 2>&1

REM ── Report results ──
echo.
echo +======================================================+
echo ^|  Build Results                                        ^|
echo +======================================================+
echo.

if %FW_RC% equ 0 (
    echo [OK] QEMU + EDK2:  SUCCESS
) else (
    echo [XX] QEMU + EDK2:  FAILED (exit code %FW_RC%^)
)

if %KN_RC% equ 0 (
    echo [OK] Kernel:        SUCCESS
) else (
    echo [XX] Kernel:        FAILED (exit code %KN_RC%^)
)

echo.
if exist "%OUTPUT_DIR%\artifacts" (
    echo [^>^>] Artifacts:
    dir /b "%OUTPUT_DIR%\artifacts\"
) else (
    echo [!!] No artifacts found in %OUTPUT_DIR%\artifacts\
)

REM ── Exit with combined result ──
if %FW_RC% neq 0 exit /b %FW_RC%
if %KN_RC% neq 0 exit /b 1
exit /b 0
