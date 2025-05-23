## Extended configuration management module
## Provides validation, dynamic reload, encryption, and environment management

import std/[
  tables,
  json,
  strutils,
  sequtils,
  os,
  times,
  re,
  base64,
  options,
  strformat,
  sets,
  encodings
]
import ./errors

type
  ConfigError* = object of AppError
  ValidationError* = object of ConfigError
  DecryptionError* = object of ConfigError
  
  FileSource* = object
    path*: string
  
  # Configuration management system
  ConfigManager* = ref object
    data*: JsonNode
    baseData*: JsonNode  # Store base config separately
    schema*: JsonNode
    encryptionKey*: string
    sensitiveFields*: seq[string]
    fileWatchers*: Table[string, Time]
    watchEnabled*: bool
    onReload*: proc(config: JsonNode) {.gcsafe.}
    environments*: Table[string, JsonNode]
    inheritance*: Table[string, string]
    currentEnvironment*: string
    overlays*: OrderedTable[string, JsonNode]

# Forward declarations
proc recomputeConfig(mgr: ConfigManager)

proc newConfigManager*(): ConfigManager =
  ConfigManager(
    data: newJObject(),
    baseData: newJObject(),
    schema: newJObject(),
    sensitiveFields: @[],
    fileWatchers: initTable[string, Time](),
    environments: initTable[string, JsonNode](),
    inheritance: initTable[string, string](),
    overlays: initOrderedTable[string, JsonNode]()
  )

# Schema validation
proc validateType(value: JsonNode, typeStr: string, path: string): Result[void, ConfigError] =
  case typeStr.toLowerAscii()
  of "string":
    if value.kind != JString:
      return err(ConfigError(msg: &"{path}: expected string, got {value.kind}"))
  of "integer", "int":
    if value.kind != JInt:
      return err(ConfigError(msg: &"{path}: expected integer, got {value.kind}"))
  of "float", "number":
    if value.kind notin {JFloat, JInt}:
      return err(ConfigError(msg: &"{path}: expected number, got {value.kind}"))
  of "boolean", "bool":
    if value.kind != JBool:
      return err(ConfigError(msg: &"{path}: expected boolean, got {value.kind}"))
  of "array":
    if value.kind != JArray:
      return err(ConfigError(msg: &"{path}: expected array, got {value.kind}"))
  of "object":
    if value.kind != JObject:
      return err(ConfigError(msg: &"{path}: expected object, got {value.kind}"))
  ok()

proc validateValue(value: JsonNode, schema: JsonNode, path: string): Result[void, ConfigError] =
  # Type validation
  if schema.hasKey("type"):
    let typeResult = validateType(value, schema["type"].getStr(), path)
    if typeResult.isErr:
      return typeResult
  
  # String pattern validation
  if value.kind == JString and schema.hasKey("pattern"):
    let pattern = schema["pattern"].getStr()
    if not match(value.getStr(), re(pattern)):
      return err(ConfigError(msg: &"{path}: does not match pattern {pattern}"))
  
  # Number range validation
  if value.kind in {JInt, JFloat} and (schema.hasKey("minimum") or schema.hasKey("maximum")):
    let numVal = if value.kind == JInt: value.getInt().float else: value.getFloat()
    
    if schema.hasKey("minimum") and numVal < schema["minimum"].getFloat():
      return err(ConfigError(msg: &"{path}: value below minimum"))
    
    if schema.hasKey("maximum") and numVal > schema["maximum"].getFloat():
      return err(ConfigError(msg: &"{path}: value above maximum"))
  
  # String length validation
  if value.kind == JString and (schema.hasKey("minLength") or schema.hasKey("maxLength")):
    let strLen = value.getStr().len
    
    if schema.hasKey("minLength") and strLen < schema["minLength"].getInt():
      return err(ConfigError(msg: &"{path}: string too short"))
    
    if schema.hasKey("maxLength") and strLen > schema["maxLength"].getInt():
      return err(ConfigError(msg: &"{path}: string too long"))
  
  # Object properties validation
  if value.kind == JObject and schema.hasKey("properties"):
    let properties = schema["properties"]
    
    # Check required fields
    for key, prop in properties:
      if prop.hasKey("required") and prop["required"].getBool() and not value.hasKey(key):
        let fullPath = if path == "": key else: path & "." & key
        return err(ConfigError(msg: &"{fullPath}: required field missing"))
    
    # Validate each property
    for key, subValue in value:
      if properties.hasKey(key):
        let fullPath = if path == "": key else: path & "." & key
        let subResult = validateValue(subValue, properties[key], fullPath)
        if subResult.isErr:
          return subResult
  
  # Array items validation
  if value.kind == JArray and schema.hasKey("items"):
    for i, item in value.elems:
      let itemResult = validateValue(item, schema["items"], &"{path}[{i}]")
      if itemResult.isErr:
        return itemResult
  
  ok()

