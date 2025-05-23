# Package
version       = "0.1.0"
author        = "Your Name"
description   = "Common process management utilities for Nim"
license       = "MIT"
srcDir        = "src"

# Dependencies
requires "nim >= 2.0.0"

# Tasks
task test, "Run tests":
  exec "testament pattern 'tests/test*.nim'"

task docs, "Generate documentation":
  exec "nim doc --project --index:on --outdir:htmldocs src/process.nim"