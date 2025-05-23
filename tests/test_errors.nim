import unittest
import ../src/nim_libaspects/errors
import std/[strformat, strutils]

suite "Error Module Tests":
  test "Error context creation":
    let ctx = newErrorContext(
      ecInvalidInput,
      "Invalid email format",
      "user.nim",
      42,
      15
    )
    check ctx.code == ecInvalidInput
    check ctx.message == "Invalid email format"
    check ctx.source == "user.nim"
    check ctx.line == 42
    check ctx.column == 15
  
  test "App error creation":
    let err = newAppError(ecInternalError, "Database connection failed")
    check err.context.code == ecInternalError
    check err.msg == "Database connection failed"
  
  test "Specific error types":
    # Validation error
    let valErr = newValidationError("Email is required", "email")
    check valErr.context.code == ecInvalidInput
    check "Email is required" in valErr.msg
    
    # Not found error
    let notFoundErr = newNotFoundError("User", "123")
    check notFoundErr.context.code == ecNotFound
    check "User with id '123' not found" in notFoundErr.msg
    
    # Permission error
    let permErr = newPermissionError("delete", "admin panel")
    check permErr.context.code == ecPermissionDenied
    check "Permission denied for delete on admin panel" in permErr.msg
    
    # Timeout error
    let timeoutErr = newTimeoutError("API call", 30.0)
    check timeoutErr.context.code == ecTimeout
    check "API call timed out after 30" in timeoutErr.msg
    
    # Connection error
    let connErr = newConnectionError("localhost", 5432, "Connection refused")
    check connErr.context.code == ecConnectionFailed
    check "Failed to connect to localhost:5432: Connection refused" in connErr.msg
    
    # Internal error
    let intErr = newInternalError("Memory allocation failed", "MemoryManager")
    check intErr.context.code == ecInternalError
    check "[MemoryManager]" in intErr.msg
    
    # Not implemented error
    let notImplErr = newNotImplementedError("async file operations")
    check notImplErr.context.code == ecNotImplemented
    check "Feature not implemented: async file operations" in notImplErr.msg
    
    # Resource error
    let resErr = newResourceError("thread pool", "max threads reached")
    check resErr.context.code == ecResourceExhausted
    check "Resource exhausted: thread pool (max threads reached)" in resErr.msg
    
    # Cancellation error
    let cancelErr = newCancellationError("download task")
    check cancelErr.context.code == ecCancelled
    check "Operation cancelled: download task" in cancelErr.msg
  
  test "Result capture":
    proc mightFail(shouldFail: bool): int =
      if shouldFail:
        raise newException(ValueError, "Something went wrong")
      return 42
    
    let successResult = capture(proc(): int = mightFail(false))
    check successResult.isOk
    check successResult.get() == 42
    
    let failureResult = capture(proc(): int = mightFail(true))
    check failureResult.isErr
    check failureResult.error().msg == "Something went wrong"
  
  test "Result map":
    let result = Result[int, ref CatchableError].ok(42)
    let mapped = result.mapResult(proc(x: int): string = $x)
    check mapped.isOk
    check mapped.get() == "42"
    
    let errorResult = Result[int, string].err("error")
    let mappedError = errorResult.mapResult(proc(x: int): string = $x)
    check mappedError.isErr
    check mappedError.error() == "error"
  
  test "Result flatMap":
    proc doubleIfPositive(x: int): Result[int, string] =
      if x > 0:
        Result[int, string].ok(x * 2)
      else:
        Result[int, string].err("negative number")
    
    let result = Result[int, string].ok(5)
    let flatMapped = result.flatMapResult(doubleIfPositive)
    check flatMapped.isOk
    check flatMapped.get() == 10
    
    let negResult = Result[int, string].ok(-5)
    let negFlatMapped = negResult.flatMapResult(doubleIfPositive)
    check negFlatMapped.isErr
    check negFlatMapped.error() == "negative number"
  
  test "Result mapErr":
    let errorResult = Result[int, string].err("not found")
    let mapped = errorResult.mapErrResult(proc(e: string): string = e.toUpperAscii())
    check mapped.isErr
    check mapped.error() == "NOT FOUND"
    
    let okResult = Result[int, ref CatchableError].ok(42)
    let mappedOk = okResult.mapErrResult(proc(e: ref CatchableError): string = e.msg)
    check mappedOk.isOk
    check mappedOk.get() == 42
  
  test "Result recover":
    let errorResult = Result[int, string].err("error")
    let recovered = errorResult.recoverResult(99)
    check recovered == 99
    
    let okResult = Result[int, string].ok(42)
    let okRecovered = okResult.recoverResult(99)
    check okRecovered == 42
  
  test "Result recoverWith":
    let errorResult = Result[int, string].err("5")
    let recovered = errorResult.recoverWithResult(proc(e: string): int = parseInt(e))
    check recovered == 5
    
    let okResult = Result[int, ref CatchableError].ok(42)
    let okRecovered = okResult.recoverWithResult(proc(e: ref CatchableError): int = 0)
    check okRecovered == 42
  
  test "Result combine":
    let r1 = Result[int, ref CatchableError].ok(1)
    let r2 = Result[int, ref CatchableError].ok(2)
    let r3 = Result[int, ref CatchableError].ok(3)
    
    let combined = combineResults(r1, r2, r3)
    check combined.isOk
    check combined.get() == @[1, 2, 3]
    
    let r4 = Result[int, ref CatchableError].err(newException(CatchableError, "error"))
    let combinedWithError = combineResults(r1, r2, r4)
    check combinedWithError.isErr
  
  test "Result combineWith":
    let r1 = Result[int, ref CatchableError].ok(10)
    let r2 = Result[int, ref CatchableError].ok(20)
    let r3 = Result[int, ref CatchableError].ok(30)
    
    let sum = combineWithResult(r1, r2, r3, proc(values: seq[int]): int = 
      result = 0
      for v in values: result += v
    )
    check sum.isOk
    check sum.get() == 60
  
  test "Result withContext":
    let errorResult = Result[int, string].err("original error")
    let withCtx = errorResult.withContextResult(proc(e: string): string = 
      fmt"Context: {e}"
    )
    check withCtx.isErr
    check withCtx.error() == "Context: original error"
  
  test "Validation":
    type ValProc = proc(val: string): Result[void, string]
    
    let notEmpty: ValProc = proc(val: string): Result[void, string] =
      if val.len == 0:
        return Result[void, string].err("cannot be empty")
      else:
        return Result[void, string].ok()
    
    let validEmail: ValProc = proc(val: string): Result[void, string] =
      if "@" notin val:
        return Result[void, string].err("must contain @")  
      else:
        return Result[void, string].ok()
    
    let validResult = validate("test@example.com", notEmpty, validEmail)
    check validResult.isOk
    
    let invalidResult = validate("", notEmpty, validEmail)
    check invalidResult.isErr
    check invalidResult.error().len == 2
    check "cannot be empty" in invalidResult.error()
    check "must contain @" in invalidResult.error()
  
  test "Error context formatting":
    let ctx = newErrorContext(
      ecNotFound,
      "Resource not found",
      "api.nim",
      123,
      45
    )
    let formatted = $ctx
    check "[NOT_FOUND]" in formatted
    check "Resource not found" in formatted
    check "api.nim:123:45" in formatted
  
  test "App error formatting":
    let err = newAppError(ecInternalError, "System failure")
    let formatted = $err
    check "System failure" in formatted
    check "[INTERNAL_ERROR]" in formatted
  
  test "Error context with inner error":
    let inner = new(ErrorContext)
    inner[] = newErrorContext(ecConnectionFailed, "Network error")
    
    let outer = newErrorContext(
      ecInternalError,
      "Service unavailable",
      innerError = inner
    )
    
    let formatted = $outer
    check "Service unavailable" in formatted
    check "Caused by:" in formatted
    check "Network error" in formatted
  
  test "Macro tryExpr":
    proc maybeInt(s: string): int =
      parseInt(s)
    
    let result1 = tryExpr(maybeInt("42"))
    check result1.isOk
    check result1.get() == 42
    
    let result2 = tryExpr(maybeInt("not a number"))
    check result2.isErr
  
  test "Stack trace capture":
    when defined(debug):
      let trace = getErrorStackTrace()
      check trace.len > 0
    else:
      let trace = getErrorStackTrace()
      check trace.len == 0
  
  test "Error chaining with addContext":
    let err = newValidationError("Invalid input")
    let enriched = err.addContext("field", "username")
                      .addContext("value", "admin@")
    
    check "field=username" in enriched.msg
    check "value=admin@" in enriched.msg