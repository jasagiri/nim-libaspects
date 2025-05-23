## Error handling module for nim-libs
## Provides enhanced error handling utilities and Result type extensions

import std/[strformat, macros, typetraits, asyncdispatch, json]
import results
export results

type
  ErrorSeverity* = enum
    sevDebug = "debug"
    sevInfo = "info"
    sevWarning = "warning"
    sevError = "error"
    sevCritical = "critical"
  
  ErrorCode* = enum
    ecNone = "NONE"
    ecInvalidInput = "INVALID_INPUT"
    ecNotFound = "NOT_FOUND"
    ecPermissionDenied = "PERMISSION_DENIED"
    ecTimeout = "TIMEOUT"
    ecConnectionFailed = "CONNECTION_FAILED"
    ecInternalError = "INTERNAL_ERROR"
    ecNotImplemented = "NOT_IMPLEMENTED"
    ecResourceExhausted = "RESOURCE_EXHAUSTED"
    ecCancelled = "CANCELLED"

  ErrorContext* = object
    code*: ErrorCode
    message*: string
    source*: string
    line*: int
    column*: int
    stackTrace*: seq[string]
    innerError*: ref ErrorContext

  AppError* = object of CatchableError
    context*: ErrorContext
    severity*: ErrorSeverity
    enrichedContext*: JsonNode

# Exception hierarchy
type
  ValidationError* = object of AppError
  NotFoundError* = object of AppError
  PermissionError* = object of AppError
  TimeoutError* = object of AppError
  ConnectionError* = object of AppError
  InternalError* = object of AppError
  NotImplementedError* = object of AppError
  ResourceError* = object of AppError
  CancellationError* = object of AppError

# Error creation helpers
proc newErrorContext*(
  code: ErrorCode,
  message: string,
  source = "",
  line = 0,
  column = 0,
  innerError: ref ErrorContext = nil
): ErrorContext =
  result = ErrorContext(
    code: code,
    message: message,
    source: source,
    line: line,
    column: column,
    stackTrace: @[],
    innerError: innerError
  )
  
  # Capture stack trace
  when defined(debug):
    result.stackTrace = getErrorStackTrace()

proc newAppError*(
  code: ErrorCode,
  message: string,
  source = "",
  line = 0,
  column = 0,
  innerError: ref ErrorContext = nil,
  severity = sevError
): ref AppError =
  result = newException(AppError, message)
  result.context = newErrorContext(code, message, source, line, column, innerError)
  result.severity = severity
  result.enrichedContext = newJObject()

# Specific error constructors
proc newValidationError*(message: string, field = ""): ref ValidationError =
  result = newException(ValidationError, message)
  result.severity = sevError
  result.context = newErrorContext(ecInvalidInput, message, field)
  result.enrichedContext = newJObject()

proc newNotFoundError*(resource: string, id = ""): ref NotFoundError =
  let msg = if id.len > 0: fmt"{resource} with id '{id}' not found"
            else: fmt"{resource} not found"
  result = newException(NotFoundError, msg)
  result.context = newErrorContext(ecNotFound, msg, resource)
  result.severity = sevWarning
  result.enrichedContext = newJObject()

proc newPermissionError*(action: string, resource = ""): ref PermissionError =
  let msg = if resource.len > 0: fmt"Permission denied for {action} on {resource}"
            else: fmt"Permission denied for {action}"
  result = newException(PermissionError, msg)
  result.context = newErrorContext(ecPermissionDenied, msg)
  result.severity = sevError
  result.enrichedContext = newJObject()

proc newTimeoutError*(operation: string, duration = 0.0): ref TimeoutError =
  let msg = if duration > 0: fmt"{operation} timed out after {duration}s"
            else: fmt"{operation} timed out"
  result = newException(TimeoutError, msg)
  result.context = newErrorContext(ecTimeout, msg)
  result.severity = sevError
  result.enrichedContext = newJObject()

proc newConnectionError*(host: string, port = 0, reason = ""): ref ConnectionError =
  var msg = fmt"Failed to connect to {host}"
  if port > 0: msg &= fmt":{port}"
  if reason.len > 0: msg &= fmt": {reason}"
  result = newException(ConnectionError, msg)
  result.context = newErrorContext(ecConnectionFailed, msg)
  result.severity = sevError
  result.enrichedContext = newJObject()

proc newInternalError*(message: string, component = ""): ref InternalError =
  var msg = message
  if component.len > 0: msg = fmt"[{component}] {msg}"
  result = newException(InternalError, msg)
  result.context = newErrorContext(ecInternalError, msg, component)
  result.severity = sevCritical
  result.enrichedContext = newJObject()

proc newNotImplementedError*(feature: string): ref NotImplementedError =
  let msg = fmt"Feature not implemented: {feature}"
  result = newException(NotImplementedError, msg)
  result.context = newErrorContext(ecNotImplemented, msg)
  result.severity = sevWarning
  result.enrichedContext = newJObject()

proc newResourceError*(resource: string, reason = ""): ref ResourceError =
  var msg = fmt"Resource exhausted: {resource}"
  if reason.len > 0: msg &= fmt" ({reason})"
  result = newException(ResourceError, msg)
  result.context = newErrorContext(ecResourceExhausted, msg)
  result.severity = sevCritical
  result.enrichedContext = newJObject()

