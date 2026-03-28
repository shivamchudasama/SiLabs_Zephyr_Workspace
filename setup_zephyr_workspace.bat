@echo off
setlocal EnableDelayedExpansion

:: ============================================================================
::  setup_zephyr_workspace.bat
::
::  One-click setup for Silicon Labs BLE Zephyr development on Windows.
::  Uses winget (Windows' built-in package manager) per the official
::  Zephyr Getting Started Guide.
::
::  What this script does:
::    1. Enables Windows long-path support  (requires Administrator)
::    2. Installs host tools via winget     (cmake, ninja, python, git, etc.)
::    3. Installs West (Zephyr meta-tool)
::    4. Clones the manifest repo and runs  west init / west update
::    5. Exports the Zephyr CMake package
::    6. Installs Zephyr Python dependencies
::    7. Installs the Zephyr SDK            (via west sdk install)
::    8. Downloads Silicon Labs BLE radio blobs
::
::  Usage:
::    Right-click this file → "Run as Administrator"
::
::    OR from an elevated command prompt:
::      setup_zephyr_workspace.bat [workspace_path]
::
::    Default workspace path: %USERPROFILE%\zephyr-silabs-workspace
:: ============================================================================

:: ── Configuration ──────────────────────────────────────────────────────────
:: Change these to match your GitHub org / repo URLs.

set "MANIFEST_REPO_URL=https://github.com/your-org/silabs-ble-manifest.git"
set "WORKSPACE_DIR=%~1"
if "%WORKSPACE_DIR%"=="" set "WORKSPACE_DIR=%USERPROFILE%\zephyr-silabs-workspace"
set "BOARD=xg24_dk2601b"

:: ── Labels ─────────────────────────────────────────────────────────────────
set "INFO=[INFO]"
set "OK=[  OK]"
set "FAIL=[FAIL]"
set "WARN=[WARN]"

:: ============================================================================
::  STEP 0 — Check for Administrator privileges
:: ============================================================================
echo.
echo ===========================================================================
echo   Silicon Labs BLE - Zephyr Workspace Setup  (winget edition)
echo ===========================================================================
echo.

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo %FAIL% This script must be run as Administrator.
    echo        Right-click the file and select "Run as Administrator".
    echo.
    pause
    exit /b 1
)
echo %OK% Running with Administrator privileges.

:: ============================================================================
::  STEP 1 — Enable long paths
:: ============================================================================
echo.
echo %INFO% Step 1/8: Enabling Windows long-path support...

reg query "HKLM\SYSTEM\CurrentControlSet\Control\FileSystem" /v LongPathsEnabled 2>nul | find "0x1" >nul
if %errorlevel% equ 0 (
    echo %OK% Long paths already enabled.
) else (
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\FileSystem" /v LongPathsEnabled /t REG_DWORD /d 1 /f >nul 2>&1
    if !errorlevel! equ 0 (
        echo %OK% Long paths enabled. A reboot is recommended after setup.
        set "NEEDS_REBOOT=1"
    ) else (
        echo %FAIL% Could not enable long paths. Continuing anyway...
    )
)

:: Configure Git for long paths (if already installed)
where git >nul 2>&1
if %errorlevel% equ 0 (
    git config --global core.longpaths true >nul 2>&1
    echo %OK% Git configured for long paths.
)

:: ============================================================================
::  STEP 2 — Install host tools via winget
:: ============================================================================
echo.
echo %INFO% Step 2/8: Installing host tools via winget...
echo.

:: Verify winget is available
where winget >nul 2>&1
if %errorlevel% neq 0 (
    echo %FAIL% winget is not available on this system.
    echo        winget comes pre-installed on Windows 10 ^(1709+^) and Windows 11.
    echo        Install it from: https://aka.ms/getwinget
    pause
    exit /b 1
)

:: Install packages using the exact IDs from the official Zephyr guide.
:: winget will skip packages that are already installed.
echo %INFO% Installing CMake...
winget install -e --id Kitware.CMake --accept-source-agreements --accept-package-agreements

echo.
echo %INFO% Installing Ninja...
winget install -e --id Ninja-build.Ninja --accept-source-agreements --accept-package-agreements

echo.
echo %INFO% Installing gperf...
winget install -e --id oss-winget.gperf --accept-source-agreements --accept-package-agreements