proc setSchema*(mgr: ConfigManager, schema: JsonNode) =
  mgr.schema = schema

proc validate*(mgr: ConfigManager, config: JsonNode): Result[void, ConfigError] =
  validateValue(config, mgr.schema, "")

proc validateAndApplyDefaults*(mgr: ConfigManager, config: JsonNode): Result[JsonNode, ConfigError] =
  # First validate
  let valResult = mgr.validate(config)
  if valResult.isErr:
    return err(valResult.error)
  
  # Then apply defaults
  var configWithDefaults = config.copy()
  
  proc applyDefaults(value: JsonNode, schema: JsonNode): JsonNode =
    if value.kind == JObject:
      var res = value.copy()
      if schema.hasKey("properties"):
        for key, prop in schema["properties"]:
          if not res.hasKey(key) and prop.hasKey("default"):
            res[key] = prop["default"]
          elif res.hasKey(key):
            res[key] = applyDefaults(res[key], prop)
      return res
    else:
      return value
  
  for key, schema in mgr.schema:
    if not configWithDefaults.hasKey(key) and schema.hasKey("default"):
      configWithDefaults[key] = schema["default"]
    elif configWithDefaults.hasKey(key):
      configWithDefaults[key] = applyDefaults(configWithDefaults[key], schema)
  
  ok(configWithDefaults)

# File watching and reload
proc addSource*(mgr: ConfigManager, source: FileSource) =
  if fileExists(source.path):
    let content = readFile(source.path)
    let json = parseJson(content)
    
    # Merge with existing data
    if mgr.data.kind == JObject and json.kind == JObject:
      for key, value in json:
        mgr.data[key] = value
    else:
      mgr.data = json
    
    if mgr.watchEnabled:
      let info = getFileInfo(source.path)
      mgr.fileWatchers[source.path] = info.lastWriteTime

proc watchChanges*(mgr: ConfigManager, enabled: bool) =
  mgr.watchEnabled = enabled

proc watchFile*(mgr: ConfigManager, path: string) =
  if fileExists(path):
    let info = getFileInfo(path)
    mgr.fileWatchers[path] = info.lastWriteTime

proc reload*(mgr: ConfigManager) =
  var newData = newJObject()
  
  for path, _ in mgr.fileWatchers:
    if fileExists(path):
      try:
        let content = readFile(path)
        let json = parseJson(content)
        
        # Merge data
        if newData.kind == JObject and json.kind == JObject:
          for key, value in json:
            newData[key] = value
        
        # Update modification time
        let info = getFileInfo(path)
        mgr.fileWatchers[path] = info.lastWriteTime
      except:
        discard  # Skip files that can't be read
  
  if mgr.onReload != nil:
    mgr.onReload(newData)
  
  mgr.data = newData

# Encryption/Decryption
proc setEncryptionKey*(mgr: ConfigManager, key: string) =
  mgr.encryptionKey = key

proc markSensitive*(mgr: ConfigManager, fields: seq[string]) =
  mgr.sensitiveFields = fields

proc simpleXor(data: string, key: string): string =
  result = ""
  for i, c in data:
    result.add(chr(ord(c) xor ord(key[i mod key.len])))

