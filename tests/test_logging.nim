import unittest
import ../src/nim_libaspects/logging
import std/[json, tempfiles, os, times, strutils]
import results

# Test handlers need to be at top level
type TestHandler = ref object of LogHandler
  messages*: ptr seq[string]

proc newTestHandler(messages: ptr seq[string]): TestHandler =
  TestHandler(messages: messages)

method handle(self: TestHandler, record: LogRecord) =
  let formatter = defaultLogger.formatter
  if formatter != nil:
    self.messages[].add(formatter.format(record))

suite "Logging Module Tests":
  test "Log level parsing":
    check parseLogLevel("debug").get() == lvlDebug
    check parseLogLevel("info").get() == lvlInfo
    check parseLogLevel("warn").get() == lvlWarn
    check parseLogLevel("error").get() == lvlError
    check parseLogLevel("fatal").get() == lvlFatal
    check parseLogLevel("invalid").isErr()
  
  test "Log level comparison":
    check lvlDebug < lvlInfo
    check lvlInfo < lvlWarn
    check lvlWarn < lvlError
    check lvlError < lvlFatal
    check lvlDebug <= lvlDebug
    check lvlFatal >= lvlError
  
  test "Text formatter":
    let formatter = newTextFormatter()
    let record = LogRecord(
      level: lvlInfo,
      message: "Test message",
      timestamp: now(),
      module: "test",
      fields: nil
    )
    let formatted = formatter.format(record)
    check "INFO" in formatted
    check "test" in formatted
    check "Test message" in formatted
  
  test "Text formatter with fields":
    let formatter = newTextFormatter()
    let fields = %*{"user": "john", "action": "login"}
    let record = LogRecord(
      level: lvlInfo,
      message: "User action",
      timestamp: now(),
      module: "auth",
      fields: fields
    )
    let formatted = formatter.format(record)
    check "user=" in formatted
    check "action=" in formatted
  
  test "JSON formatter":
    let formatter = newJsonFormatter()
    let record = LogRecord(
      level: lvlWarn,
      message: "Warning message",
      timestamp: now(),
      module: "system",
      fields: nil
    )
    let formatted = formatter.format(record)
    let json = parseJson(formatted)
    check json["level"].getStr() == "WARN"
    check json["module"].getStr() == "system"
    check json["message"].getStr() == "Warning message"
  
  test "JSON formatter pretty":
    let formatter = newJsonFormatter(pretty = true)
    let record = LogRecord(
      level: lvlError,
      message: "Error occurred",
      timestamp: now(),
      module: "app",
      fields: nil
    )
    let formatted = formatter.format(record)
    check "\n" in formatted  # Pretty printing includes newlines
  
  test "Console handler":
    # Create a temporary file to use as output
    let (file, path) = createTempFile("test_console_", ".log")
    defer: 
      file.close()
      removeFile(path)
    
    let handler = newConsoleHandler(stream = file, useColors = false)
    let formatter = newTextFormatter("{level}: {message}")
    defaultLogger.setFormatter(formatter)
    
    let record = LogRecord(
      level: lvlInfo,
      message: "Test console output",
      timestamp: now(),
      module: "test",
      fields: nil
    )
    handler.handle(record)
    
    # Read back the content
    file.flushFile()
    let content = readFile(path)
    check "INFO: Test console output" in content
  
  test "File handler":
    let (_, path) = createTempFile("test_file_", ".log")
    defer: removeFile(path)
    
    let handlerResult = newFileHandler(path)
    check handlerResult.isOk()
    
    let handler = handlerResult.get()
    defer: handler.close()
    
    let formatter = newTextFormatter("{level}: {message}")
    defaultLogger.setFormatter(formatter)
    
    let record = LogRecord(
      level: lvlError,
      message: "Test file output",
      timestamp: now(),
      module: "test",
      fields: nil
    )
    handler.handle(record)
    
    # Read back the content
    let content = readFile(path)
    check "ERROR: Test file output" in content
  
  test "Logger creation and configuration":
    let logger = newLogger(module = "myapp", level = lvlWarn)
    check logger.module == "myapp"
    check logger.level == lvlWarn
    
    logger.setLevel(lvlDebug)
    check logger.level == lvlDebug
  
  test "Logger filtering by level":
    let logger = newLogger(level = lvlWarn)
    
    # Create a test handler that captures messages
    var capturedMessages: seq[string] = @[]
    
    let handler = newTestHandler(addr capturedMessages)
    logger.addHandler(handler)
    logger.setFormatter(newTextFormatter("{level}: {message}"))
    
    # These should not be logged (below threshold)
    logger.debug("Debug message")
    logger.info("Info message")
    
    # These should be logged
    logger.warn("Warning message")
    logger.error("Error message")
    logger.fatal("Fatal message")
    
    check capturedMessages.len == 3
    check "WARN: Warning message" in capturedMessages[0]
    check "ERROR: Error message" in capturedMessages[1]
    check "FATAL: Fatal message" in capturedMessages[2]
  
  test "Logger with fields":
    let logger = newLogger()
    
    # Create a test handler that captures messages
    var capturedMessages: seq[string] = @[]
    
    let handler = newTestHandler(addr capturedMessages)
    logger.addHandler(handler)
    logger.setFormatter(newTextFormatter("{level}: {message}"))
    
    let fields = %*{"request_id": "12345", "user_id": 42}
    logger.info("User login", fields)
    
    check capturedMessages.len == 1
    check "request_id=\"12345\"" in capturedMessages[0]
    check "user_id=42" in capturedMessages[0]
  
  test "Module-level convenience functions":
    # These use the default logger
    # Just ensure they don't crash
    debug("Debug message")
    info("Info message")
    warn("Warning message")
    error("Error message")
    
    let fields = %*{"test": true}
    info("With fields", fields)