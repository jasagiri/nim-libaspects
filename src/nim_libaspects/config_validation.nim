## Configuration validation and extended features
## Provides validation, encryption, and environment-specific configuration

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
  sets
]
import ./errors

type
  ConfigError* = object of AppError
  ValidationError* = object of ConfigError
  DecryptionError* = object of ConfigError
  
  SchemaType* = enum
    stString = "string"
    stInteger = "integer"
    stFloat = "float"
    stBoolean = "boolean"
    stArray = "array"
    stObject = "object"
  
  SchemaProperty* = object
    `type`*: SchemaType
    required*: bool
    pattern*: string
    minimum*: Option[float]
    maximum*: Option[float]
    minLength*: Option[int]
    maxLength*: Option[int]
    default*: Option[JsonNode]
    properties*: Table[string, SchemaProperty]
    items*: Option[ref SchemaProperty]
  
  ConfigSchema* = object
    properties*: Table[string, SchemaProperty]
  
  ConfigValidator* = ref object
    schema*: ConfigSchema
  
  ConfigEncryption* = ref object
    key*: string
    sensitiveFields*: seq[string]
  
  EnvironmentConfig* = ref object
    environments*: Table[string, JsonNode]
    inheritance*: Table[string, string]
    current*: string
  
  ConfigManager* = ref object
    data*: JsonNode
    validator*: ConfigValidator
    encryption*: ConfigEncryption
    envConfig*: EnvironmentConfig
    overlays*: OrderedTable[string, JsonNode]
    fileWatchers*: Table[string, Time]
    watchEnabled*: bool
    onReload*: proc(config: JsonNode) {.gcsafe.}

# Create new instances
proc newConfigValidator*(): ConfigValidator =
  ConfigValidator(schema: ConfigSchema(properties: initTable[string, SchemaProperty]()))

proc newConfigEncryption*(): ConfigEncryption =
  ConfigEncryption(sensitiveFields: @[])

proc newEnvironmentConfig*(): EnvironmentConfig =
  EnvironmentConfig(
    environments: initTable[string, JsonNode](),
    inheritance: initTable[string, string]()
  )

proc newConfigManager*(): ConfigManager =
  ConfigManager(
    data: newJObject(),
    validator: newConfigValidator(),
    encryption: newConfigEncryption(),
    envConfig: newEnvironmentConfig(),
    overlays: initOrderedTable[string, JsonNode](),
    fileWatchers: initTable[string, Time]()
  )

# Schema parsing
proc parseSchemaType(typeStr: string): SchemaType =
  case typeStr.toLowerAscii()
  of "string": stString
  of "integer", "int": stInteger
  of "float", "number": stFloat
  of "boolean", "bool": stBoolean
  of "array": stArray
  of "object": stObject
  else: raise newException(ValidationError, "Unknown schema type: " & typeStr)

proc parseSchema(node: JsonNode): SchemaProperty =
  result.`type` = parseSchemaType(node["type"].getStr())
  result.required = node{"required"}.getBool(false)
  
  if node.hasKey("pattern"):
    result.pattern = node["pattern"].getStr()
  
  if node.hasKey("minimum"):
    result.minimum = some(node["minimum"].getFloat())
  
  if node.hasKey("maximum"):
    result.maximum = some(node["maximum"].getFloat())
  
  if node.hasKey("minLength"):
    result.minLength = some(node["minLength"].getInt())
  
  if node.hasKey("maxLength"):
    result.maxLength = some(node["maxLength"].getInt())
  
  if node.hasKey("default"):
    result.default = some(node["default"])
  
  if result.`type` == stObject and node.hasKey("properties"):
    result.properties = initTable[string, SchemaProperty]()
    for key, value in node["properties"]:
      result.properties[key] = parseSchema(value)
  
  if result.`type` == stArray and node.hasKey("items"):
    let itemSchema = parseSchema(node["items"])
    result.items = some(new(ref SchemaProperty))
    result.items.get()[] = itemSchema

proc setSchema*(validator: ConfigValidator, schema: JsonNode) =
  validator.schema.properties.clear()
  for key, value in schema:
    validator.schema.properties[key] = parseSchema(value)

proc setSchema*(mgr: ConfigManager, schema: JsonNode) =
  mgr.validator.setSchema(schema)

