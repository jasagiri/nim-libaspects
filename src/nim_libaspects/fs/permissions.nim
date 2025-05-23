## File permissions utilities

import std/[os, strutils]
import ../errors

when defined(posix):
  import std/posix
  
type
  FilePermission* = enum
    UserRead = "u+r"
    UserWrite = "u+w"
    UserExecute = "u+x"
    GroupRead = "g+r"
    GroupWrite = "g+w"
    GroupExecute = "g+x"
    OtherRead = "o+r"
    OtherWrite = "o+w"
    OtherExecute = "o+x"
    
  PermissionSet* = set[FilePermission]
  
when defined(posix):
  proc toMode(perms: PermissionSet): Mode =
    ## Convert permission set to POSIX mode
    result = 0
    if UserRead in perms: result = result or S_IRUSR
    if UserWrite in perms: result = result or S_IWUSR
    if UserExecute in perms: result = result or S_IXUSR
    if GroupRead in perms: result = result or S_IRGRP
    if GroupWrite in perms: result = result or S_IWGRP
    if GroupExecute in perms: result = result or S_IXGRP
    if OtherRead in perms: result = result or S_IROTH
    if OtherWrite in perms: result = result or S_IWOTH
    if OtherExecute in perms: result = result or S_IXOTH
    
  proc fromMode(mode: Mode): PermissionSet =
    ## Convert POSIX mode to permission set
    result = {}
    if (mode and S_IRUSR) != 0: result.incl(UserRead)
    if (mode and S_IWUSR) != 0: result.incl(UserWrite)
    if (mode and S_IXUSR) != 0: result.incl(UserExecute)
    if (mode and S_IRGRP) != 0: result.incl(GroupRead)
    if (mode and S_IWGRP) != 0: result.incl(GroupWrite)
    if (mode and S_IXGRP) != 0: result.incl(GroupExecute)
    if (mode and S_IROTH) != 0: result.incl(OtherRead)
    if (mode and S_IWOTH) != 0: result.incl(OtherWrite)
    if (mode and S_IXOTH) != 0: result.incl(OtherExecute)

proc getPermissions*(path: string): Result[PermissionSet, string] =
  ## Get file permissions
  when defined(posix):
    try:
      let info = getFileInfo(path)
      ok(fromMode(info.permissions))
    except OSError as e:
      err("Failed to get permissions: " & e.msg)
  else:
    # Windows doesn't have the same permission model
    ok({UserRead, UserWrite})
    
proc setPermissions*(path: string, perms: PermissionSet): Result[void, string] =
  ## Set file permissions
  when defined(posix):
    try:
      setFilePermissions(path, toMode(perms))
      ok()
    except OSError as e:
      err("Failed to set permissions: " & e.msg)
  else:
    # Windows permissions are more limited
    ok()
    
proc makeExecutable*(path: string): Result[void, string] =
  ## Make file executable by owner
  let perms = ?getPermissions(path)
  setPermissions(path, perms + {UserExecute})
  
proc isExecutable*(path: string): bool =
  ## Check if file is executable
  let perms = getPermissions(path)
  if perms.isOk:
    UserExecute in perms.get
  else:
    false
    
proc isReadable*(path: string): bool =
  ## Check if file is readable
  let perms = getPermissions(path)
  if perms.isOk:
    UserRead in perms.get
  else:
    false
    
proc isWritable*(path: string): bool =
  ## Check if file is writable
  let perms = getPermissions(path)
  if perms.isOk:
    UserWrite in perms.get
  else:
    false
