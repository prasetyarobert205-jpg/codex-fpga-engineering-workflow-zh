@echo off
setlocal
echo TOOL_ENV_FAIL: no standalone native linter recipe is configured.
echo Configure a real Verilator/svlint/vendor-linter command before use.
echo.
pause
exit /b 1
