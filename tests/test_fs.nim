## Tests for file system utilities

import unittest
import std/[os, sequtils, times, strutils]
import ../src/nim_libaspects/fs
import ../src/nim_libaspects/errors

suite "Path utilities":
  test "normalizePath":
    check normalizePath("foo/bar/../baz") == "foo/baz"
    check normalizePath("./foo/./bar") == "foo/bar"
    
  test "expandPath":
    let base = "/home/user"
    check expandPath("foo/bar", base) == "/home/user/foo/bar"
    check expandPath("/absolute/path", base) == "/absolute/path"
    
  test "ensureDir":
    let tempDir = getTempDir() / "test_ensure_dir"
    removeDir(tempDir)
    
    let result = ensureDir(tempDir)
    check result.isOk
    check dirExists(tempDir)
    
    # Cleanup
    removeDir(tempDir)
    
  test "ensureParentDir":
    let tempFile = getTempDir() / "test_parent" / "file.txt"
    let parentDir = tempFile.parentDir
    removeDir(parentDir)
    
    let result = ensureParentDir(tempFile)
    check result.isOk
    check dirExists(parentDir)
    
    # Cleanup
    removeDir(parentDir)

suite "File operations":
  test "readFileUtf8 and writeFileUtf8":
    let tempFile = getTempDir() / "test_file.txt"
    let content = "Hello, World! 你好世界"
    
    let writeResult = writeFileUtf8(tempFile, content)
    check writeResult.isOk
    
    let readResult = readFileUtf8(tempFile)
    check readResult.isOk
    check readResult.get == content
    
    # Cleanup
    removeFile(tempFile)
    
  test "copyFileWithProgress":
    let srcFile = getTempDir() / "test_src.txt"
    let destFile = getTempDir() / "test_dest.txt"
    let content = "Test content for copy"
    
    writeFile(srcFile, content)
    
    var progressCalled = false
    let result = copyFileWithProgress(srcFile, destFile) do (copied, total: int64):
      progressCalled = true
      check copied <= total
      
    check result.isOk
    check readFile(destFile) == content
    
    # Cleanup
    removeFile(srcFile)
    removeFile(destFile)

suite "File watching":
  test "FileWatcher basic operations":
    var events: seq[(string, WatchEvent)] = @[]
    
    let watcher = newFileWatcher proc(path: string, event: WatchEvent) =
      events.add((path, event))
      
    let testFile = getTempDir() / "watch_test.txt"
    watcher.addPath(testFile)
    
    # Create file
    writeFile(testFile, "initial")
    watcher.checkChanges()
    
    check events.len > 0
    check events[^1][1] == Created
    
    # Modify file
    events.setLen(0)
    sleep(100)  # Ensure modification time changes
    writeFile(testFile, "modified")
    watcher.checkChanges()
    
    check events.len > 0
    check events[^1][1] == Modified
    
    # Delete file
    events.setLen(0)
    removeFile(testFile)
    watcher.checkChanges()
    
    check events.len > 0
    check events[^1][1] == Deleted

suite "Temp file management":
  test "TempFileManager":
    let manager = newTempFileManager()
    
    # Create temp file
    let tempFile = manager.createTempFile("test_", ".txt")
    check fileExists(tempFile)
    
    # Create temp dir
    let tempDir = manager.createTempDir("test_dir_")
    check dirExists(tempDir)
    
    # Create file in temp dir
    let fileInDir = tempDir / "test.txt"
    writeFile(fileInDir, "test")
    
    # Cleanup
    manager.cleanup()
    check not fileExists(tempFile)
    check not dirExists(tempDir)

suite "Path resolution":
  test "PathResolver":
    let resolver = newPathResolver()
    
    resolver.addAlias("src", "src")
    resolver.addAlias("tests", "tests")
    
    let resolved1 = resolver.resolve("@src/main.nim")
    check resolved1.contains("src/main.nim")
    
    let resolved2 = resolver.resolve("@tests/test.nim")
    check resolved2.contains("tests/test.nim")
    
    let resolved3 = resolver.resolve("regular/path.nim")
    check resolved3.contains("regular/path.nim")

suite "Utility functions":
  test "findFiles":
    let tempDir = getTempDir() / "find_test"
    createDir(tempDir)
    
    writeFile(tempDir / "test1.nim", "")
    writeFile(tempDir / "test2.nim", "")
    writeFile(tempDir / "test.txt", "")
    
    let nimFiles = findFiles("*.nim", tempDir)
    check nimFiles.len == 2
    
    # Cleanup
    removeDir(tempDir)
    
  test "findFilesRecursive":
    let tempDir = getTempDir() / "find_recursive"
    let subDir = tempDir / "sub"
    createDir(tempDir)
    createDir(subDir)
    
    writeFile(tempDir / "test1.nim", "")
    writeFile(subDir / "test2.nim", "")
    writeFile(tempDir / "test.txt", "")
    
    let nimFiles = findFilesRecursive(".nim", tempDir)
    check nimFiles.len == 2
    
    # Cleanup
    removeDir(tempDir)
    
  test "getFileHash":
    let tempFile = getTempDir() / "hash_test.txt"
    writeFile(tempFile, "test content")
    
    let hashResult = getFileHash(tempFile)
    check hashResult.isOk
    
    # Same content should produce same hash
    let tempFile2 = getTempDir() / "hash_test2.txt"
    writeFile(tempFile2, "test content")
    
    let hashResult2 = getFileHash(tempFile2)
    check hashResult2.isOk
    check hashResult.get == hashResult2.get
    
    # Cleanup
    removeFile(tempFile)
    removeFile(tempFile2)
    
  test "compareFiles":
    let tempFile1 = getTempDir() / "compare1.txt"
    let tempFile2 = getTempDir() / "compare2.txt"
    let tempFile3 = getTempDir() / "compare3.txt"
    
    writeFile(tempFile1, "same content")
    writeFile(tempFile2, "same content")
    writeFile(tempFile3, "different content")
    
    let result1 = compareFiles(tempFile1, tempFile2)
    check result1.isOk
    check result1.get == true
    
    let result2 = compareFiles(tempFile1, tempFile3)
    check result2.isOk
    check result2.get == false
    
    # Cleanup
    removeFile(tempFile1)
    removeFile(tempFile2)
    removeFile(tempFile3)