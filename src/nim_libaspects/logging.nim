## Logging module for nim-libs
## Provides structured logging with multiple handlers and formatters

import std/[times, strformat, strutils, terminal]
import std/json
import results

type
  LogLevel* = enum
    lvlDebug = "DEBUG"
    lvlInfo = "INFO"
    lvlWarn = "WARN"
    lvlError = "ERROR"
    lvlFatal = "FATAL"

  LogRecord* = object
    level*: LogLevel
    message*: string
    timestamp*: DateTime
    module*: string
    fields*: JsonNode

  LogHandler* = ref object of RootObj

  LogFormatter* = ref object of RootObj

  Logger* = ref object
    level*: LogLevel
    handlers*: seq[LogHandler]
    formatter*: LogFormatter
    module*: string

  ConsoleHandler* = ref object of LogHandler
    useColors*: bool
    stream*: File

  FileHandler* = ref object of LogHandler
    filename*: string
    file*: File

  TextFormatter* = ref object of LogFormatter
    format*: string

  JsonFormatter* = ref object of LogFormatter
    pretty*: bool

# Forward declarations
method format*(self: LogFormatter, record: LogRecord): string {.base.} =
  raise newException(CatchableError, "Not implemented")

method handle*(self: LogHandler, record: LogRecord) {.base.} =
  raise newException(CatchableError, "Not implemented")

# Default global logger
var defaultLogger* = Logger(
  level: lvlInfo,
  handlers: @[],
  formatter: nil,
  module: "root"
)

proc compareLogLevels*(a, b: LogLevel): int =
  ## Compare two log levels for severity
  ord(a) - ord(b)

proc `<=`*(a, b: LogLevel): bool =
  compareLogLevels(a, b) <= 0

proc `>=`*(a, b: LogLevel): bool =
  compareLogLevels(a, b) >= 0

proc parseLogLevel*(level: string): Result[LogLevel, string] =
  ## Parse string to LogLevel
  case level.toLowerAscii()
  of "debug": ok(lvlDebug)
  of "info": ok(lvlInfo)
  of "warn", "warning": ok(lvlWarn)
  of "error": ok(lvlError)
  of "fatal": ok(lvlFatal)
  else: err(fmt"Unknown log level: {level}")

# TextFormatter implementation
proc newTextFormatter*(format = "{timestamp} [{level}] {module}: {message}"): TextFormatter =
  TextFormatter(format: format)

method format*(self: TextFormatter, record: LogRecord): string =
  result = self.format
  result = result.replace("{timestamp}", $record.timestamp)
  result = result.replace("{level}", $record.level)
  result = result.replace("{module}", record.module)
  result = result.replace("{message}", record.message)
  
  if record.fields != nil and record.fields.len > 0:
    var fields: seq[string]
    for key, value in record.fields:
      fields.add(fmt"{key}={value}")
    if fields.len > 0:
      result &= " " & fields.join(" ")

# JsonFormatter implementation
proc newJsonFormatter*(pretty = false): JsonFormatter =
  JsonFormatter(pretty: pretty)

method format*(self: JsonFormatter, record: LogRecord): string =
  var json = %*{
    "timestamp": $record.timestamp,
    "level": $record.level,
    "module": record.module,
    "message": record.message
  }
  
  if record.fields != nil:
    json["fields"] = record.fields
  
  if self.pretty:
    result = json.pretty()
  else:
    result = $json

# ConsoleHandler implementation
proc newConsoleHandler*(stream = stdout, useColors = true): ConsoleHandler =
  ConsoleHandler(stream: stream, useColors: useColors)

method handle*(self: ConsoleHandler, record: LogRecord) =
  let formatter = defaultLogger.formatter
  if formatter == nil:
    return
    
  let message = formatter.format(record)
  
  if self.useColors and isatty(self.stream):
    case record.level
    of lvlDebug: self.stream.styledWrite(fgCyan, message)
    of lvlInfo: self.stream.write(message)
    of lvlWarn: self.stream.styledWrite(fgYellow, message)
    of lvlError: self.stream.styledWrite(fgRed, message)
    of lvlFatal: self.stream.styledWrite(fgRed, styleBright, message)
  else:
    self.stream.write(message)
  
  self.stream.write("\n")
  self.stream.flushFile()

# FileHandler implementation
proc newFileHandler*(filename: string): Result[FileHandler, string] =
  try:
    let file = open(filename, fmAppend)
    ok(FileHandler(filename: filename, file: file))
  except IOError as e:
    err(e.msg)

method handle*(self: FileHandler, record: LogRecord) =
  let formatter = defaultLogger.formatter
  if formatter == nil:
    return
    
  let message = formatter.format(record)
  self.file.writeLine(message)
  self.file.flushFile()

proc close*(self: FileHandler) =
  if self.file != nil:
    self.file.close()

# Logger implementation
proc newLogger*(module = "root", level = lvlInfo): Logger =
  Logger(
    level: level,
    handlers: @[],
    formatter: newTextFormatter(),
    module: module
  )

proc addHandler*(self: Logger, handler: LogHandler) =
  self.handlers.add(handler)

proc setFormatter*(self: Logger, formatter: LogFormatter) =
  self.formatter = formatter

proc setLevel*(self: Logger, level: LogLevel) =
  self.level = level

proc log*(self: Logger, level: LogLevel, message: string, fields: JsonNode = nil) =
  if level < self.level:
    return
    
  let record = LogRecord(
    level: level,
    message: message,
    timestamp: now(),
    module: self.module,
    fields: fields
  )
  
  for handler in self.handlers:
    handler.handle(record)

proc debug*(self: Logger, message: string, fields: JsonNode = nil) =
  self.log(lvlDebug, message, fields)

proc info*(self: Logger, message: string, fields: JsonNode = nil) =
  self.log(lvlInfo, message, fields)

proc warn*(self: Logger, message: string, fields: JsonNode = nil) =
  self.log(lvlWarn, message, fields)

proc error*(self: Logger, message: string, fields: JsonNode = nil) =
  self.log(lvlError, message, fields)

proc fatal*(self: Logger, message: string, fields: JsonNode = nil) =
  self.log(lvlFatal, message, fields)

# Module-level convenience functions that use default logger
proc debug*(message: string, fields: JsonNode = nil) =
  defaultLogger.debug(message, fields)

proc info*(message: string, fields: JsonNode = nil) =
  defaultLogger.info(message, fields)

proc warn*(message: string, fields: JsonNode = nil) =
  defaultLogger.warn(message, fields)

proc error*(message: string, fields: JsonNode = nil) =
  defaultLogger.error(message, fields)

proc fatal*(message: string, fields: JsonNode = nil) =
  defaultLogger.fatal(message, fields)

# Initialize default logger with console handler
proc initDefaultLogger*() =
  defaultLogger = newLogger()
  defaultLogger.addHandler(newConsoleHandler())
  defaultLogger.setFormatter(newTextFormatter())

# Call init on module load
initDefaultLogger()