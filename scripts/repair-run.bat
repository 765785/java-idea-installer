@echo off
setlocal EnableExtensions
set "JAVA_SETUP_NO_BRIDGE=1"
set "JAVA_SETUP_NO_PAUSE=1"
set "JAVA_SETUP_NO_UI=1"
call "%~dp0install.bat" --fix-all %*
set "EXIT_CODE=%ERRORLEVEL%"
if defined JAVA_SETUP_JOB_SENTINEL (
  set "SENTINEL_FILE=%JAVA_SETUP_JOB_SENTINEL%"
) else (
  set "SENTINEL_FILE=%~dp0repair-job.exit"
)
for %%D in ("%SENTINEL_FILE%") do (
  if not exist "%%~dpD" mkdir "%%~dpD" >nul 2>&1
)
set "SENTINEL_TEMP=%SENTINEL_FILE%.tmp"
> "%SENTINEL_TEMP%" echo %EXIT_CODE%
move /Y "%SENTINEL_TEMP%" "%SENTINEL_FILE%" >nul
exit /b %EXIT_CODE%
