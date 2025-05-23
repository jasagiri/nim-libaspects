# Configuration Module

The configuration module provides comprehensive configuration management with support for multiple sources and formats. When integrated with nim-lang-core, it offers AI-powered validation and suggestions.

## Features

- Configuration from multiple sources (files, environment, CLI)
- Support for JSON and TOML formats
- Cascading configuration with priority
- Type-safe value access with conversions
- Nested configuration sections
- **AI-powered config validation** (with nim-lang-core)
- **Automatic schema generation** (with nim-lang-core)
- **Configuration analysis and suggestions** (with nim-lang-core)

## Basic Usage

```nim
import nim_libaspects/config

# Create config with environment variable prefix
let config = newConfig(envPrefix = "MYAPP_")

# Set defaults
config.setDefault("port", 8080)
config.setDefault("host", "localhost")
config.setDefault("debug", false)

# Load from various sources (cascading priority)
discard config.loadJson("config.json")
discard config.loadToml("config.toml")
discard config.loadEnv()
discard config.loadCommandLine()

# Access values with type conversions
let port = config.getInt("port")
let host = config.getString("host", "0.0.0.0")
let debug = config.getBool("debug")
```

## Configuration Sources

### 1. Default Values (Lowest Priority)

```nim
config.setDefault("timeout", 30)
config.setDefault("retries", 3)
```

### 2. Configuration Files

#### JSON Files
```nim
# config.json
{
  "server": {
    "port": 8080,
    "host": "localhost"
  },
  "database": {
    "url": "postgresql://localhost/myapp"
  }
}

# Load it
discard config.loadJson("config.json")
```

#### TOML Files
```nim
# config.toml
[server]
port = 8080
host = "localhost"

[database]
url = "postgresql://localhost/myapp"

# Load it
discard config.loadToml("config.toml")
```

### 3. Environment Variables

```nim
# With prefix "MYAPP_"
# MYAPP_PORT=9000
# MYAPP_DATABASE_URL=postgresql://prod/myapp

discard config.loadEnv()
```

### 4. Command Line Arguments (Highest Priority)

```nim
# --port=9090 --debug

discard config.loadCommandLine()
```

## Enhanced Features with nim-lang-core

### Configuration Validation

Validate configuration against a schema:

```nim
let result = config.validateConfig("schema.nim")
if result.isErr:
  for error in result.error:
    echo "Validation error: ", error
```

### Configuration Analysis

Analyze configuration files for potential issues:

```nim
let issues = analyzeConfigFile("config.json")
for issue in issues:
  echo "Config issue: ", issue
```

Common issues detected:
- Hardcoded passwords or secrets
- Missing required configurations
- Deprecated configuration keys
- Type mismatches

### AI-Powered Suggestions

Get intelligent suggestions for configuration improvements:

```nim
let suggestions = config.suggestConfigImprovements()
for suggestion in suggestions:
  echo "Suggestion: ", suggestion
```

Suggestions include:
- Missing common configurations (database, log_level, etc.)
- Security improvements
- Performance optimizations
- Best practices

### Schema Generation

Automatically generate a configuration schema:

```nim
let schema = config.generateConfigSchema()
writeFile("config-schema.nim", schema)
```

Generated schema example:
```nim
type ConfigSchema = object
  port: int
  host: string
  debug: bool
  database: DatabaseConfig
  
type DatabaseConfig = object
  url: string
  poolSize: int
```

## Nested Configuration

Access nested configuration sections:

```nim
let serverConfig = config.getSection("server")
if serverConfig.isOk:
  let server = serverConfig.get()
  let port = server.getInt("port", 8080)
  let host = server.getString("host", "localhost")
```

## Cascading Configuration

Load configuration from multiple sources with automatic priority:

```nim
discard config.loadCascade(
  configFiles = @["default.toml", "config.toml"],
  loadEnv = true,
  loadCmdLine = true
)
```

Priority order (highest to lowest):
1. Command line arguments
2. Environment variables
3. Config files (later files override earlier)
4. Default values

## Type Conversions

The config module provides automatic type conversions:

```nim
# String to int
config.setDefault("port", "8080")
let port = config.getInt("port")  # Returns 8080

# String to bool
config.setDefault("debug", "true")
let debug = config.getBool("debug")  # Returns true

# Int to float
config.setDefault("timeout", 30)
let timeout = config.getFloat("timeout")  # Returns 30.0
```

## Best Practices

1. **Use environment prefixes**: Avoid conflicts with system variables
2. **Set sensible defaults**: Always provide default values
3. **Validate early**: Check configuration at startup
4. **Avoid secrets in files**: Use environment variables for sensitive data
5. **Use schema validation**: Define and validate configuration structure
6. **Regular analysis**: Use AI analysis to improve configuration

## API Reference

See the main README for complete API documentation.