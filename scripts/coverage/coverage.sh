#!/bin/sh
# Test coverage script for power_assert_nim

set -e

# Get the project root directory
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TESTS_DIR="${PROJECT_ROOT}/tests"
BUILD_DIR="${PROJECT_ROOT}/build/tests"
COVERAGE_DIR="${PROJECT_ROOT}/coverage"

# Create directories if they don't exist
mkdir -p "${BUILD_DIR}"
mkdir -p "${COVERAGE_DIR}"

# Check if a specific test file is specified
if [ -n "${TEST_FILE}" ]; then
  TEST_PATH="${TESTS_DIR}/${TEST_FILE}"
  
  if [ ! -f "${TEST_PATH}" ]; then
    echo "Error: Test file ${TEST_PATH} not found."
    exit 1
  fi
  
  echo "Running test with coverage: ${TEST_FILE}"
  nim c --passC:"-fprofile-arcs -ftest-coverage" --passL:"-fprofile-arcs -ftest-coverage" -r -o:"${BUILD_DIR}/$(basename "${TEST_FILE}" .nim)" "${TEST_PATH}"
  
  # Generate coverage info
  echo "Generating coverage report..."
  lcov --capture --directory "${PROJECT_ROOT}/nimcache" --output-file "${COVERAGE_DIR}/coverage.info"
  genhtml "${COVERAGE_DIR}/coverage.info" --output-directory "${COVERAGE_DIR}"
else
  # Run all tests with coverage
  echo "Running all tests with coverage..."
  
  # Clean old coverage data
  rm -f "${COVERAGE_DIR}"/*.info
  
  # Run tests with coverage instrumentation
  nim c --passC:"-fprofile-arcs -ftest-coverage" --passL:"-fprofile-arcs -ftest-coverage" -r -o:"${BUILD_DIR}/test_power_assert" "${TESTS_DIR}/test_power_assert.nim"
  nim c --passC:"-fprofile-arcs -ftest-coverage" --passL:"-fprofile-arcs -ftest-coverage" -r -o:"${BUILD_DIR}/test_operators" "${TESTS_DIR}/test_operators.nim"
  nim c --passC:"-fprofile-arcs -ftest-coverage" --passL:"-fprofile-arcs -ftest-coverage" -r -o:"${BUILD_DIR}/test_custom_types" "${TESTS_DIR}/test_custom_types.nim"
  
  # Generate coverage info
  echo "Generating coverage report..."
  lcov --capture --directory "${PROJECT_ROOT}/nimcache" --output-file "${COVERAGE_DIR}/coverage.info"
  genhtml "${COVERAGE_DIR}/coverage.info" --output-directory "${COVERAGE_DIR}"
fi

# Check if coverage should be opened in browser
if [ "${OPEN_COVERAGE}" = "true" ]; then
  echo "Opening coverage report in default browser..."
  
  # Open index.html with the default browser based on the OS
  if [ "$(uname)" = "Darwin" ]; then
    # macOS
    open "${COVERAGE_DIR}/index.html"
  elif [ "$(uname)" = "Linux" ]; then
    # Linux
    if command -v xdg-open >/dev/null 2>&1; then
      xdg-open "${COVERAGE_DIR}/index.html"
    else
      echo "Warning: xdg-open not found. Please open coverage report manually."
    fi
  else
    # Other OS
    echo "Coverage report generated, but auto-open not supported on this OS."
    echo "Please open ${COVERAGE_DIR}/index.html manually."
  fi
fi

echo "Coverage reporting completed successfully."