@echo off
setlocal EnableExtensions
set "JAVA_SETUP_NO_BRIDGE=1"
set "JAVA_SETUP_NO_PAUSE=1"
call "%~dp0install.bat" --fix-all %*
set "EXIT_CODE=%ERRORLEVEL%"
if defined JAVA_SETUP_JOB_SENTINEL (
  set "SENTINEL_FILE=%JAVA_SETUP_JOB_SENTINEL%"
) else (
  set "SENTINEL_FILE=%~dp0repair-job.exit"
)
> "%SENTINEL_FILE%" echo %EXIT_CODE%
exit /b %EXIT_CODE%
