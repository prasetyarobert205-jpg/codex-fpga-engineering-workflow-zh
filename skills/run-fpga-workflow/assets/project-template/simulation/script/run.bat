@echo off
setlocal EnableExtensions
set "SCRIPT_DIR=%~dp0"
for %%I in ("%SCRIPT_DIR%..\..") do set "PROJECT_ROOT=%%~fI"
call "%PROJECT_ROOT%\project\script\setting.bat"
if errorlevel 1 goto :FAIL
set "CASE_NAME=%~1"
if "%CASE_NAME%"=="" set "CASE_NAME=default"
set "MODE=%~2"
if "%MODE%"=="" set "MODE=gui"
set "RUN_DIR=%PROJECT_ROOT%\simulation\work"
if not exist "%RUN_DIR%" mkdir "%RUN_DIR%"
if errorlevel 1 goto :FAIL
if not exist "%SCRIPT_DIR%setting.txt" goto :FAIL
if not exist "%SCRIPT_DIR%src_list.txt" goto :FAIL
if not exist "%SCRIPT_DIR%vsim.do" goto :FAIL
pushd "%RUN_DIR%"
if errorlevel 1 goto :FAIL
echo TOOL_ENV_FAIL: the confirmed __VENDOR__ ModelSim/Questa export and library recipe is not configured.
echo Keep generated compile.do, modelsim.ini, libraries, logs and waves under:
echo   %RUN_DIR%
popd
set "RC=1"
goto :DONE
:FAIL
set "RC=1"
:DONE
echo.
pause
exit /b %RC%
