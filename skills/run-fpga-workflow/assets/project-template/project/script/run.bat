@echo off
setlocal EnableExtensions
set "SCRIPT_DIR=%~dp0"
for %%I in ("%SCRIPT_DIR%..\..") do set "PROJECT_ROOT=%%~fI"
call "%SCRIPT_DIR%setting.bat"
if errorlevel 1 goto :FAIL
set "ACTION=%~1"
if "%ACTION%"=="" set "ACTION=compile"
set "RUN_DIR=%PROJECT_ROOT%\project\par"
if not exist "%RUN_DIR%" mkdir "%RUN_DIR%"
if errorlevel 1 goto :FAIL
pushd "%RUN_DIR%"
if errorlevel 1 goto :FAIL
echo TOOL_ENV_FAIL: the __VENDOR__ native build Tcl/CLI recipe is not configured.
echo Confirm the exact tool/version/project/part, then keep the one selected
echo vendor flow beside this BAT. Its real launcher must be created directly in:
echo   %RUN_DIR%
echo Do not add a project\par\vivado_project or project\par\build container.
popd
set "RC=1"
goto :DONE
:FAIL
set "RC=1"
:DONE
echo.
pause
exit /b %RC%
