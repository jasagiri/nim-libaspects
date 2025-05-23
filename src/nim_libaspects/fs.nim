## File System utilities module
## Provides cross-platform file system operations and abstractions

import std/[os, strutils, times, tables, sets, sequtils, sugar, hashes]
import ./errors

export os

type
  WatchEvent* = enum
    Created
    Modified
    Deleted
    Renamed
    
  WatchCallback* = proc(path: string, event: WatchEvent) {.closure.}
  
  FileWatcher* = ref object
    paths: seq[string]
    callback: WatchCallback
    lastModified: Table[string, Time]
    running: bool
    
  TempFileManager* = ref object
    files: seq[string]
    dirs: seq[string]
    
  PathResolver* = ref object
    basePath: string
    aliases: Table[string, string]

# Path utilities
proc normalizePath*(path: string): string =
  ## Normalize path separators and resolve . and ..
  result = path.normalizedPath()
  
proc expandPath*(path: string, base: string = ""): string =
  ## Expand relative path to absolute
  if path.isAbsolute:
    result = path
  else:
    result = if base.len > 0: base / path else: getCurrentDir() / path
  result = result.normalizedPath()
  
proc ensureDir*(path: string): Result[void, string] =
  ## Ensure directory exists, creating if necessary
  try:
    createDir(path)
    ok()
  except OSError as e:
    err("Failed to create directory: " & e.msg)
    
proc ensureParentDir*(path: string): Result[void, string] =
  ## Ensure parent directory of path exists
  let parent = path.parentDir
  if parent.len > 0:
    ensureDir(parent)
  else:
    ok()
    
# File operations
proc readFileUtf8*(path: string): Result[string, string] =
  ## Read file as UTF-8 string
  try:
    ok(readFile(path))
  except IOError as e:
    err("Failed to read file: " & e.msg)
    
proc writeFileUtf8*(path: string, content: string): Result[void, string] =
  ## Write string to file as UTF-8
  try:
    writeFile(path, content)
    ok()
  except IOError as e:
    err("Failed to write file: " & e.msg)
    
proc copyFileWithProgress*(src, dest: string, 
                          onProgress: proc(copied, total: int64) = nil): Result[void, string] =
  ## Copy file with optional progress callback
  try:
    if onProgress == nil:
      copyFile(src, dest)
    else:
      let srcFile = open(src, fmRead)
      defer: srcFile.close()
      
      let destFile = open(dest, fmWrite)
      defer: destFile.close()
      
      let fileSize = getFileSize(src)
      var copied: int64 = 0
      let bufferSize = 8192
      var buffer = newString(bufferSize)
      
      while true:
        let bytesRead = srcFile.readBuffer(addr buffer[0], bufferSize)
        if bytesRead == 0:
          break
          
        discard destFile.writeBuffer(addr buffer[0], bytesRead)
        copied += bytesRead
        
        if onProgress != nil:
          onProgress(copied, fileSize)
          
    ok()
  except IOError as e:
    err("Failed to copy file: " & e.msg)
    
# File watching
proc newFileWatcher*(callback: WatchCallback): FileWatcher =
  ## Create a new file watcher
  result = FileWatcher(
    paths: @[],
    callback: callback,
    lastModified: initTable[string, Time](),
    running: false
  )
  
proc addPath*(watcher: FileWatcher, path: string) =
  ## Add path to watch list
  if path notin watcher.paths:
    watcher.paths.add(path)
    if fileExists(path):
      watcher.lastModified[path] = getLastModificationTime(path)
      
proc removePath*(watcher: FileWatcher, path: string) =
  ## Remove path from watch list
  let idx = watcher.paths.find(path)
  if idx >= 0:
    watcher.paths.del(idx)
    watcher.lastModified.del(path)
    
proc checkChanges*(watcher: FileWatcher) =
  ## Check for file changes
  for path in watcher.paths:
    if fileExists(path):
      let modTime = getLastModificationTime(path)
      if path notin watcher.lastModified:
        watcher.callback(path, Created)
        watcher.lastModified[path] = modTime
      elif modTime != watcher.lastModified[path]:
        watcher.callback(path, Modified)
        watcher.lastModified[path] = modTime
    else:
      if path in watcher.lastModified:
        watcher.callback(path, Deleted)
        watcher.lastModified.del(path)
        
# Temp file management
proc newTempFileManager*(): TempFileManager =
  ## Create a new temp file manager
  result = TempFileManager(
    files: @[],
    dirs: @[]
  )
  
proc createTempFile*(manager: TempFileManager, prefix = "tmp", suffix = ""): string =
  ## Create a temporary file
  # Import tempfile module if available, otherwise use simple implementation
  result = getTempDir() / prefix & $epochTime().int & suffix
  writeFile(result, "")
  manager.files.add(result)
  
proc createTempDir*(manager: TempFileManager, prefix = "tmp"): string =
  ## Create a temporary directory
  result = getTempDir() / prefix & $epochTime().int
  createDir(result)
  manager.dirs.add(result)
  
proc cleanup*(manager: TempFileManager) =
  ## Clean up all temporary files and directories
  for file in manager.files:
    if fileExists(file):
      removeFile(file)
  manager.files.setLen(0)
  
  # Remove directories in reverse order (deepest first)
  for i in countdown(manager.dirs.len - 1, 0):
    let dir = manager.dirs[i]
    if dirExists(dir):
      removeDir(dir)
  manager.dirs.setLen(0)
  
# Path resolution
proc newPathResolver*(basePath = ""): PathResolver =
  ## Create a new path resolver
  result = PathResolver(
    basePath: if basePath.len > 0: expandPath(basePath) else: getCurrentDir(),
    aliases: initTable[string, string]()
  )
  
proc addAlias*(resolver: PathResolver, alias, path: string) =
  ## Add a path alias
  resolver.aliases[alias] = expandPath(path, resolver.basePath)
  
proc resolve*(resolver: PathResolver, path: string): string =
  ## Resolve a path, expanding aliases
  if path.len > 0 and path[0] == '@':
    let parts = path.split('/', 1)
    let alias = parts[0][1..^1]  # Remove @ prefix
    if alias in resolver.aliases:
      let basePath = resolver.aliases[alias]
      if parts.len > 1:
        result = basePath / parts[1]
      else:
        result = basePath
    else:
      result = expandPath(path, resolver.basePath)
  else:
    result = expandPath(path, resolver.basePath)
  result = result.normalizedPath()
  
# Utility functions
proc findFiles*(pattern: string, dir = "."): seq[string] =
  ## Find files matching a pattern
  for file in walkFiles(dir / pattern):
    result.add(file)
    
proc findFilesRecursive*(pattern: string, dir = "."): seq[string] =
  ## Find files recursively matching a pattern
  for file in walkDirRec(dir):
    if file.endsWith(pattern) or pattern in file:
      result.add(file)
      
proc getFileHash*(path: string): Result[string, string] =
  ## Calculate file hash (simple implementation)
  let content = ?readFileUtf8(path)
  ok($content.hash)  # Simple hash for now
  
proc compareFiles*(path1, path2: string): Result[bool, string] =
  ## Compare two files
  let content1 = ?readFileUtf8(path1)
  let content2 = ?readFileUtf8(path2)
  ok(content1 == content2)