# Validation
proc validateValue(value: JsonNode, schema: SchemaProperty, path: string): Result[void, ValidationError] =
  case schema.`type`
  of stString:
    if value.kind != JString:
      return err(ValidationError(msg: &"{path}: expected string, got {value.kind}"))
    
    let strVal = value.getStr()
    if schema.pattern != "" and not match(strVal, re(schema.pattern)):
      return err(ValidationError(msg: &"{path}: does not match pattern {schema.pattern}"))
    
    if schema.minLength.isSome and strVal.len < schema.minLength.get():
      return err(ValidationError(msg: &"{path}: string too short"))
    
    if schema.maxLength.isSome and strVal.len > schema.maxLength.get():
      return err(ValidationError(msg: &"{path}: string too long"))
  
  of stInteger:
    if value.kind != JInt:
      return err(ValidationError(msg: &"{path}: expected integer, got {value.kind}"))
    
    let intVal = value.getInt().float
    if schema.minimum.isSome and intVal < schema.minimum.get():
      return err(ValidationError(msg: &"{path}: value below minimum"))
    
    if schema.maximum.isSome and intVal > schema.maximum.get():
      return err(ValidationError(msg: &"{path}: value above maximum"))
  
  of stFloat:
    if value.kind notin {JFloat, JInt}:
      return err(ValidationError(msg: &"{path}: expected number, got {value.kind}"))
    
    let floatVal = if value.kind == JInt: value.getInt().float else: value.getFloat()
    if schema.minimum.isSome and floatVal < schema.minimum.get():
      return err(ValidationError(msg: &"{path}: value below minimum"))
    
    if schema.maximum.isSome and floatVal > schema.maximum.get():
      return err(ValidationError(msg: &"{path}: value above maximum"))
  
  of stBoolean:
    if value.kind != JBool:
      return err(ValidationError(msg: &"{path}: expected boolean, got {value.kind}"))
  
  of stArray:
    if value.kind != JArray:
      return err(ValidationError(msg: &"{path}: expected array, got {value.kind}"))
    
    if schema.items.isSome:
      for i, item in value.elems:
        let itemResult = validateValue(item, schema.items.get()[], &"{path}[{i}]")
        if itemResult.isErr:
          return itemResult
  
  of stObject:
    if value.kind != JObject:
      return err(ValidationError(msg: &"{path}: expected object, got {value.kind}"))
    
    # Check required fields
    for key, prop in schema.properties:
      let fieldPath = if path == "": key else: path & "." & key
      if prop.required and not value.hasKey(key):
        return err(ValidationError(msg: &"{fieldPath}: required field missing"))
    
    # Validate each field
    for key, subValue in value:
      if schema.properties.hasKey(key):
        let fieldPath = if path == "": key else: path & "." & key
        let fieldResult = validateValue(subValue, schema.properties[key], fieldPath)
        if fieldResult.isErr:
          return fieldResult
  
  ok()

proc validate*(validator: ConfigValidator, config: JsonNode): Result[void, ConfigError] =
  for key, schema in validator.schema.properties:
    if schema.required and not config.hasKey(key):
      return err(ConfigError(msg: &"{key}: required field missing"))
    
    if config.hasKey(key):
      let valResult = validateValue(config[key], schema, key)
      if valResult.isErr:
        return err(ConfigError(msg: valResult.error.msg))
  
  ok()

proc validate*(mgr: ConfigManager, config: JsonNode): Result[void, ConfigError] =
  mgr.validator.validate(config)

# Apply defaults
proc applyDefaults(value: JsonNode, schema: SchemaProperty): JsonNode =
  case schema.`type`
  of stObject:
    result = if value.kind == JObject: value.copy() else: newJObject()
    for key, prop in schema.properties:
      if not result.hasKey(key) and prop.default.isSome:
        result[key] = prop.default.get()
      elif result.hasKey(key) and prop.`type` == stObject:
        result[key] = applyDefaults(result[key], prop)
  else:
    if value.kind == JNull and schema.default.isSome:
      result = schema.default.get()
    else:
      result = value

proc validateAndApplyDefaults*(mgr: ConfigManager, config: JsonNode): Result[JsonNode, ConfigError] =
  let valResult = mgr.validate(config)
  if valResult.isErr:
    return err(valResult.error)
  
  var resultConfig = config.copy()
  for key, schema in mgr.validator.schema.properties:
    if not resultConfig.hasKey(key) and schema.default.isSome:
      resultConfig[key] = schema.default.get()
    elif resultConfig.hasKey(key):
      resultConfig[key] = applyDefaults(resultConfig[key], schema)
  
  ok(resultConfig)

# Forward declarations
proc mergeJson(base, overlay: JsonNode): JsonNode
proc recomputeConfig(mgr: ConfigManager)

# File watching and reload
type FileSource* = object
  path*: string

proc addSource*(mgr: ConfigManager, source: FileSource) =
  if fileExists(source.path):
    let content = readFile(source.path)
    let json = parseJson(content)
    mgr.data = mergeJson(mgr.data, json)
    
    if mgr.watchEnabled:
      let info = getFileInfo(source.path)
      mgr.fileWatchers[source.path] = info.lastWriteTime

