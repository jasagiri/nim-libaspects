import ../src/process
import std/[os, asyncdispatch]

# Example 1: Basic command execution
echo "=== Basic Command Execution ==="
let result = runCommand("echo Hello, World!")
echo "Exit code: ", result.exitCode
echo "Output: ", result.output
echo ""

# Example 2: Command with custom working directory
echo "=== Working Directory Example ==="
let tempDir = getTempDir()
let pwdResult = runCommand("pwd", workingDir = tempDir)
echo "Current directory: ", pwdResult.output.strip()
echo ""

# Example 3: Command with environment variables
echo "=== Environment Variables Example ==="
let env = createEnvTable(additions = [
  ("MY_NAME", "Nim User"),
  ("MY_LANG", "Nim")
])
let envResult = runCommand("echo Hello $MY_NAME, you're using $MY_LANG!", env = env)
echo envResult.output
echo ""

# Example 4: Command with timeout
echo "=== Timeout Example ==="
echo "Running command with 1 second timeout..."
let timeoutResult = runCommandWithTimeout("sleep 3", timeout = 1.0)
if timeoutResult.timedOut:
  echo "Command timed out as expected"
else:
  echo "Command completed (unexpected)"
echo ""

# Example 5: Async command execution
echo "=== Async Execution Example ==="
proc runAsyncExample() {.async.} =
  echo "Starting async command..."
  let asyncResult = await runCommandAsync("echo Async execution complete")
  echo "Async result: ", asyncResult.output.strip()

waitFor runAsyncExample()
echo ""

# Example 6: Process manager
echo "=== Process Manager Example ==="
let pm = newProcessManager()

# Start a simple HTTP server (if Python is available)
let pythonPath = findExecutableInPath("python3")
if pythonPath.len > 0:
  echo "Starting HTTP server..."
  let serverProcess = pm.startManagedProcess("http_server", 
    "python3 -m http.server 8888")
  
  # Give it a moment to start
  sleep(1000)
  
  echo "Server started with PID: ", serverProcess.processID
  echo "Stopping server..."
  discard pm.terminateManagedProcess("http_server")
  echo "Server stopped"
else:
  echo "Python not found, skipping HTTP server example"
echo ""

# Example 7: Using ProcessOptions
echo "=== ProcessOptions Example ==="
let opts = ProcessOptions(
  command: "echo",
  args: @["Using", "ProcessOptions", "with", "multiple", "args"],
  workingDir: "",
  env: nil,
  timeout: none[float]()
)

let optsResult = execute(opts)
echo "Result: ", optsResult.output.strip()
echo ""

# Example 8: Platform detection
echo "=== Platform Detection ==="
echo "Current platform:"
if isWindows():
  echo "  Windows"
elif isMacOS():
  echo "  macOS"
elif isLinux():
  echo "  Linux"
else:
  echo "  Unknown"
echo ""

# Example 9: Shell escape
echo "=== Shell Escape Example ==="
let filename = "file with spaces.txt"
let escaped = shellEscape(filename)
echo "Original: ", filename
echo "Escaped: ", escaped

# Create a test file and use escaped name
let testFile = getTempDir() / filename
writeFile(testFile, "test content")
let catResult = runCommand("cat " & shellEscape(testFile))
echo "File content: ", catResult.output
removeFile(testFile)
echo ""

# Example 10: Find executable
echo "=== Find Executable Example ==="
let nimPath = findExecutableInPath("nim")
if nimPath.len > 0:
  echo "Found Nim at: ", nimPath
else:
  echo "Nim not found in PATH"