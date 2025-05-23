# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Common Development Commands

### Building
```bash
# Build the library and documentation
nimble buildLib

# Build everything including binaries
nimble build

# Clean build artifacts
nimble clean
```

### Testing
```bash
# Run all tests
nimble test
# or directly:
nim c -r tests/test_all

# Run specific module tests
nim c -r tests/test_logging
nim c -r tests/test_errors
nim c -r tests/test_config
# etc. (pattern: test_<module>)

# Run tests with coverage
nimble coverage

# Run benchmarks
nimble bench
```

### Documentation
```bash
# Generate documentation
nimble docs
```

### CI Workflow
```bash
# Run full CI pipeline (clean, build, test)
nimble ci
```

## High-Level Architecture

### Module Organization
The project follows a modular architecture where each aspect (logging, errors, config, etc.) is implemented as an independent module. All modules are located in `src/nim_libaspects/` and are re-exported through the main `src/nim_libaspects.nim` file.

### Core Design Patterns

1. **Error Handling**: All modules use `Result[T,E]` types from the `results` package for safe error handling instead of exceptions. Error types inherit from `AppError` base type.

2. **Extensibility**: Modules use ref object inheritance for extensibility. Examples:
   - `LogHandler` base with `ConsoleHandler`, `FileHandler` implementations
   - `Transport` base with `StdioTransport`, `SocketTransport`, `ServerTransport`
   - `TestReporter` base with `ConsoleReporter`, `JsonReporter`, `HtmlReporter`

3. **Thread Safety**: Modules that need concurrent access use explicit locks (e.g., metrics, events). Procedures are marked with `{.gcsafe.}` pragma where appropriate.

4. **Async Operations**: I/O-heavy modules (transport, events, notifications) use async/await patterns with the `asyncdispatch` module.

### Module Dependencies
- `errors` module is the foundation used by all other modules
- `logging` is used by transport and monitoring modules
- `metrics` and `events` are used by the monitoring module
- `logging_metrics` bridges logging and metrics modules
- Most other modules are standalone with minimal dependencies

### Testing Strategy
- Each module has corresponding unit tests (`test_<module>.nim`)
- Integration tests verify module interactions
- Coverage tests ensure comprehensive testing
- All tests are aggregated in `test_all.nim`
- Tests use BDD-style organization with Given/When/Then comments

### Build Configuration
- Output goes to `build/` directory (binaries in `build/bin/`, libs in `build/lib/`)
- Cross-platform build scripts in `scripts/` directory
- `nim.cfg` sets common paths and compilation options
- Library can be compiled as `.so` (Linux/Mac) or `.dll` (Windows)

### Key Modules Overview

- **errors**: Result types, error hierarchy, validation utilities
- **logging**: Structured logging with handlers and formatters
- **config**: Cascading configuration from files, env vars, CLI (enhanced with nim-lang-core file analysis)
- **transport**: Protocol communication (LSP/DAP) over stdio/sockets
- **parallel**: Task execution with dependencies and scheduling
- **process**: Cross-platform process spawning and management
- **testing**: Test framework with assertions, runners, and reporters (enhanced with nim-lang-core AST analysis)
- **metrics**: Performance metrics collection (counters, gauges, histograms)
- **events**: Event bus with pub/sub, filtering, and persistence
- **monitoring**: Health checks, alerts, and system monitoring
- **notifications**: Multi-channel notifications (email, Slack, webhooks)
- **profiler**: Performance profiling with AI-powered optimization suggestions (uses nim-lang-core)
- **cache**: Comprehensive caching with nim-lang-core AST cache integration

### nim-lang-core Integration

This project integrates with nim-lang-core to provide enhanced functionality:

1. **AST Analysis**: Testing, profiler, and config modules use nim-lang-core's AST parsing
2. **AI Pattern Detection**: Automatic detection of code patterns and anti-patterns
3. **Symbol Analysis**: Enhanced code analysis for profiling and optimization
4. **Cache Infrastructure**: Cache module can leverage nim-lang-core's optimized AST cache

To use nim-lang-core features, ensure nim-lang-core is available at `../nim-lang-core` relative to this project.