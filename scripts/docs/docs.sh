#!/bin/bash
# Documentation generation script for power_assert_nim

# Load common environment settings and functions
SCRIPT_DIR="$(dirname "$0")"
source "${SCRIPT_DIR}/../../scripts/env/env.sh"
source "${SCRIPT_DIR}/../../scripts/common/common.sh"

# Setup clean exit with trap
set_cleanup_trap

log_info "Generating documentation for power_assert_nim"

# Create docs directory if it doesn't exist
ensure_dir "${DOCS_DIR}"
ensure_dir "${BUILD_DOCS}"

# Check if prerequisite commands are available
check_command "${NIM_COMPILER}" || cleanup_and_exit 1 "Nim compiler not found"

# Set documentation flags
DOC_FLAGS="--project"
if [ "${VERBOSE}" = "true" ]; then
  DOC_FLAGS="${DOC_FLAGS} --verbosity:2"
fi

log_info "Using output directory: ${BUILD_DOCS}"

# Run nim doc on the main module file
time_command ${NIM_COMPILER} doc ${DOC_FLAGS} --outdir:"${BUILD_DOCS}" "${SRC_DIR}/${MAIN_MODULE}.nim"

# Copy to docs directory if successful
if [ $? -eq 0 ]; then
  log_success "Documentation generated successfully"
  
  # Copy HTML documentation to docs directory
  log_info "Copying documentation to docs directory"
  cp -r "${BUILD_DOCS}"/*.html "${DOCS_DIR}/" 2>/dev/null || true
  cp -r "${BUILD_DOCS}"/*.css "${DOCS_DIR}/" 2>/dev/null || true
  cp -r "${BUILD_DOCS}"/*.js "${DOCS_DIR}/" 2>/dev/null || true
  
  # Check if docs should be opened in browser
  if [ "${OPEN_DOCS}" = "true" ]; then
    log_info "Opening documentation in default browser"
    
    # Open index.html with the default browser based on the OS
    if [ "${IS_MACOS}" = "true" ]; then
      open "${DOCS_DIR}/${MAIN_MODULE}.html"
    elif [ "${IS_LINUX}" = "true" ]; then
      if command -v xdg-open >/dev/null 2>&1; then
        xdg-open "${DOCS_DIR}/${MAIN_MODULE}.html"
      else
        log_warning "xdg-open not found. Please open documentation manually"
      fi
    elif [ "${IS_WINDOWS}" = "true" ]; then
      if command -v start >/dev/null 2>&1; then
        start "${DOCS_DIR}/${MAIN_MODULE}.html"
      else
        log_warning "Cannot auto-open browser on this Windows environment"
      fi
    else
      log_warning "Documentation generated, but auto-open not supported on this OS"
      log_info "Please open ${DOCS_DIR}/${MAIN_MODULE}.html manually"
    fi
  fi
else
  log_error "Documentation generation failed"
  cleanup_and_exit 1 "Documentation generation failed"
fi

log_success "Documentation process completed"