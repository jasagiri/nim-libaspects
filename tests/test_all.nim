## Runs all tests for nim-libaspects modules

import unittest

# Import all test modules
import test_errors
import test_logging
import test_config
import test_transport
import test_parallel
import test_process
import test_testing

# New test modules
import test_metrics
import test_metrics_coverage

# Run all tests
when isMainModule:
  echo "Running all nim-libaspects tests..."
  # Tests are automatically run when importing the modules