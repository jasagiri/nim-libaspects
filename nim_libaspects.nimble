# Package

version       = "0.1.0"
author        = "PaaS-nibuild Team"
description   = "Shared aspect libraries for Nim development tools"
license       = "MIT"
srcDir        = "src"
installExt    = @["nim"]

# Dependencies

requires "nim >= 2.0.0"
requires "results >= 0.5.0"
requires "parsetoml >= 0.7.2"
# requires "../nim-lang-core"  # Local dependency - uncomment when nim-lang-core is installed
binDir        = "build/bin"

# Tasks

task test, "Run all tests":
  exec "nim c -r tests/test_all"

task docs, "Generate documentation":
  exec "nim doc --project --outdir:docs src/nim_libaspects.nim"

task clean, "Clean build artifacts":
  exec "rm -rf build"
  exec "find . -name \"*.o\" -type f -delete"
  exec "find . -name \"nimcache\" -type d -exec rm -rf {} +;"
  exec "find tests -type f -executable -delete"





task buildLib, "Build the library files and documentation":
  # Create output directories
  exec "mkdir -p build/lib build/bin"

  # Compile the library files
  echo "Building nim_libaspects library..."
  when defined(windows):
    exec "nim c --app:lib -d:release --out:build/lib/nim_libaspects.dll src/nim_libaspects.nim"
  else:
    exec "nim c --app:lib -d:release --out:build/lib/libnim_libaspects.so src/nim_libaspects.nim"

  # Move any binary created in the root directory to build/bin
  echo "Moving binaries to build/bin directory..."
  when defined(windows):
    exec "cmd /c if exist nim_libaspects.exe move nim_libaspects.exe build\\bin\\"
  else:
    exec "[ -f ./nim_libaspects ] && mv ./nim_libaspects build/bin/ || true"

  # Also generate documentation
  echo "Generating documentation..."
  exec "mkdir -p build/doc"
  exec "nim doc --project --index:on --outdir:build/doc src/nim_libaspects.nim"

  echo "Build completed successfully"

# Custom build task that ensures binaries go to build/bin directory
task build, "Build the package and ensure binaries go to build/bin":
  # Create bin directory first
  exec "mkdir -p build/bin"

  # Clean root directory of binaries first
  when defined(windows):
    exec "cmd /c if exist nim_libaspects.exe del nim_libaspects.exe"
  else:
    exec "rm -f ./nim_libaspects"

  # Use nimble install with --nolinks to build without creating symlinks
  # This will use the binDir setting defined above
  exec "nimble install --nolinks"

  # Run the buildLib task for library files
  exec "nimble buildLib"

  # Verify binary placement and clean root if needed
  echo "Verifying binary placement..."
  when defined(windows):
    exec "cmd /c if exist nim_libaspects.exe (echo Binary in root directory && move nim_libaspects.exe build\\bin\\) else (echo Binary correctly placed in build/bin)"
  else:
    exec "if [ -f ./nim_libaspects ]; then echo 'Binary in root directory' && mv ./nim_libaspects build/bin/; else echo 'Binary correctly placed in build/bin'; fi"



task bench, "Run benchmarks":
  # Create benchmarks directory if it doesn't exist
  exec "mkdir -p build/benchmarks"

  # Run benchmark directly
  when defined(windows):
    exec "nim c -r -o:build/benchmarks/bench_nim_libaspects benchmarks/bench_nim_libaspects.nim"
  else:
    exec "nim c -r -o:build/benchmarks/bench_nim_libaspects benchmarks/bench_nim_libaspects.nim"

