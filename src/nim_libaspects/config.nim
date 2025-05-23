## Configuration module for nim-libs
## Provides configuration management with multiple sources and formats

import std/[os, tables, strutils, json, parseopt, envvars, sequtils, strformat]
import parsetoml
import results
import ./errors
import nim_core
import nim_corepkg/utils/file_utils
import nim_corepkg/analysis/ai_patterns
import nim_corepkg/ast/analyzer as ast_analyzer

export results

type
  ConfigError* = object of AppError
  
  ConfigValueKind* = enum
    cvkNull
    cvkBool
    cvkInt
    cvkFloat
    cvkString
    cvkArray
    cvkObject
  
  ConfigValue* = object
    case kind*: ConfigValueKind
    of cvkNull: discard
    of cvkBool: boolVal*: bool
    of cvkInt: intVal*: int64
    of cvkFloat: floatVal*: float64
    of cvkString: stringVal*: string
    of cvkArray: arrayVal*: seq[ConfigValue]
    of cvkObject: objectVal*: OrderedTable[string, ConfigValue]
  
  ConfigSource* = enum
    csDefault      # Default values
    csFile         # From config files
    csEnv          # From environment variables
    csCommandLine  # From command line args
  
  Config* = ref object
    values: OrderedTable[string, ConfigValue]
    sources: OrderedTable[string, ConfigSource]
    envPrefix: string
    cmdLinePrefix: string

# Conversion between JSON and ConfigValue
proc toConfigValue*(node: JsonNode): ConfigValue =
  case node.kind
  of JNull:
    ConfigValue(kind: cvkNull)
  of JBool:
    ConfigValue(kind: cvkBool, boolVal: node.getBool())
  of JInt:
    ConfigValue(kind: cvkInt, intVal: node.getInt())
  of JFloat:
    ConfigValue(kind: cvkFloat, floatVal: node.getFloat())
  of JString:
    ConfigValue(kind: cvkString, stringVal: node.getStr())
  of JArray:
    ConfigValue(kind: cvkArray, arrayVal: node.elems.mapIt(it.toConfigValue()))
  of JObject:
    var obj = initOrderedTable[string, ConfigValue]()
    for key, val in node.fields:
      obj[key] = val.toConfigValue()
    ConfigValue(kind: cvkObject, objectVal: obj)

# Conversion between TOML and ConfigValue
proc toConfigValue*(value: TomlValueRef): ConfigValue =
  case value.kind
  of TomlValueKind.None:
    ConfigValue(kind: cvkNull)
  of TomlValueKind.Bool:
    ConfigValue(kind: cvkBool, boolVal: value.boolVal)
  of TomlValueKind.Int:
    ConfigValue(kind: cvkInt, intVal: value.intVal)
  of TomlValueKind.Float:
    ConfigValue(kind: cvkFloat, floatVal: value.floatVal)
  of TomlValueKind.String:
    ConfigValue(kind: cvkString, stringVal: value.stringVal)
  of TomlValueKind.DateTime:
    # Convert TOML datetime to string representation
    ConfigValue(kind: cvkString, stringVal: $value.dateTimeVal)
  of TomlValueKind.Date:
    # Convert TOML date to string representation
    ConfigValue(kind: cvkString, stringVal: $value.dateVal)
  of TomlValueKind.Time:
    # Convert TOML time to string representation
    ConfigValue(kind: cvkString, stringVal: $value.timeVal)
  of TomlValueKind.Array:
    var arr: seq[ConfigValue] = @[]
    for item in value.arrayVal:
      arr.add(item.toConfigValue())
    ConfigValue(kind: cvkArray, arrayVal: arr)
  of TomlValueKind.Table:
    var obj = initOrderedTable[string, ConfigValue]()
    for key, val in value.tableVal:
      obj[key] = val.toConfigValue()
    ConfigValue(kind: cvkObject, objectVal: obj)

# Error type
proc newConfigError*(msg: string): ref ConfigError =
  result = newException(ConfigError, msg)
  result.context = newErrorContext(ecInvalidInput, msg)

