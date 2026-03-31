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
::    4. Copies the local manifest and runs  west init / west update
::    5. Exports the Zephyr CMake package
::    6. Installs Zephyr Python dependencies
::    7. Installs the Zephyr SDK            (via west sdk install)
::    8. Downloads Silicon Labs BLE radio blobs
::    9. Leaves application repos to be cloned manually by the developer
::
::  Usage:
::    Place this .bat file inside your manifest repo (next to west.yml).
::    Right-click this file → "Run as Administrator"
::    The script will ask you for a workspace directory path.
:: ============================================================================

:: ── Configuration ──────────────────────────────────────────────────────────

set "BOARD=xg24_dk2601b"

:: The manifest repo is THIS directory (where the .bat lives).
:: Resolve it to an absolute path.
set "MANIFEST_DIR=%~dp0"
:: Remove trailing backslash
if "%MANIFEST_DIR:~-1%"=="\" set "MANIFEST_DIR=%MANIFEST_DIR:~0,-1%"

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

:: ── Ask for workspace directory ────────────────────────────────────────────
echo.
echo   The workspace directory is where Zephyr, modules, and any app
echo   repos you clone manually will live. Keep the path SHORT and without spaces
echo   to avoid build issues.
echo.
set /p "WORKSPACE_DIR=   Enter workspace path (e.g. C:\zephyr-ws): "

if "%WORKSPACE_DIR%"=="" (
    echo %FAIL% Workspace path cannot be empty.
    pause
    exit /b 1
)

:: Remove any surrounding quotes the user may have typed
set "WORKSPACE_DIR=%WORKSPACE_DIR:"=%"

:: Remove trailing backslash if present
if "%WORKSPACE_DIR:~-1%"=="\" set "WORKSPACE_DIR=%WORKSPACE_DIR:~0,-1%"

echo.
echo %OK% Workspace will be created at: %WORKSPACE_DIR%

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

:: ── Ensure WinGet tools are on PATH ────────────────────────────────────────
:: winget installs tools into Packages directories and creates shims in a
:: "Links" folder. The Links folder may already be on PATH (as winget is
:: supposed to add it), but we ensure it here just in case.
:: IMPORTANT: We APPEND to the existing PATH — never replace it.

echo.
echo %INFO% Ensuring WinGet tool directories are on PATH...

if exist "%LOCALAPPDATA%\Microsoft\WinGet\Links" (
    echo !PATH! | find /i "WinGet\Links" >nul
    if !errorlevel! neq 0 (
        set "PATH=!PATH!;%LOCALAPPDATA%\Microsoft\WinGet\Links"
        echo        Added: %LOCALAPPDATA%\Microsoft\WinGet\Links
    ) else (
        echo        Already on PATH: WinGet\Links
    )
)

if exist "%ProgramFiles%\WinGet\Links" (
    echo !PATH! | find /i "WinGet\Links" >nul
    if !errorlevel! neq 0 (
        set "PATH=!PATH!;%ProgramFiles%\WinGet\Links"
        echo        Added: %ProgramFiles%\WinGet\Links
    )
)

:: dtc is a special case — winget nests it under usr\bin inside the package.
for /d %%D in ("%LOCALAPPDATA%\Microsoft\WinGet\Packages\oss-winget.dtc_*") do (
    if exist "%%~D\usr\bin\dtc.exe" (
        echo !PATH! | find /i "oss-winget.dtc" >nul
        if !errorlevel! neq 0 (
            set "PATH=!PATH!;%%~D\usr\bin"
            echo        Added: %%~D\usr\bin  ^(dtc^)
        )
    )
)
for /d %%D in ("%ProgramFiles%\WinGet\Packages\oss-winget.dtc_*") do (
    if exist "%%~D\usr\bin\dtc.exe" (
        echo !PATH! | find /i "oss-winget.dtc" >nul
        if !errorlevel! neq 0 (
            set "PATH=!PATH!;%%~D\usr\bin"
            echo        Added: %%~D\usr\bin  ^(dtc^)
        )
    )
)

:: ── Verify critical tools ──────────────────────────────────────────────────
echo.
echo %INFO% Verifying tools...
set "TOOLS_OK=1"
set "MISSING_TOOLS="

for %%T in (cmake ninja gperf python git) do (
    where %%T >nul 2>&1
    if !errorlevel! neq 0 (
        echo %FAIL% %%T not found.
        set "TOOLS_OK=0"
        set "MISSING_TOOLS=!MISSING_TOOLS! %%T"
    ) else (
        for /f "delims=" %%P in ('where %%T 2^>nul') do echo        %%T ... %%P
    )
)