proc encrypt*(mgr: ConfigManager, config: JsonNode): JsonNode =
  proc encryptNode(node: JsonNode, path: string): JsonNode =
    case node.kind
    of JObject:
      result = newJObject()
      for key, value in node:
        let currentPath = if path == "": key else: path & "." & key
        if currentPath in mgr.sensitiveFields and value.kind == JString:
          let encrypted = simpleXor(value.getStr(), mgr.encryptionKey)
          result[key] = %("enc:" & base64.encode(encrypted))
        else:
          result[key] = encryptNode(value, currentPath)
    of JArray:
      result = newJArray()
      for i, value in node:
        result.add(encryptNode(value, &"{path}[{i}]"))
    else:
      result = node
  
  encryptNode(config, "")

proc decrypt*(mgr: ConfigManager, config: JsonNode): JsonNode =
  proc decryptNode(node: JsonNode, path: string): JsonNode =
    case node.kind
    of JObject:
      result = newJObject()
      for key, value in node:
        let currentPath = if path == "": key else: path & "." & key
        if currentPath in mgr.sensitiveFields and value.kind == JString:
          let strVal = value.getStr()
          if strVal.startsWith("enc:"):
            try:
              let encrypted = base64.decode(strVal[4..^1])
              let decrypted = simpleXor(encrypted, mgr.encryptionKey)
              result[key] = %decrypted
            except:
              raise newException(DecryptionError, "Failed to decrypt value")
          else:
            result[key] = value
        else:
          result[key] = decryptNode(value, currentPath)
    of JArray:
      result = newJArray()
      for i, value in node:
        result.add(decryptNode(value, &"{path}[{i}]"))
    else:
      result = node
  
  decryptNode(config, "")

# Environment management
proc registerEnvironment*(mgr: ConfigManager, name: string, config: JsonNode) =
  mgr.environments[name] = config

proc mergeJson(target: JsonNode, source: JsonNode) =
  ## Deep merge source into target
  if target.kind == JObject and source.kind == JObject:
    for key, value in source:
      if target.hasKey(key) and target[key].kind == JObject and value.kind == JObject:
        mergeJson(target[key], value)
      else:
        target[key] = value.copy()

proc setEnvironmentInheritance*(mgr: ConfigManager, env: string, parent: string) =
  mgr.inheritance[env] = parent

proc setEnvironment*(mgr: ConfigManager, env: string) =
  if not mgr.environments.hasKey(env):
    raise newException(ConfigError, "Unknown environment: " & env)
  
  # Build inheritance chain
  var configs: seq[JsonNode] = @[]
  var current = env
  var visited = initHashSet[string]()
  
  while true:
    if current in visited:
      raise newException(ConfigError, "Circular environment inheritance detected")
    visited.incl(current)
    
    if mgr.environments.hasKey(current):
      configs.add(mgr.environments[current])
    
    if mgr.inheritance.hasKey(current):
      current = mgr.inheritance[current]
    else:
      break
  
  # Apply in reverse order (base first)
  mgr.data = newJObject()
  for i in countdown(configs.high, 0):
    let config = configs[i]
    if config.kind == JObject:
      mergeJson(mgr.data, config)
  
  mgr.currentEnvironment = env

proc getCurrentEnvironment*(mgr: ConfigManager): string =
  mgr.currentEnvironment

# Overlays
proc applyOverlay*(mgr: ConfigManager, name: string, config: JsonNode) =
  mgr.overlays[name] = config
  recomputeConfig(mgr)

proc removeOverlay*(mgr: ConfigManager, name: string) =
  mgr.overlays.del(name)
  recomputeConfig(mgr)

proc setOverlayPriority*(mgr: ConfigManager, priority: seq[string]) =
  # Reorder overlays
  var newOverlays = initOrderedTable[string, JsonNode]()
  for name in priority:
    if mgr.overlays.hasKey(name):
      newOverlays[name] = mgr.overlays[name]
  
  # Add remaining overlays
  for name, config in mgr.overlays:
    if not newOverlays.hasKey(name):
      newOverlays[name] = config
  
  mgr.overlays = newOverlays
  recomputeConfig(mgr)

