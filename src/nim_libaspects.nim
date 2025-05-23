## nim-libaspects - Shared aspect libraries for Nim development tools
## This module serves as the main entry point for all shared functionality

# Re-export all submodules for convenience
import nim_libaspects/transport
import nim_libaspects/config  
import nim_libaspects/config_extended
import nim_libaspects/parallel
import nim_libaspects/logging
import nim_libaspects/errors
import nim_libaspects/process
import nim_libaspects/testing
import nim_libaspects/metrics
import nim_libaspects/reporting
import nim_libaspects/events
import nim_libaspects/logging_metrics
import nim_libaspects/notifications
import nim_libaspects/monitoring
import nim_libaspects/cache
import nim_libaspects/profiler
import nim_libaspects/benchmark
import nim_libaspects/memory_optimizer
import nim_libaspects/error_handler_advanced
# import nim_libaspects/fs       # TODO: Implement

export transport, config, config_extended, parallel, logging, errors, process, testing, metrics, reporting, events, logging_metrics, notifications, monitoring, cache, profiler, benchmark, memory_optimizer, error_handler_advanced  # , fs

# Version information
const NimLibAspectsVersion* = "0.1.0"

when isMainModule:
  echo "nim-libaspects version ", NimLibAspectsVersion
  echo "Available modules:"
  echo "  - transport: Protocol communication (stdio, socket)"
  echo "  - config: Configuration management (JSON, TOML, env)"
  echo "  - parallel: Task execution and dependency management"
  echo "  - logging: Structured logging with multiple handlers"
  echo "  - errors: Enhanced error handling and Result types"
  echo "  - process: Process spawning and management"
  echo "  - testing: Test framework with assertions and runners"
  echo "  - metrics: Metrics collection framework (counters, gauges, histograms)"
  echo "  - reporting: Report generation and formatting framework"
  echo "  - events: Event-driven architecture (EventBus, publish/subscribe)"
  echo "  - logging_metrics: Integration between logging and metrics"
  echo "  - notifications: Multi-channel notification system"
  echo "  - monitoring: Comprehensive monitoring system (health checks, resources, alerts)"
  echo "  - cache: Generic caching with TTL, eviction policies, and statistics"
  echo "  - config_extended: Extended configuration with validation, encryption, environments, overlays"
  echo "  - profiler: Performance profiler with CPU and memory tracking"
  echo "  - benchmark: Benchmarking framework with comparison and reporting"
  echo "  - memory_optimizer: Memory optimization utilities (pools, tracking, weak refs)"
  echo "  - error_handler_advanced: Advanced error handling (aggregation, classification, recovery)"
  echo "  - fs: File system utilities and watching (TODO)"