proc newCancellationError*(operation: string): ref CancellationError =
  let msg = fmt"Operation cancelled: {operation}"
  result = newException(CancellationError, msg)
  result.context = newErrorContext(ecCancelled, msg)
  result.severity = sevInfo
  result.enrichedContext = newJObject()

# Result type extensions
type
  ResultEx*[T, E] = Result[T, E]

# Helper to convert exceptions to results
proc capture*[T](body: proc(): T): Result[T, ref CatchableError] =
  try:
    Result[T, ref CatchableError].ok(body())
  except CatchableError as e:
    Result[T, ref CatchableError].err(e)

proc captureAsync*[T](body: proc(): Future[T]): Future[Result[T, ref CatchableError]] {.async.} =
  try:
    let value = await body()
    return Result[T, ref CatchableError].ok(value)
  except CatchableError as e:
    return Result[T, ref CatchableError].err(e)

# Chain operations on results
proc mapResult*[T, E, U](self: Result[T, E], transform: proc(val: T): U): Result[U, E] =
  if self.isOk:
    Result[U, E].ok(transform(self.get()))
  else:
    Result[U, E].err(self.error())

proc flatMapResult*[T, E, U](self: Result[T, E], transform: proc(val: T): Result[U, E]): Result[U, E] =
  if self.isOk:
    transform(self.get())
  else:
    Result[U, E].err(self.error())

proc mapErrResult*[T, E, F](self: Result[T, E], transform: proc(err: E): F): Result[T, F] =
  if self.isOk:
    Result[T, F].ok(self.get())
  else:
    Result[T, F].err(transform(self.error()))

proc recoverResult*[T, E](self: Result[T, E], fallback: T): T =
  if self.isOk:
    self.get()
  else:
    fallback

proc recoverWithResult*[T, E](self: Result[T, E], fallback: proc(err: E): T): T =
  if self.isOk:
    self.get()
  else:
    fallback(self.error())

# Combine multiple results
proc combineResults*[T, E](results: varargs[Result[T, E]]): Result[seq[T], E] =
  var values: seq[T] = @[]
  for r in results:
    if r.isErr:
      return Result[seq[T], E].err(r.error())
    values.add(r.get())
  Result[seq[T], E].ok(values)

proc combineWithResult*[T, E, U](
  results: varargs[Result[T, E]],
  transform: proc(values: seq[T]): U
): Result[U, E] =
  let combined = combineResults(results)
  if combined.isOk:
    Result[U, E].ok(transform(combined.get()))
  else:
    Result[U, E].err(combined.error())

# Error chaining utilities
proc withContextResult*[T, E](
  self: Result[T, E],
  context: proc(err: E): E
): Result[T, E] =
  if self.isErr:
    Result[T, E].err(context(self.error()))
  else:
    self

proc addContext*(err: ref AppError, key: string, value: string): ref AppError =
  # In a real implementation, this would add metadata to the error
  err.msg &= fmt" [{key}={value}]"
  result = err

# Validation utilities
type
  ValidationResult*[T] = Result[T, seq[string]]

proc validate*[T](value: T, validators: varargs[proc(val: T): Result[void, string]]): ValidationResult[T] =
  var errors: seq[string] = @[]
  for validator in validators:
    let res = validator(value)
    if res.isErr:
      errors.add(res.error())
  
  if errors.len > 0:
    Result[T, seq[string]].err(errors)
  else:
    Result[T, seq[string]].ok(value)

# String formatting for errors
proc `$`*(err: ErrorContext): string =
  result = fmt"[{err.code}] {err.message}"
  if err.source.len > 0:
    result &= fmt" at {err.source}"
    if err.line > 0:
      result &= fmt":{err.line}"
      if err.column > 0:
        result &= fmt":{err.column}"
  if err.innerError != nil:
    result &= fmt"\n  Caused by: {err.innerError[]}"

proc `$`*(err: ref AppError): string =
  result = err.msg
  if err.context.code != ecNone:
    result &= fmt" [{err.context.code}]"

# Utility macros for error handling
macro tryExpr*(body: untyped): untyped =
  ## Convert an expression that might raise to a Result
  result = quote do:
    capture(proc(): auto = `body`)

macro assertOk*(expr: untyped, msg = ""): untyped =
  ## Assert that a Result is Ok, otherwise raise
  let msgLit = if msg.len > 0: msg else: newLit(fmt"Result is not Ok: {expr.repr}")
  result = quote do:
    let res = `expr`
    if res.isErr:
      raise newException(AssertionDefect, `msgLit` & ": " & $res.error())
    res.get()

# Stack trace utilities
proc getErrorStackTrace*(): seq[string] =
  when defined(debug):
    try:
      raise newException(CatchableError, "Stack trace")
    except:
      return @[getCurrentExceptionMsg()]
  else:
    return @[]

proc formatStackTrace*(trace: seq[string]): string =
  result = "Stack trace:\n"
  for i, line in trace:
    result &= fmt"  {i}: {line}\n"