echo.
echo %INFO% Installing Python 3.12...
winget install -e --id Python.Python.3.12 --accept-source-agreements --accept-package-agreements

echo.
echo %INFO% Installing Git...
winget install -e --id Git.Git --accept-source-agreements --accept-package-agreements

echo.
echo %INFO% Installing Device Tree Compiler...
winget install -e --id oss-winget.dtc --accept-source-agreements --accept-package-agreements

echo.
echo %INFO% Installing wget...
winget install -e --id=GnuWin32.Wget --accept-source-agreements --accept-package-agreements

echo.
echo %INFO% Installing 7-Zip...
winget install -e --id 7zip.7zip --accept-source-agreements --accept-package-agreements

:: ── Refresh PATH ───────────────────────────────────────────────────────────
:: winget installs may update PATH but the current shell won't see it.
:: We reload PATH from the registry so newly installed tools are found.
echo.
echo %INFO% Refreshing PATH...

for /f "tokens=2*" %%A in (
    'reg query "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v Path 2^>nul'
) do set "SYS_PATH=%%B"

for /f "tokens=2*" %%A in (
    'reg query "HKCU\Environment" /v Path 2^>nul'
) do set "USR_PATH=%%B"

set "PATH=%SYS_PATH%;%USR_PATH%"

:: Also try refreshenv if available (from Chocolatey or other tools)
call refreshenv >nul 2>&1

:: ── Verify critical tools ──────────────────────────────────────────────────
echo.
echo %INFO% Verifying tools...
set "TOOLS_OK=1"

for %%T in (cmake ninja gperf python git) do (
    where %%T >nul 2>&1
    if !errorlevel! neq 0 (
        echo %FAIL% %%T not found on PATH.
        set "TOOLS_OK=0"
    ) else (
        echo        %%T ... found
    )
)

if "%TOOLS_OK%"=="0" (
    echo.
    echo %WARN% Some tools are not yet on PATH in this shell session.
    echo        This is normal after a fresh winget install.
    echo.
    echo        Please CLOSE this window, open a NEW Admin command prompt,
    echo        and re-run this script. The second run will skip packages
    echo        that are already installed and continue from where it left off.
    echo.
    pause
    exit /b 1
)
echo %OK% All required tools found.

:: Configure Git for long paths (now that Git is guaranteed installed)
git config --global core.longpaths true >nul 2>&1

:: ============================================================================
::  STEP 3 — Install West
:: ============================================================================
echo.
echo %INFO% Step 3/8: Installing West...

pip show west >nul 2>&1
if %errorlevel% equ 0 (
    echo %OK% West already installed.
) else (
    pip install west
    if !errorlevel! neq 0 (
        echo %FAIL% West installation failed.
        pause
        exit /b 1
    )
    echo %OK% West installed.
)

:: Verify west is callable
where west >nul 2>&1
if %errorlevel% neq 0 (
    echo %WARN% West not found on PATH. Trying via Python module...
    python -m west --version >nul 2>&1
    if !errorlevel! neq 0 (
        echo %FAIL% West is not accessible. Check your PATH.
        pause
        exit /b 1
    )
)

west --version 2>nul
echo.

:: ============================================================================
::  STEP 4 — Clone manifest and initialise workspace
:: ============================================================================
echo.
echo %INFO% Step 4/8: Setting up workspace at %WORKSPACE_DIR%...

if not exist "%WORKSPACE_DIR%" (
    mkdir "%WORKSPACE_DIR%"
)

cd /d "%WORKSPACE_DIR%"

:: Clone the manifest repo if not already present
if exist "manifest\.git" (
    echo %OK% Manifest repo already cloned.
) else (
    echo %INFO% Cloning manifest repo...
    git clone "%MANIFEST_REPO_URL%" manifest
    if !errorlevel! neq 0 (
        echo %FAIL% Could not clone manifest repo.
        echo        Check the URL: %MANIFEST_REPO_URL%
        echo.
        echo        If you haven't pushed your manifest repo yet, you can:
        echo          1. Copy the manifest folder manually into %WORKSPACE_DIR%
        echo          2. Re-run this script
        pause
        exit /b 1
    )
    echo %OK% Manifest repo cloned.
)