if "%TOOLS_OK%"=="0" (
    echo.
    echo %FAIL% Could not find:%MISSING_TOOLS%
    echo.
    echo        The following directories were searched:
    echo          - System and User PATH from registry
    echo          - %LOCALAPPDATA%\Microsoft\WinGet\Links
    echo          - %ProgramFiles%\WinGet\Links
    echo.
    echo        To fix, try uninstalling and reinstalling the missing tool:
    echo          winget uninstall --id ^<package-id^>
    echo          winget install -e --id ^<package-id^>
    echo.
    echo        Or install manually from the tool's website, making sure to
    echo        check "Add to PATH" during installation.
    echo.
    pause
    exit /b 1
)
echo %OK% All required tools found.

:: Configure Git for long paths (now that Git is guaranteed installed)
git config --global core.longpaths true >nul 2>&1

:: ── Refresh Python Scripts directory on PATH ────────────────────────────────
:: winget-installed Python 3.12 updates the registry PATH but not the current
:: session's PATH. We ask Python itself where its Scripts folder is and append
:: it so that pip, west, and other entry-points are immediately reachable.
echo.
echo %INFO% Refreshing Python Scripts directory on PATH...

for /f "delims=" %%S in ('python -c "import sys,os; print(os.path.join(sys.prefix,'Scripts'))" 2^>nul') do (
    if exist "%%~S" (
        echo !PATH! | find /i "%%~S" >nul
        if !errorlevel! neq 0 (
            set "PATH=!PATH!;%%~S"
            echo        Added: %%~S
        ) else (
            echo        Already on PATH: %%~S
        )
    )
)

:: Also add the user-level Scripts folder (pip install --user target)
for /f "delims=" %%U in ('python -c "import site; print(site.getusersitepackages().replace(\"site-packages\",\"Scripts\"))" 2^>nul') do (
    if exist "%%~U" (
        echo !PATH! | find /i "%%~U" >nul
        if !errorlevel! neq 0 (
            set "PATH=!PATH!;%%~U"
            echo        Added: %%~U  ^(user Scripts^)
        )
    )
)

:: ============================================================================
::  STEP 3 — Install West
:: ============================================================================
echo.
echo %INFO% Step 3/8: Installing West...

python -m pip show west >nul 2>&1
if %errorlevel% equ 0 (
    echo %OK% West already installed.
) else (
    python -m pip install west
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
::  STEP 4 — Copy manifest locally and initialise workspace
:: ============================================================================
echo.
echo %INFO% Step 4/8: Setting up workspace at %WORKSPACE_DIR%...

if not exist "%WORKSPACE_DIR%" (
    mkdir "%WORKSPACE_DIR%"
)

cd /d "%WORKSPACE_DIR%"

:: Copy the manifest repo from the local directory where this script lives.
:: The manifest is the folder containing west.yml (same folder as this .bat).
if exist "manifest\west.yml" (
    echo %OK% Manifest already present in workspace.
) else (
    echo %INFO% Copying manifest from %MANIFEST_DIR% ...
    if not exist "%MANIFEST_DIR%\west.yml" (
        echo %FAIL% west.yml not found next to this batch file.
        echo        Make sure this .bat is inside the manifest repo folder
        echo        alongside west.yml.
        pause
        exit /b 1
    )
    xcopy "%MANIFEST_DIR%" "%WORKSPACE_DIR%\manifest\" /E /I /H /Y >nul
    if !errorlevel! neq 0 (
        echo %FAIL% Could not copy manifest to workspace.
        pause
        exit /b 1
    )
    echo %OK% Manifest copied to %WORKSPACE_DIR%\manifest
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

:: Fetch west-managed projects (Zephyr and SDK/module dependencies)
echo %INFO% Running west update (this will take a while on first run)...
west update
if %errorlevel% neq 0 (
    echo %FAIL% west update failed. Check your network connection.
    pause
    exit /b 1
)
echo %OK% West-managed projects fetched.

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
    python -m pip install -r zephyr\scripts\requirements.txt
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
echo     git clone ^<APP_REPO_URL^> KeyFob_App
echo     west build -b %BOARD% KeyFob_App
echo     west flash
echo.

if defined NEEDS_REBOOT (
    echo   NOTE: Long paths were enabled. Please reboot your PC for this
    echo         to take effect system-wide.
    echo.
)

echo   To rebuild from scratch:
echo     west build -b %BOARD% KeyFob_App -p
echo.
echo   To open menuconfig:
echo     west build -t menuconfig
echo.
echo ===========================================================================
echo.
pause
endlocal