proc watchChanges*(mgr: ConfigManager, enabled: bool) =
  mgr.watchEnabled = enabled

proc reload*(mgr: ConfigManager) =
  var newData = newJObject()
  
  for path, _ in mgr.fileWatchers:
    if fileExists(path):
      try:
        let content = readFile(path)
        let json = parseJson(content)
        newData = mergeJson(newData, json)
        
        # Update modification time
        let info = getFileInfo(path)
        mgr.fileWatchers[path] = info.lastWriteTime
      except:
        discard  # Skip files that can't be read
  
  if not mgr.onReload.isNil:
    mgr.onReload(newData)
  
  mgr.data = newData

# Encryption
proc simpleXor(data: string, key: string): string =
  result = ""
  for i, c in data:
    result.add(chr(ord(c) xor ord(key[i mod key.len])))

proc setEncryptionKey*(mgr: ConfigManager, key: string) =
  mgr.encryption.key = key

proc markSensitive*(mgr: ConfigManager, fields: seq[string]) =
  mgr.encryption.sensitiveFields = fields

proc encryptValue(value: string, key: string): string =
  if key == "":
    return value
  let encrypted = simpleXor(value, key)
  "enc:" & base64.encode(encrypted)

proc decryptValue(value: string, key: string): string =
  if not value.startsWith("enc:") or key == "":
    return value
  
  try:
    let encrypted = base64.decode(value[4..^1])
    simpleXor(encrypted, key)
  except:
    raise newException(DecryptionError, "Failed to decrypt value")

proc encrypt*(mgr: ConfigManager, config: JsonNode): JsonNode =
  proc encryptNode(node: JsonNode, path: string): JsonNode =
    case node.kind
    of JObject:
      result = newJObject()
      for key, value in node:
        let currentPath = if path == "": key else: path & "." & key
        if currentPath in mgr.encryption.sensitiveFields and value.kind == JString:
          result[key] = %encryptValue(value.getStr(), mgr.encryption.key)
        else:
          result[key] = encryptNode(value, currentPath)
    of JArray:
      result = newJArray()
      for i, value in node:
        result.add(encryptNode(value, path & &"[{i}]"))
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
        if currentPath in mgr.encryption.sensitiveFields and value.kind == JString:
          result[key] = %decryptValue(value.getStr(), mgr.encryption.key)
        else:
          result[key] = decryptNode(value, currentPath)
    of JArray:
      result = newJArray()
      for i, value in node:
        result.add(decryptNode(value, path & &"[{i}]"))
    else:
      result = node
  
  decryptNode(config, "")

# Environment management
proc registerEnvironment*(mgr: ConfigManager, name: string, config: JsonNode) =
  mgr.envConfig.environments[name] = config

proc setEnvironmentInheritance*(mgr: ConfigManager, env: string, parent: string) =
  mgr.envConfig.inheritance[env] = parent

proc setEnvironment*(mgr: ConfigManager, env: string) =
  if not mgr.envConfig.environments.hasKey(env):
    raise newException(ConfigError, "Unknown environment: " & env)
  
  # Collect configs from inheritance chain
  var configs: seq[JsonNode] = @[]
  var current = env
  var visited: HashSet[string]
  
  while true:
    if current in visited:
      raise newException(ConfigError, "Circular environment inheritance detected")
    visited.incl(current)
    
    if mgr.envConfig.environments.hasKey(current):
      configs.add(mgr.envConfig.environments[current])
    
    if mgr.envConfig.inheritance.hasKey(current):
      current = mgr.envConfig.inheritance[current]
    else:
      break
  
  # Apply configs in reverse order (base first)
  mgr.data = newJObject()
  for i in countdown(configs.high, 0):
    mgr.data = mergeJson(mgr.data, configs[i])
  
  mgr.envConfig.current = env

proc getCurrentEnvironment*(mgr: ConfigManager): string =
  mgr.envConfig.current

# Overlays
proc applyOverlay*(mgr: ConfigManager, name: string, config: JsonNode) =
  mgr.overlays[name] = config
  mgr.recomputeConfig()

proc removeOverlay*(mgr: ConfigManager, name: string) =
  mgr.overlays.del(name)
  mgr.recomputeConfig()

proc setOverlayPriority*(mgr: ConfigManager, priority: seq[string]) =
  # Reorder overlays according to priority
  var newOverlays = initOrderedTable[string, JsonNode]()
  for name in priority:
    if mgr.overlays.hasKey(name):
      newOverlays[name] = mgr.overlays[name]
  
  # Add any remaining overlays
  for name, config in mgr.overlays:
    if not newOverlays.hasKey(name):
      newOverlays[name] = config
  
  mgr.overlays = newOverlays
  mgr.recomputeConfig()