:: Initialise West workspace
if exist ".west" (
    echo %OK% West workspace already initialised.
) else (
    echo %INFO% Initialising West workspace...
    west init -l manifest
    if !errorlevel! neq 0 (
        echo %FAIL% west init failed.
        pause
        exit /b 1
    )
    echo %OK% West workspace initialised.
)

:: Fetch all projects (Zephyr, modules, app repos)
echo %INFO% Running west update (this will take a while on first run)...
west update
if %errorlevel% neq 0 (
    echo %FAIL% west update failed. Check your network connection.
    pause
    exit /b 1
)
echo %OK% All projects fetched.

:: ============================================================================
::  STEP 5 — Export Zephyr CMake package
:: ============================================================================
echo.
echo %INFO% Step 5/8: Exporting Zephyr CMake package...

west zephyr-export
if %errorlevel% neq 0 (
    echo %WARN% west zephyr-export failed. Builds may still work.
) else (
    echo %OK% Zephyr CMake package exported.
)

:: ============================================================================
::  STEP 6 — Install Zephyr Python dependencies
:: ============================================================================
echo.
echo %INFO% Step 6/8: Installing Zephyr Python dependencies...

if exist "zephyr\scripts\utils\west-packages-pip-install.cmd" (
    echo %INFO% Using west-packages-pip-install.cmd...
    cmd /c zephyr\scripts\utils\west-packages-pip-install.cmd
    if !errorlevel! neq 0 (
        echo %WARN% Some Python packages may have failed. Check output above.
    ) else (
        echo %OK% Python dependencies installed.
    )
) else if exist "zephyr\scripts\requirements.txt" (
    echo %INFO% Falling back to requirements.txt...
    pip install -r zephyr\scripts\requirements.txt
    if !errorlevel! neq 0 (
        echo %WARN% Some Python packages may have failed. Check output above.
    ) else (
        echo %OK% Python dependencies installed.
    )
) else (
    echo %WARN% Could not find Python dependency files. Skipping.
)

:: ============================================================================
::  STEP 7 — Install Zephyr SDK
:: ============================================================================
echo.
echo %INFO% Step 7/8: Installing Zephyr SDK (ARM toolchain)...
echo        This downloads the SDK matching the Zephyr version in this workspace.
echo.

:: Use 'west sdk install' which auto-detects the correct version.
:: The -t flag selects only the ARM toolchain (all we need for EFR32).
west sdk install -t arm-zephyr-eabi
if %errorlevel% neq 0 (
    echo %WARN% west sdk install with ARM-only failed. Attempting full install...
    west sdk install
    if !errorlevel! neq 0 (
        echo %FAIL% Zephyr SDK installation failed.
        echo        You may need to install it manually from:
        echo        https://github.com/zephyrproject-rtos/sdk-ng/releases
        echo.
        echo        Continuing with remaining steps...
    )
) else (
    echo %OK% Zephyr SDK installed.
)

:: ============================================================================
::  STEP 8 — Fetch Silicon Labs BLE radio blobs
:: ============================================================================
echo.
echo %INFO% Step 8/8: Downloading Silicon Labs BLE radio firmware blobs...

west blobs fetch hal_silabs
if %errorlevel% neq 0 (
    echo %FAIL% Blob fetch failed. BLE will not work without these.
    echo        Try running manually: west blobs fetch hal_silabs
    pause
    exit /b 1
)
echo %OK% Radio blobs downloaded.

:: ============================================================================
::  Done!
:: ============================================================================
echo.
echo ===========================================================================
echo   Setup complete!
echo ===========================================================================
echo.
echo   Workspace : %WORKSPACE_DIR%
echo   Board     : %BOARD%
echo.
echo   To start developing, open a command prompt and run:
echo.
echo     cd %WORKSPACE_DIR%
echo     west build -b %BOARD% silabs-ble-app
echo     west flash
echo.

if defined NEEDS_REBOOT (
    echo   NOTE: Long paths were enabled. Please reboot your PC for this
    echo         to take effect system-wide.
    echo.
)

echo   To rebuild from scratch:
echo     west build -b %BOARD% silabs-ble-app -p
echo.
echo   To open menuconfig:
echo     west build -t menuconfig
echo.
echo ===========================================================================
echo.
pause
endlocal
