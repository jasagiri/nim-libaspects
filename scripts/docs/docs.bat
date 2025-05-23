@echo off
REM Documentation generation script for power_assert_nim

REM Get the project root directory
SET "PROJECT_ROOT=%~dp0..\..\"
SET "SRC_DIR=%PROJECT_ROOT%src"
SET "DOCS_DIR=%PROJECT_ROOT%docs"

REM Create docs directory if it doesn't exist
if not exist "%DOCS_DIR%" mkdir "%DOCS_DIR%"

echo Generating documentation...

REM Run nim doc on the main module file
nim doc --project --outdir:"%DOCS_DIR%" "%SRC_DIR%\power_assert.nim"

REM Check if docs should be opened in browser
if "%OPEN_DOCS%"=="true" (
  echo Opening documentation in default browser...
  start "" "%DOCS_DIR%\power_assert.html"
)

echo Documentation generation completed successfully.