proc recomputeConfig(mgr: ConfigManager) =
  # Start with current environment or empty
  mgr.data = if mgr.envConfig.current != "" and mgr.envConfig.environments.hasKey(mgr.envConfig.current):
    mgr.envConfig.environments[mgr.envConfig.current]
  else:
    newJObject()
  
  # Apply overlays in order
  for name, config in mgr.overlays:
    mgr.data = mergeJson(mgr.data, config)

# Template processing
proc processTemplates*(mgr: ConfigManager, config: JsonNode): JsonNode =
  proc expandTemplate(value: string, context: JsonNode): string =
    result = value
    var matches: seq[tuple[start, finish: int]]
    
    # Find all ${...} patterns
    var i = 0
    while i < value.len - 2:
      if value[i] == '$' and value[i+1] == '{':
        let start = i
        var braceCount = 1
        i += 2
        while i < value.len and braceCount > 0:
          if value[i] == '{': inc braceCount
          elif value[i] == '}': dec braceCount
          inc i
        if braceCount == 0:
          matches.add((start, i))
      else:
        inc i
    
    # Replace in reverse order to preserve positions
    for i in countdown(matches.high, 0):
      let (start, finish) = matches[i]
      let expr = value[start+2..finish-2]
      
      # Check for default value syntax: ${VAR:-default}
      let parts = expr.split(":-", 1)
      let varPath = parts[0]
      let defaultValue = if parts.len > 1: parts[1] else: ""
      
      # First check environment variables
      if varPath.toUpperAscii() == varPath:  # All caps = env var
        let envValue = getEnv(varPath)
        if envValue != "":
          result = result[0..start-1] & envValue & result[finish..^1]
        else:
          result = result[0..start-1] & defaultValue & result[finish..^1]
      else:
        # Check in config context
        let pathParts = varPath.split(".")
        var current = context
        var found = true
        
        for part in pathParts:
          if current.kind == JObject and current.hasKey(part):
            current = current[part]
          else:
            found = false
            break
        
        if found and current.kind in {JString, JInt, JFloat, JBool}:
          let replacement = case current.kind
            of JString: current.getStr()
            of JInt: $current.getInt()
            of JFloat: $current.getFloat()
            of JBool: $current.getBool()
            else: ""
          result = result[0..start-1] & replacement & result[finish..^1]
        else:
          result = result[0..start-1] & defaultValue & result[finish..^1]
  
  proc processNode(node: JsonNode, context: JsonNode): JsonNode =
    case node.kind
    of JString:
      result = %expandTemplate(node.getStr(), context)
    of JObject:
      result = newJObject()
      for key, value in node:
        result[key] = processNode(value, context)
    of JArray:
      result = newJArray()
      for value in node:
        result.add(processNode(value, context))
    else:
      result = node
  
  processNode(config, config)

# Utilities
proc mergeJson(base, overlay: JsonNode): JsonNode =
  if base.kind != JObject or overlay.kind != JObject:
    return overlay
  
  result = base.copy()
  for key, value in overlay:
    if result.hasKey(key) and result[key].kind == JObject and value.kind == JObject:
      result[key] = mergeJson(result[key], value)
    else:
      result[key] = value

proc loadJson*(mgr: ConfigManager, json: JsonNode) =
  mgr.data = mergeJson(mgr.data, json)

# Access methods
proc get*(mgr: ConfigManager, path: string): string =
  let parts = path.split(".")
  var current = mgr.data
  
  for part in parts:
    if current.kind == JObject and current.hasKey(part):
      current = current[part]
    else:
      return ""
  
  if current.kind == JString:
    # Check if value is encrypted
    if path in mgr.encryption.sensitiveFields and current.getStr().startsWith("enc:"):
      return decryptValue(current.getStr(), mgr.encryption.key)
    else:
      return current.getStr()
  else:
    return $current

proc getInt*(mgr: ConfigManager, path: string): int =
  let parts = path.split(".")
  var current = mgr.data
  
  for part in parts:
    if current.kind == JObject and current.hasKey(part):
      current = current[part]
    else:
      return 0
  
  if current.kind == JInt:
    return current.getInt()
  else:
    return 0

proc getBool*(mgr: ConfigManager, path: string): bool =
  let parts = path.split(".")
  var current = mgr.data
  
  for part in parts:
    if current.kind == JObject and current.hasKey(part):
      current = current[part]
    else:
      return false
  
  if current.kind == JBool:
    return current.getBool()
  else:
    return false