proc recomputeConfig(mgr: ConfigManager) =
  # Start with base or environment data
  if mgr.currentEnvironment != "" and mgr.environments.hasKey(mgr.currentEnvironment):
    # When environment is set, start fresh and apply environment chain
    mgr.setEnvironment(mgr.currentEnvironment)
  else:
    # When no environment, use base data
    mgr.data = mgr.baseData.copy()
  
  # Apply overlays with deep merge
  for name, overlay in mgr.overlays:
    if overlay.kind == JObject:
      mergeJson(mgr.data, overlay)

# Template processing
proc processTemplates*(mgr: ConfigManager, config: JsonNode): JsonNode =
  proc expandTemplate(value: string, context: JsonNode): string =
    result = value
    
    # Find ${...} patterns
    var i = 0
    while i < value.len:
      let start = value.find("${", i)
      if start < 0:
        break
      
      let finish = value.find("}", start)
      if finish < 0:
        break
      
      let expr = value[start+2..finish-1]
      
      # Check for default value syntax: ${VAR:-default}
      let parts = expr.split(":-", 1)
      let varPath = parts[0]
      let defaultValue = if parts.len > 1: parts[1] else: ""
      
      var replacement = ""
      
      # Check environment variables (all caps)
      if varPath.toUpperAscii() == varPath:
        let envValue = getEnv(varPath)
        replacement = if envValue != "": envValue else: defaultValue
      else:
        # Navigate through config
        let pathParts = varPath.split(".")
        var current = context
        var found = true
        
        for part in pathParts:
          if current.kind == JObject and current.hasKey(part):
            current = current[part]
          else:
            found = false
            break
        
        if found:
          replacement = case current.kind
            of JString: current.getStr()
            of JInt: $current.getInt()
            of JFloat: $current.getFloat()
            of JBool: $current.getBool()
            else: defaultValue
        else:
          replacement = defaultValue
      
      result = value[0..start-1] & replacement & value[finish+1..^1]
      i = start + replacement.len
  
  proc processNode(node: JsonNode): JsonNode =
    case node.kind
    of JString:
      result = %expandTemplate(node.getStr(), config)
    of JObject:
      result = newJObject()
      for key, value in node:
        result[key] = processNode(value)
    of JArray:
      result = newJArray()
      for value in node:
        result.add(processNode(value))
    else:
      result = node
  
  processNode(config)

# Access methods
proc getValue(mgr: ConfigManager, path: string): JsonNode =
  let parts = path.split(".")
  var current = mgr.data
  
  for part in parts:
    if current.kind == JObject and current.hasKey(part):
      current = current[part]
    else:
      return newJNull()
  
  current

proc get*(mgr: ConfigManager, path: string): string =
  let value = mgr.getValue(path)
  if value.kind == JString:
    # Check if encrypted
    if path in mgr.sensitiveFields and value.getStr().startsWith("enc:"):
      let encrypted = base64.decode(value.getStr()[4..^1])
      return simpleXor(encrypted, mgr.encryptionKey)
    else:
      return value.getStr()
  else:
    return ""

proc getInt*(mgr: ConfigManager, path: string): int =
  let value = mgr.getValue(path)
  if value.kind == JInt:
    return value.getInt()
  else:
    return 0

proc getBool*(mgr: ConfigManager, path: string): bool =
  let value = mgr.getValue(path)
  if value.kind == JBool:
    return value.getBool()
  else:
    return false

proc loadJson*(mgr: ConfigManager, json: JsonNode) =
  mgr.baseData = json.copy()
  mgr.data = json.copy()
  # Clear current environment as we're loading fresh data
  mgr.currentEnvironment = ""
  # Recompute to apply overlays
  recomputeConfig(mgr)

export FileSource
export ConfigError, ValidationError, DecryptionError