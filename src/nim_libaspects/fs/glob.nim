## Glob pattern matching for file system operations

import std/[strutils, sequtils, os, re]
import ../errors

type
  GlobPattern* = object
    pattern: string
    compiled: Regex
    
proc globToRegex(pattern: string): string =
  ## Convert glob pattern to regex
  result = ""
  var i = 0
  while i < pattern.len:
    case pattern[i]
    of '*':
      if i + 1 < pattern.len and pattern[i + 1] == '*':
        # ** matches any number of directories
        result.add ".*"
        i += 2
      else:
        # * matches any characters except /
        result.add "[^/]*"
        i += 1
    of '?':
      # ? matches any single character except /
      result.add "[^/]"
      i += 1
    of '[':
      # Character class
      var j = i + 1
      while j < pattern.len and pattern[j] != ']':
        j += 1
      if j < pattern.len:
        result.add pattern[i..j]
        i = j + 1
      else:
        result.add "\\["
        i += 1
    of '.':
      result.add "\\."
      i += 1
    of '\\':
      if i + 1 < pattern.len:
        result.add "\\" & pattern[i + 1]
        i += 2
      else:
        result.add "\\\\"
        i += 1
    else:
      result.add pattern[i]
      i += 1
  result = "^" & result & "$"
  
proc newGlobPattern*(pattern: string): Result[GlobPattern, string] =
  ## Create a new glob pattern
  try:
    let regex = re(globToRegex(pattern))
    ok(GlobPattern(pattern: pattern, compiled: regex))
  except RegexError as e:
    err("Invalid glob pattern: " & e.msg)
    
proc matches*(pattern: GlobPattern, path: string): bool =
  ## Check if path matches the pattern
  match(path, pattern.compiled)
  
proc glob*(pattern: string, baseDir = "."): seq[string] =
  ## Find all files matching the glob pattern
  result = @[]
  
  let globPattern = newGlobPattern(pattern)
  if globPattern.isErr:
    return result
    
  let pat = globPattern.get
  
  # Handle recursive patterns
  if "**" in pattern:
    for path in walkDirRec(baseDir):
      let relPath = relativePath(path, baseDir)
      if pat.matches(relPath):
        result.add(path)
  else:
    # Non-recursive pattern
    let dirPattern = pattern.rsplit('/', 1)
    let (searchDir, filePattern) = 
      if dirPattern.len == 2:
        (baseDir / dirPattern[0], dirPattern[1])
      else:
        (baseDir, pattern)
        
    if dirExists(searchDir):
      for path in walkDir(searchDir):
        let relPath = relativePath(path.path, baseDir)
        if pat.matches(relPath):
          result.add(path.path)