task coverage, "Generate test coverage report":
  # Create coverage directory
  exec "mkdir -p build/coverage"

  echo "Generating coverage report..."

  # Check if we're on macOS with Apple Silicon, which has known issues with gcov
  let isAppleSilicon = gorgeEx("uname -sm").output.contains("Darwin arm64")
  let forceRun = existsEnv("FORCE_COVERAGE") or existsEnv("BYPASS_PLATFORM_CHECK")

  if isAppleSilicon and not forceRun:
    echo "⚠️ Detected macOS on Apple Silicon (M1/M2)"
    echo """
Coverage generation on Apple Silicon Macs has known compatibility issues.

Recommended alternatives:
1. Run a simplified test coverage without detailed reports:
   nim c -r --passC:-fprofile-arcs --passC:-ftest-coverage --passL:-lgcov tests/test_all.nim

2. Install and use LLVM tools (may still have compatibility issues):
   brew install llvm lcov
   export PATH="$(brew --prefix llvm)/bin:$PATH"

3. For the most reliable results, use Docker with a Linux container:
   docker run --rm -v $(pwd):/src -w /src nimlang/nim:latest \
     bash -c "apt-get update && apt-get install -y lcov && nimble coverage"

4. To bypass this warning and try anyway, run:
   BYPASS_PLATFORM_CHECK=1 nimble coverage
"""
    return

  if isAppleSilicon:
    echo "Note: Bypassing Apple Silicon compatibility warning. This may still fail."

  # Check for required tools
  var missingTools: seq[string] = @[]
  var installInstructions = ""

  when defined(windows):
    # Windows tool check
    try:
      let gcovOutput = staticExec("where gcov 2>&1")
      if not gcovOutput.contains("gcov"):
        missingTools.add("gcov")
        installInstructions.add("\n  - gcov: Install MinGW-w64 or use Windows Subsystem for Linux (WSL)")
    except:
      missingTools.add("gcov")
      installInstructions.add("\n  - gcov: Install MinGW-w64 or use Windows Subsystem for Linux (WSL)")
  else:
    # Unix tool check
    if staticExec("which gcov 2>/dev/null || echo notfound") == "notfound":
      missingTools.add("gcov")

    if staticExec("which lcov 2>/dev/null || echo notfound") == "notfound":
      missingTools.add("lcov")

    if staticExec("which genhtml 2>/dev/null || echo notfound") == "notfound":
      missingTools.add("genhtml")

    # Add installation instructions based on platform
    if missingTools.len > 0:
      if staticExec("uname") == "Darwin":
        # macOS instructions
        installInstructions.add("\nOn macOS, install the missing tools with Homebrew:\n")
        installInstructions.add("  brew install lcov\n")
        installInstructions.add("\nNote: For gcov support, you need to install GCC instead of using Apple's clang:\n")
        installInstructions.add("  brew install gcc\n")
        installInstructions.add("  export CC=gcc-13  # Or your installed GCC version\n")
      elif staticExec("uname") == "Linux":
        # Linux instructions
        installInstructions.add("\nOn Linux, install the missing tools with your package manager:\n")
        installInstructions.add("  # Debian/Ubuntu:\n")
        installInstructions.add("  sudo apt-get install gcc lcov\n\n")
        installInstructions.add("  # Fedora/RHEL/CentOS:\n")
        installInstructions.add("  sudo dnf install gcc lcov\n")

  # Check if we have missing tools and print installation instructions
  if missingTools.len > 0:
    echo "⚠️ Missing required tools for coverage generation: ", missingTools.join(", ")
    echo installInstructions
    echo "\nSkipping coverage generation. Install the required tools and try again."
    return

  # Try to test for libgcov without running the full compilation
  let testCompileResult = gorgeEx("nim c --verbosity:0 --hint[Processing]:off " &
                                "--passC:-fprofile-arcs --passC:-ftest-coverage " &
                                "--passL:-lgcov -e'quit(0)' 2>&1")

  # If we have an error with libgcov, display instructions
  if testCompileResult.exitCode != 0 and testCompileResult.output.contains("library not found for -lgcov"):
    echo "⚠️ Compiler error: libgcov not found"

    if staticExec("uname") == "Darwin":
      echo """
On macOS, Apple's Clang doesn't include libgcov. You need GCC instead:

1. Install GCC via Homebrew:
   brew install gcc

2. Set environment variables to use GCC:
   export CC=gcc-13  # Use the version you installed
   export PATH="/usr/local/bin:$PATH"

3. Run coverage again:
   nimble coverage

Alternative: Use a simplified approach without lcov HTML reports:
  nim c -r tests/test_all.nim
"""
    elif staticExec("uname") == "Linux":
      echo """
On Linux, you need to install gcc with coverage support:

# For Debian/Ubuntu:
sudo apt-get install gcc lcov

# For Fedora/RHEL/CentOS:
sudo dnf install gcc lcov
"""
    return

  # If we got here, attempt to run coverage
  when defined(windows):
    # Windows coverage command
    try:
      exec "nim c -r --passC:-fprofile-arcs --passC:-ftest-coverage --passL:-lgcov tests/test_all.nim"
      exec "gcov -o nimcache src/*.nim || echo '⚠️ gcov failed. Check if you have the correct version.'"
    except:
      echo "⚠️ Coverage generation failed on Windows."
      echo "This might be because of missing libgcov. Make sure you have a compatible compiler installed."
  else:
    # Unix coverage command
    try:
      # Run gcc version check to provide in error reports
      let gccVersion = staticExec("gcc --version 2>&1 || clang --version 2>&1 || echo 'No compiler version info available'")

      echo "Compiling tests with coverage instrumentation..."
      exec "nim c -r --passC:-fprofile-arcs --passC:-ftest-coverage --passL:-lgcov tests/test_all.nim"

      echo "Generating coverage data..."
      exec "gcov -o nimcache src/*.nim || echo '⚠️ gcov failed with standard syntax, trying alternative...'"

      # If standard gcov syntax failed, try alternative syntax for different gcov versions
      if staticExec("[ -f src/nim_libaspects.nim.gcov ] && echo 'exists' || echo 'notfound'") == "notfound":
        echo "Trying alternative gcov command..."
        exec "cd nimcache && gcov ../src/*.nim || echo '⚠️ Alternative gcov command also failed.'"

      echo "Processing coverage data with lcov..."
      exec "mkdir -p build/coverage"
      exec "lcov --capture --directory nimcache --output-file build/coverage/coverage.info || echo '⚠️ lcov failed to capture coverage data.'"

      echo "Generating HTML report..."
      exec "genhtml build/coverage/coverage.info --output-directory build/coverage || echo '⚠️ genhtml failed to generate HTML report.'"

      if staticExec("[ -f build/coverage/index.html ] && echo 'exists' || echo 'notfound'") == "exists":
        echo "\n✅ Coverage report generated successfully!"
        echo "View the report by opening build/coverage/index.html in your browser."
      else:
        echo "\n⚠️ Coverage report generation failed to produce output files."
        echo "Your compiler setup may not be compatible with the coverage tools."
        echo "\nCompiler information:"
        echo gccVersion

        echo "\nTry installing GCC instead of using Clang:"
        echo "  brew install gcc"
        echo "  export CC=gcc-13  # Use the version you installed"

        # Provide alternative coverage approach
        echo "\nAlternative: Run tests directly for basic coverage:"
        echo "  nim c -r tests/test_all.nim"
    except:
      echo "⚠️ Coverage generation failed."
      echo "This might be due to incompatible compiler flags or environment."

      # Check for common GCC vs Clang issues
      if staticExec("gcc --version 2>/dev/null || echo notfound") == "notfound":
        echo "\nYou appear to be using Clang, which may not support gcov properly."
        echo "Try installing GCC:"

        if staticExec("uname") == "Darwin":
          echo "  brew install gcc"
          echo "  export CC=gcc-13  # Use the version you installed"
        elif staticExec("uname") == "Linux":
          echo "  sudo apt install gcc  # Debian/Ubuntu"
          echo "  sudo dnf install gcc  # Fedora/RHEL"

task ci, "Run CI workflow (clean, lint, build, test)":
  exec "nimble clean"
  exec "nimble buildLib"
  exec "nimble test"

  # Add optional steps based on environment variables
  if existsEnv("GENERATE_DOCS"):
    exec "nimble docs"

  if existsEnv("GENERATE_COVERAGE"):
    exec "nimble coverage"

  if existsEnv("RUN_BENCHMARKS"):
    exec "nimble bench"
