@echo off
REM ===========================================================================
REM 共通関数ライブラリ (Windows版)
REM スクリプト間で共有される汎用関数を定義します
REM ===========================================================================

REM 環境設定をロード（まだ読み込まれていない場合）
IF NOT DEFINED PROJECT_ROOT (
  CALL "%~dp0..\env\env.bat"
)

REM ログ出力関数
:log_info
SET "MSG=%~1"
IF /I "%COLOR_OUTPUT%"=="true" (
  echo [34m===[0m %MSG%
) ELSE (
  echo === %MSG%
)
EXIT /b 0

:log_success
SET "MSG=%~1"
IF /I "%COLOR_OUTPUT%"=="true" (
  echo [32m^✓[0m %MSG%
) ELSE (
  echo ^✓ %MSG%
)
EXIT /b 0

:log_warning
SET "MSG=%~1"
IF /I "%COLOR_OUTPUT%"=="true" (
  echo [33m^![0m %MSG%
) ELSE (
  echo ^! %MSG%
)
EXIT /b 0

:log_error
SET "MSG=%~1"
IF /I "%COLOR_OUTPUT%"=="true" (
  echo [31mERROR:[0m %MSG% 1>&2
) ELSE (
  echo ERROR: %MSG% 1>&2
)
EXIT /b 0

REM ディレクトリ作成（存在確認付き）
:ensure_dir
SET "DIR=%~1"
IF NOT EXIST "%DIR%" (
  mkdir "%DIR%" 2>nul
  IF ERRORLEVEL 0 (
    CALL :log_success "Created directory: %DIR%"
  ) ELSE (
    CALL :log_error "Failed to create directory: %DIR%"
    EXIT /b 1
  )
)
EXIT /b 0

REM ファイルをバックアップ
:backup_file
SET "FILE=%~1"
SET "BACKUP=%FILE%.bak"

IF EXIST "%FILE%" (
  copy "%FILE%" "%BACKUP%" >nul
  CALL :log_success "Backed up %FILE% to %BACKUP%"
) ELSE (
  CALL :log_warning "File %FILE% does not exist, no backup created"
)
EXIT /b 0

REM コマンドの存在確認
:check_command
SET "CMD=%~1"
where %CMD% >nul 2>&1
IF %ERRORLEVEL% NEQ 0 (
  CALL :log_error "Required command '%CMD%' not found"
  EXIT /b 1
)
EXIT /b 0

REM エラー発生時の終了処理
:cleanup_and_exit
SET "EXIT_CODE=%~1"
SET "MESSAGE=%~2"

IF NOT "%MESSAGE%"=="" (
  CALL :log_error "%MESSAGE%"
)

EXIT /b %EXIT_CODE%

REM ファイル名から拡張子を取得
:get_extension
SET "FILENAME=%~1"
FOR %%F IN ("%FILENAME%") DO SET "EXTENSION=%%~xF"
SET "EXTENSION=%EXTENSION:~1%"
echo %EXTENSION%
EXIT /b 0

REM ファイル名から拡張子を除いた部分を取得
:get_basename
SET "FILENAME=%~1"
FOR %%F IN ("%FILENAME%") DO SET "BASENAME=%%~nF"
echo %BASENAME%
EXIT /b 0

REM CSVファイルからデータを読み込む
:parse_csv
SET "CSV_FILE=%~1"
SET "DELIMITER=%~2"
IF "%DELIMITER%"=="" SET "DELIMITER=,"

IF NOT EXIST "%CSV_FILE%" (
  CALL :log_error "CSV file not found: %CSV_FILE%"
  EXIT /b 1
)

FOR /F "usebackq tokens=1,2* delims=%DELIMITER%" %%A IN ("%CSV_FILE%") DO (
  REM 処理ロジックをここに記述
  echo Column 1: %%A, Column 2: %%B
)
EXIT /b 0

REM 共通ライブラリが読み込まれたことを通知
IF /I "%VERBOSE%"=="true" (
  CALL :log_info "Common functions loaded"
)