# Process Library

A common process management library for Nim projects, extracted from niuv, nibuild, and nim-debug-adapter.

## Features

- **Platform-independent process execution** - Works on Windows, macOS, and Linux
- **Synchronous and asynchronous execution** - Support for both blocking and non-blocking process execution
- **Timeout support** - Execute processes with configurable timeouts
- **Environment management** - Set custom environment variables for processes
- **Process manager** - Manage multiple processes with IDs
- **Output streaming** - Read process output line by line
- **Shell command integration** - Platform-specific shell command handling
- **Utility functions** - Find executables in PATH, escape shell arguments, etc.

## Installation

```nim
requires "https://github.com/yourusername/nim-libs/process"
```

## Usage

### Basic Command Execution

```nim
import process

# Simple command
let result = runCommand("echo hello")
echo result.output  # "hello\n"
echo result.exitCode  # 0

# Command with working directory
let result2 = runCommand("pwd", workingDir = "/tmp")

# Command with environment variables
let env = createEnvTable(additions = [("MY_VAR", "value")])
let result3 = runCommand("echo $MY_VAR", env = env)
```

### Async Execution

```nim
import asyncdispatch

proc runAsync() {.async.} =
  let result = await runCommandAsync("long-running-command")
  echo result.output

waitFor runAsync()
```

### Timeout Support

```nim
# Kill process after 5 seconds
let result = runCommandWithTimeout("sleep 10", timeout = 5.0)
if result.timedOut:
  echo "Process timed out"
```

### Process Manager

```nim
let pm = newProcessManager()

# Start managed processes
let p1 = pm.startManagedProcess("server", "python -m http.server 8000")
let p2 = pm.startManagedProcess("worker", "nim r worker.nim")

# Get a process by ID
let server = pm.getManagedProcess("server")

# Terminate a specific process
pm.terminateManagedProcess("worker")

# Terminate all processes
pm.terminateAllProcesses()
```

### ProcessOptions

```nim
let opts = ProcessOptions(
  command: "nim",
  args: @["c", "-r", "myfile.nim"],
  workingDir: "/my/project",
  timeout: some(30.0),  # 30 second timeout
  env: createEnvTable([("NIMBLE_DIR", "/custom/nimble")])
)

let result = execute(opts)
```

### Platform Detection

```nim
if isWindows():
  echo "Running on Windows"
elif isMacOS():
  echo "Running on macOS"
elif isLinux():
  echo "Running on Linux"
```

### Shell Utilities

```nim
# Find executable
let nimPath = findExecutableInPath("nim")
if nimPath.len > 0:
  echo "Found Nim at: ", nimPath

# Escape shell arguments
let safe = shellEscape("file with spaces.txt")
runCommand("cat " & safe)
```

### Output Streaming

```nim
let process = startProcessShell("find /usr -name '*.nim'")

# Read output line by line
readProcessOutput(process) do (line: string):
  echo "Found: ", line

discard process.waitForExit()
process.close()
```

## API Reference

### Types

- `ProcessResult` - Result of process execution (exitCode, output, error, timedOut)
- `ProcessOptions` - Options for process execution
- `ProcessManager` - Manager for multiple processes
- `ProcessError` - Base exception type
- `TimeoutError` - Timeout exception type

### Core Functions

- `runCommand(cmd, workingDir, env)` - Run command synchronously
- `runCommandAsync(cmd, workingDir, env)` - Run command asynchronously
- `runCommandWithTimeout(cmd, timeout, workingDir, env)` - Run with timeout
- `execute(opts: ProcessOptions)` - Execute with options
- `executeAsync(opts: ProcessOptions)` - Execute async with options

### Process Management

- `newProcessManager()` - Create process manager
- `startManagedProcess(pm, id, cmd, ...)` - Start managed process
- `getManagedProcess(pm, id)` - Get process by ID
- `terminateManagedProcess(pm, id)` - Terminate by ID
- `terminateAllProcesses(pm)` - Terminate all

### Utilities

- `isWindows()`, `isMacOS()`, `isLinux()` - Platform detection
- `shellEscape(s)` - Escape shell arguments
- `findExecutableInPath(name)` - Find executable in PATH
- `createEnvTable(baseEnv, additions)` - Create environment table
- `getPlatformShellCommand()` - Get shell command for platform

## Examples

See the `examples/` directory for more detailed examples.

## Contributing

Pull requests welcome! Please ensure all tests pass.

## License

MIT