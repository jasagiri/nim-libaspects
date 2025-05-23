## test_testing.nim
## ===============
##
## Tests for the testing module

import ../src/nim_libaspects/testing

proc testCheckAssertion() =
  echo "Testing check assertion..."
  var raised = false
  try:
    check(true, "Should pass")
  except PowerAssertError:
    raised = true
  assert(not raised)
  
  raised = false
  try:
    check(false, "Should fail")
  except PowerAssertError as e:
    raised = true
    assert(e.msg == "Should fail")
  assert(raised)
  echo "  ✓ Check assertion works"

proc testExpectAssertion() =
  echo "Testing expect assertion..."
  var raised = false
  try:
    expect(42, 42)
  except PowerAssertError:
    raised = true
  assert(not raised)
  
  raised = false
  try:
    expect(42, 43)
  except PowerAssertError as e:
    raised = true
    assert(e.msg == "Expected 42, got 43")
    assert(e.values.len == 2)
    assert(e.values[0] == ("expected", "42"))
    assert(e.values[1] == ("actual", "43"))
  assert(raised)
  echo "  ✓ Expect assertion works"

proc testExpectErrorAssertion() =
  echo "Testing expectError assertion..."
  var raised = false
  try:
    expectError(ValueError):
      raise newException(ValueError, "Test error")
  except PowerAssertError:
    raised = true
  assert(not raised)
  
  raised = false
  try:
    expectError(ValueError):
      # No error raised
      discard
  except PowerAssertError as e:
    raised = true
    assert(e.msg == "Expected ValueError, but no error was raised")
  assert(raised)
  echo "  ✓ ExpectError assertion works"

proc testRunner() =
  echo "Testing test runner..."
  # Just test that we can initialize the registry without error
  initTestRegistry()
  echo "  ✓ Test runner initialization works"

when isMainModule:
  echo "Running nim-libs testing module tests..."
  testCheckAssertion()
  testExpectAssertion()
  testExpectErrorAssertion()
  testRunner()
  echo "All tests passed!"