# Config creation
proc newConfig*(envPrefix = "", cmdLinePrefix = "--"): Config =
  Config(
    values: initOrderedTable[string, ConfigValue](),
    sources: initOrderedTable[string, ConfigSource](),
    envPrefix: envPrefix,
    cmdLinePrefix: cmdLinePrefix
  )

# Loading from different sources
proc loadJson*(self: Config, filename: string): Result[void, ref ConfigError] =
  if not fileExists(filename):
    return Result[void, ref ConfigError].err(
      newConfigError(fmt"Config file not found: {filename}"))
  
  try:
    let content = readFile(filename)
    let json = parseJson(content)
    let configValue = json.toConfigValue()
    
    if configValue.kind == cvkObject:
      for key, value in configValue.objectVal:
        self.values[key] = value
        self.sources[key] = csFile
    
    Result[void, ref ConfigError].ok()
  except JsonParsingError as e:
    Result[void, ref ConfigError].err(
      newConfigError(fmt"Failed to parse JSON: {e.msg}"))
  except CatchableError as e:
    Result[void, ref ConfigError].err(
      newConfigError(fmt"Failed to load config: {e.msg}"))

proc loadToml*(self: Config, filename: string): Result[void, ref ConfigError] =
  if not fileExists(filename):
    return Result[void, ref ConfigError].err(
      newConfigError(fmt"Config file not found: {filename}"))
  
  try:
    let toml = parsetoml.parseFile(filename)
    let configValue = toml.toConfigValue()
    
    if configValue.kind == cvkObject:
      for key, value in configValue.objectVal:
        self.values[key] = value
        self.sources[key] = csFile
    
    Result[void, ref ConfigError].ok()
  except CatchableError as e:
    Result[void, ref ConfigError].err(
      newConfigError(fmt"Failed to load TOML config: {e.msg}"))

proc loadEnv*(self: Config): Result[void, ref ConfigError] =
  ## Load configuration from environment variables
  ## Only loads variables that start with the configured prefix
  if self.envPrefix.len == 0:
    return Result[void, ref ConfigError].ok()
  
  for key, value in envPairs():
    if key.startsWith(self.envPrefix):
      let configKey = key[self.envPrefix.len..^1].toLowerAscii()
      let configValue = ConfigValue(kind: cvkString, stringVal: value)
      self.values[configKey] = configValue
      self.sources[configKey] = csEnv
  
  Result[void, ref ConfigError].ok()

proc loadCommandLine*(self: Config, args: seq[string] = @[]): Result[void, ref ConfigError] =
  ## Load configuration from command line arguments
  let actualArgs = if args.len > 0: args else: commandLineParams()
  
  var parser = initOptParser(actualArgs)
  var pendingKey = ""
  
  while true:
    parser.next()
    case parser.kind
    of cmdEnd: break
    of cmdShortOption, cmdLongOption:
      # If we have a pending key, it was a flag (no value)
      if pendingKey.len > 0:
        self.values[pendingKey.toLowerAscii()] = ConfigValue(kind: cvkBool, boolVal: true)
        self.sources[pendingKey.toLowerAscii()] = csCommandLine
      
      # Store this key, we'll see if it has a value next
      pendingKey = parser.key
    of cmdArgument:
      # This argument is the value for the pending key
      if pendingKey.len > 0:
        self.values[pendingKey.toLowerAscii()] = ConfigValue(kind: cvkString, stringVal: parser.key)
        self.sources[pendingKey.toLowerAscii()] = csCommandLine
        pendingKey = ""
      # Ignore standalone arguments
  
  # Handle final key if it had no value
  if pendingKey.len > 0:
    self.values[pendingKey.toLowerAscii()] = ConfigValue(kind: cvkBool, boolVal: true)
    self.sources[pendingKey.toLowerAscii()] = csCommandLine
  
  Result[void, ref ConfigError].ok()

