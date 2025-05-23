#\!/bin/bash
# ===========================================================================
# 共通関数ライブラリ
# スクリプト間で共有される汎用関数を定義します
# ===========================================================================

# 現在のスクリプトディレクトリを取得
COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 環境設定をロード（まだ読み込まれていない場合）
if [ -z "${PROJECT_ROOT}" ]; then
  source "${COMMON_DIR}/../env/env.sh"
fi

# ログ出力関数
log_info() {
  if [ "${COLOR_OUTPUT}" = "true" ]; then
    echo -e "${COLOR_BLUE}===${COLOR_RESET} $1"
  else
    echo "=== $1"
  fi
}

log_success() {
  if [ "${COLOR_OUTPUT}" = "true" ]; then
    echo -e "${COLOR_GREEN}✓${COLOR_RESET} $1"
  else
    echo "✓ $1"
  fi
}

log_warning() {
  if [ "${COLOR_OUTPUT}" = "true" ]; then
    echo -e "${COLOR_YELLOW}\!${COLOR_RESET} $1"
  else
    echo "\! $1"
  fi
}

log_error() {
  if [ "${COLOR_OUTPUT}" = "true" ]; then
    echo -e "${COLOR_RED}ERROR:${COLOR_RESET} $1" >&2
  else
    echo "ERROR: $1" >&2
  fi
}

# ディレクトリ作成（存在確認付き）
ensure_dir() {
  local dir="$1"
  if [ \! -d "${dir}" ]; then
    mkdir -p "${dir}"
    log_success "Created directory: ${dir}"
  fi
}

# ファイルをバックアップ
backup_file() {
  local file="$1"
  local backup="${file}.bak"
  
  if [ -f "${file}" ]; then
    cp "${file}" "${backup}"
    log_success "Backed up ${file} to ${backup}"
  else
    log_warning "File ${file} does not exist, no backup created"
  fi
}

# コマンドの存在確認
check_command() {
  local cmd="$1"
  if \! command -v "${cmd}" &> /dev/null; then
    log_error "Required command '${cmd}' not found"
    return 1
  fi
  return 0
}

# エラー発生時の終了処理
cleanup_and_exit() {
  local exit_code="$1"
  local message="$2"
  
  if [ -n "${message}" ]; then
    log_error "${message}"
  fi
  
  exit "${exit_code}"
}

# プラットフォーム検出
get_platform() {
  if [ "${IS_MACOS}" = "true" ]; then
    echo "macos"
  elif [ "${IS_LINUX}" = "true" ]; then
    echo "linux"
  elif [ "${IS_WINDOWS}" = "true" ]; then
    echo "windows"
  else
    echo "unknown"
  fi
}

# 処理時間の計測
time_command() {
  local start=$(date +%s)
  "$@"
  local exit_code=$?
  local end=$(date +%s)
  local runtime=$((end-start))
  
  log_info "Execution time: ${runtime} seconds"
  return ${exit_code}
}

# ファイル名から拡張子を取得
get_extension() {
  local filename="$1"
  echo "${filename##*.}"
}

# ファイル名から拡張子を除いた部分を取得
get_basename() {
  local filename="$1"
  local basename="${filename##*/}"
  echo "${basename%.*}"
}

# スクリプト実行時にTRAPを設定
set_cleanup_trap() {
  trap 'log_warning "Script interrupted, cleaning up..."; cleanup_and_exit 1 "Script execution aborted"' INT TERM
}

# CSVファイルからデータを読み込む
parse_csv() {
  local csv_file="$1"
  local delimiter="${2:-,}"
  
  if [ \! -f "${csv_file}" ]; then
    log_error "CSV file not found: ${csv_file}"
    return 1
  fi
  
  while IFS="${delimiter}" read -r col1 col2 remainder; do
    # 処理ロジックをここに記述
    echo "Column 1: ${col1}, Column 2: ${col2}"
  done < "${csv_file}"
}

# 共通ライブラリが読み込まれたことを通知
if [ "${VERBOSE}" = "true" ]; then
  log_info "Common functions loaded"
fi