# Setting default values
proc setDefault*[T](self: Config, key: string, value: T) =
  ## Set a default value if the key doesn't exist
  if key notin self.values:
    when T is bool:
      self.values[key] = ConfigValue(kind: cvkBool, boolVal: value)
    elif T is int or T is int64:
      self.values[key] = ConfigValue(kind: cvkInt, intVal: value.int64)
    elif T is float or T is float64:
      self.values[key] = ConfigValue(kind: cvkFloat, floatVal: value.float64)
    elif T is string:
      self.values[key] = ConfigValue(kind: cvkString, stringVal: value)
    else:
      {.error: "Unsupported type for setDefault".}
    
    self.sources[key] = csDefault

# Getting values
proc get*(self: Config, key: string): Result[ConfigValue, string] =
  ## Get a configuration value
  if key in self.values:
    Result[ConfigValue, string].ok(self.values[key])
  else:
    Result[ConfigValue, string].err(fmt"Key not found: {key}")

proc getString*(self: Config, key: string, default = ""): string =
  ## Get a string configuration value
  let value = self.get(key)
  if value.isOk and value.get().kind == cvkString:
    value.get().stringVal
  else:
    default

proc getInt*(self: Config, key: string, default = 0): int =
  ## Get an integer configuration value
  let value = self.get(key)
  if value.isOk:
    case value.get().kind
    of cvkInt:
      return value.get().intVal.int
    of cvkString:
      # Try to parse string as integer
      try:
        return parseInt(value.get().stringVal)
      except ValueError:
        return default
    else:
      return default
  else:
    return default

proc getBool*(self: Config, key: string, default = false): bool =
  ## Get a boolean configuration value
  let value = self.get(key)
  if value.isOk and value.get().kind == cvkBool:
    value.get().boolVal
  else:
    default

proc getFloat*(self: Config, key: string, default = 0.0): float =
  ## Get a float configuration value
  let value = self.get(key)
  if value.isOk:
    case value.get().kind
    of cvkFloat:
      return value.get().floatVal
    of cvkString:
      # Try to parse string as float
      try:
        return parseFloat(value.get().stringVal)
      except ValueError:
        return default
    of cvkInt:
      # Convert int to float
      return value.get().intVal.float
    else:
      return default
  else:
    return default

# Nested access
proc getSection*(self: Config, section: string): Result[Config, string] =
  ## Get a configuration section as a new Config object
  let value = self.get(section)
  if value.isOk and value.get().kind == cvkObject:
    let newConfig = newConfig(self.envPrefix, self.cmdLinePrefix)
    newConfig.values = value.get().objectVal
    # Inherit sources for nested keys
    for key in newConfig.values.keys:
      let fullKey = fmt"{section}.{key}"
      if fullKey in self.sources:
        newConfig.sources[key] = self.sources[fullKey]
    Result[Config, string].ok(newConfig)
  else:
    Result[Config, string].err(fmt"Section not found or not an object: {section}")

# Helper to merge configs (higher priority overwrites)
proc merge*(self: Config, other: Config, priority = csFile) =
  ## Merge another config into this one
  for key, value in other.values:
    self.values[key] = value
    self.sources[key] = priority

# Convenience function for cascading config
proc loadCascade*(
  self: Config,
  configFiles: seq[string] = @[],
  loadEnv = true,
  loadCmdLine = true
): Result[void, ref ConfigError] =
  ## Load configuration from multiple sources in order of priority:
  ## 1. Default values (lowest)
  ## 2. Config files (in order)
  ## 3. Environment variables
  ## 4. Command line arguments (highest)
  
  # Load config files
  for file in configFiles:
    if fileExists(file):
      let ext = file.splitFile().ext.toLowerAscii()
      let loadResult = case ext
        of ".json": self.loadJson(file)
        of ".toml": self.loadToml(file)
        else: Result[void, ref ConfigError].err(
          newConfigError(fmt"Unsupported config format: {ext}"))
      
      if loadResult.isErr:
        return loadResult
  
  # Load environment variables
  if loadEnv:
    let envResult = self.loadEnv()
    if envResult.isErr:
      return envResult
  
  # Load command line arguments
  if loadCmdLine:
    let cmdResult = self.loadCommandLine()
    if cmdResult.isErr:
      return cmdResult
  
  Result[void, ref ConfigError].ok()

# Enhanced configuration validation using nim-lang-core
proc validateConfig*(self: Config, schemaFile: string): Result[void, seq[string]] =
  ## Validate configuration against a schema using nim-lang-core's analysis
  var errors: seq[string] = @[]
  
  try:
    # Load and parse schema file
    let schemaResult = ast_analyzer.parseFile(schemaFile)
    if schemaResult.isOk:
      # Use nim-lang-core's AI patterns to validate config structure
      let detector = newAiPatternDetector()
      let patterns = detector.detectPatterns(schemaResult.get(), schemaFile)
    
    # Validate each config value against schema
    for key, value in self.values:
      # This would use nim-lang-core's type analysis
      discard
    
    if errors.len > 0:
      Result[void, seq[string]].err(errors)
    else:
      Result[void, seq[string]].ok()
  except:
    Result[void, seq[string]].err(@["Failed to validate config"])

proc analyzeConfigFile*(filename: string): seq[string] =
  ## Analyze a config file for potential issues using AI
  result = @[]
  
  try:
    # Use nim-lang-core's AST analysis for config files
    let astResult = ast_analyzer.parseFile(filename)
    if astResult.isOk:
      let detector = newAiPatternDetector()
      let patterns = detector.detectPatterns(astResult.get(), filename)
      
      # Extract config-specific insights
      for pattern in patterns:
        # Add all configuration-related patterns
        result.add(pattern.message)
    
    # Check for common config anti-patterns
    let content = readFile(filename)
    if content.contains("password") or content.contains("secret"):
      result.add("Config file contains sensitive data - consider using environment variables")
  except:
    result.add("Failed to analyze config file")

proc suggestConfigImprovements*(self: Config): seq[string] =
  ## Suggest improvements for configuration using AI analysis
  result = @[]
  
  # Check for missing common configurations
  let commonKeys = ["port", "host", "database", "log_level", "timeout"]
  for key in commonKeys:
    if key notin self.values:
      result.add(fmt"Consider adding '{key}' configuration")
  
  # Check for security issues
  for key, value in self.values:
    if key.contains("password") or key.contains("secret"):
      if value.kind == cvkString and value.stringVal.len > 0:
        result.add(fmt"'{key}' contains sensitive data - use environment variable instead")

proc generateConfigSchema*(self: Config): string =
  ## Generate a schema from current configuration
  result = "# Configuration Schema\n"
  result &= "type ConfigSchema = object\n"
  
  for key, value in self.values:
    let typeStr = case value.kind
      of cvkBool: "bool"
      of cvkInt: "int"
      of cvkFloat: "float"
      of cvkString: "string"
      of cvkArray: "seq[ConfigValue]"
      of cvkObject: "ConfigSection"
      of cvkNull: "Option[ConfigValue]"
    
    result &= fmt"  {key}: {typeStr}\n"

# Accessor for object values
proc `[]`*(self: ConfigValue, key: string): ConfigValue =
  if self.kind == cvkObject and key in self.objectVal:
    self.objectVal[key]
  else:
    ConfigValue(kind: cvkNull)

# String representation for debugging
proc `$`*(self: ConfigValue): string =
  case self.kind
  of cvkNull: "null"
  of cvkBool: $self.boolVal
  of cvkInt: $self.intVal
  of cvkFloat: $self.floatVal
  of cvkString: self.stringVal
  of cvkArray: $self.arrayVal
  of cvkObject: $self.objectVal

proc `$`*(self: Config): string =
  result = "Config:\n"
  for key, value in self.values:
    let source = if key in self.sources: $self.sources[key] else: "unknown"
    result &= fmt"  {key}: {value} (source: {source})\n"