## Test suite for extended configuration management features
import unittest
import options
import json
import strformat
import strutils
import os
import times
import random
import results
import nim_libaspects/config_extended
import nim_libaspects/errors

proc mkstemp(prefix: string, suffix: string): string =
  let tmpDir = getTempDir()
  let timestamp = getTime().toUnix()
  let randomNum = rand(9999)
  result = tmpDir / &"{prefix}{timestamp}_{randomNum}{suffix}"

suite "Extended Configuration Management":
  var configManager: ConfigManager
  
  setup:
    configManager = newConfigManager()
    
  test "Configuration validation":
    # Define validation schema
    let schema = %*{
      "server": {
        "type": "object",
        "required": ["host", "port"],
        "properties": {
          "host": {"type": "string", "pattern": "^[a-zA-Z0-9.-]+$"},
          "port": {"type": "integer", "minimum": 1, "maximum": 65535},
          "ssl": {"type": "boolean", "default": false}
        }
      },
      "database": {
        "type": "object",
        "required": ["url"],
        "properties": {
          "url": {"type": "string", "pattern": "^(postgres|mysql|sqlite)://"},
          "pool_size": {"type": "integer", "minimum": 1, "maximum": 100, "default": 10}
        }
      },
      "features": {
        "type": "object",
        "properties": {
          "cache_enabled": {"type": "boolean"},
          "cache_ttl": {"type": "integer", "minimum": 0}
        }
      }
    }
    
    # Set validation schema
    configManager.setSchema(schema)
    
    # Test valid configuration
    let validConfig = %*{
      "server": {
        "host": "localhost",
        "port": 8080,
        "ssl": true
      },
      "database": {
        "url": "postgres://localhost/mydb"
      },
      "features": {
        "cache_enabled": true,
        "cache_ttl": 300
      }
    }
    
    let validResult = configManager.validate(validConfig)
    check(validResult.isOk())
    
    # Test invalid configuration - missing required field
    let invalidConfig1 = %*{
      "server": {
        "host": "localhost"
        # Missing required 'port'
      }
    }
    
    let invalidResult1 = configManager.validate(invalidConfig1)
    check(invalidResult1.isErr())
    check("port" in invalidResult1.error.msg)
    
    # Test invalid configuration - wrong type
    let invalidConfig2 = %*{
      "server": {
        "host": "localhost",
        "port": "8080"  # Should be integer
      }
    }
    
    let invalidResult2 = configManager.validate(invalidConfig2)
    check(invalidResult2.isErr())
    check("type" in invalidResult2.error.msg)
    
    # Test invalid configuration - out of range
    let invalidConfig3 = %*{
      "server": {
        "host": "localhost",
        "port": 70000  # Exceeds maximum
      }
    }
    
    let invalidResult3 = configManager.validate(invalidConfig3)
    check(invalidResult3.isErr())
    check("maximum" in invalidResult3.error.msg)
    
    # Test configuration with defaults
    let configWithDefaults = %*{
      "server": {
        "host": "localhost",
        "port": 8080
        # ssl should default to false
      },
      "database": {
        "url": "postgres://localhost/mydb"
        # pool_size should default to 10
      }
    }
    
    let result = configManager.validateAndApplyDefaults(configWithDefaults)
    check(result.isOk())
    if result.isOk:
      let finalConfig = result.unsafeGet()
      check(finalConfig["server"]["ssl"].getBool() == false)
      check(finalConfig["database"]["pool_size"].getInt() == 10)
    
  test "Dynamic configuration reload":
    # Create temporary config file
    let tmpFile = mkstemp("config_", ".json")
    
    # Initial configuration
    let initialConfig = %*{
      "app": {
        "name": "TestApp",
        "version": "1.0.0",
        "debug": false
      }
    }
    writeFile(tmpFile, $initialConfig)
    
    # Load initial configuration
    configManager.addSource(FileSource(path: tmpFile))
    check(configManager.get("app.name") == "TestApp")
    check(configManager.getBool("app.debug") == false)
    
    # Set up reload callback
    var reloadCount = 0
    var lastConfig: JsonNode
    
    configManager.onReload = proc(newConfig: JsonNode) {.gcsafe.} =
      {.gcsafe.}:
        inc reloadCount
        lastConfig = newConfig
    
    # Enable watching
    configManager.watchChanges(enabled = true)
    
    # Update configuration file
    let updatedConfig = %*{
      "app": {
        "name": "TestApp",
        "version": "1.0.1",  # Changed
        "debug": true       # Changed
      }
    }
    writeFile(tmpFile, $updatedConfig)
    
    # Trigger manual reload (in real implementation, this would be automatic)
    configManager.reload()
    
    # Check that configuration was reloaded
    check(configManager.get("app.version") == "1.0.1")
    check(configManager.getBool("app.debug") == true)
    check(reloadCount == 1)
    check(lastConfig["app"]["version"].getStr() == "1.0.1")
    
    # Test reload error handling
    writeFile(tmpFile, "invalid json{")
    configManager.reload()
    
    # Configuration should remain unchanged on error
    check(configManager.get("app.version") == "1.0.1")
    check(reloadCount == 1)  # Callback not called on error
    
    # Clean up
    removeFile(tmpFile)
    
  test "Configuration encryption":
    # Set encryption key
    let encryptionKey = "my-secret-encryption-key-32-chars"
    configManager.setEncryptionKey(encryptionKey)
    
    # Original configuration with sensitive data
    let config = %*{
      "database": {
        "password": "super-secret-password",
        "api_key": "sk_live_123456789"
      },
      "app": {
        "name": "MyApp",
        "port": 8080
      }
    }
    
    # Mark fields for encryption
    configManager.markSensitive(@["database.password", "database.api_key"])
    
    # Encrypt configuration
    let encryptedConfig = configManager.encrypt(config)
    
    # Check that sensitive fields are encrypted
    check(encryptedConfig["database"]["password"].getStr() != "super-secret-password")
    check(encryptedConfig["database"]["api_key"].getStr() != "sk_live_123456789")
    check(encryptedConfig["database"]["password"].getStr().startsWith("enc:"))
    check(encryptedConfig["database"]["api_key"].getStr().startsWith("enc:"))
    
    # Non-sensitive fields remain unchanged
    check(encryptedConfig["app"]["name"].getStr() == "MyApp")
    check(encryptedConfig["app"]["port"].getInt() == 8080)
    
    # Decrypt configuration
    let decryptedConfig = configManager.decrypt(encryptedConfig)
    
    # Check that sensitive fields are decrypted correctly
    check(decryptedConfig["database"]["password"].getStr() == "super-secret-password")
    check(decryptedConfig["database"]["api_key"].getStr() == "sk_live_123456789")
    
    # Test auto-decryption when getting values
    configManager.loadJson(encryptedConfig)
    check(configManager.get("database.password") == "super-secret-password")
    check(configManager.get("database.api_key") == "sk_live_123456789")
    
    # Test encryption with wrong key
    configManager.setEncryptionKey("wrong-key-32-characters-long-xxx")
    expect(DecryptionError):
      discard configManager.decrypt(encryptedConfig)
    
  test "Environment-specific configuration":
    # Create multiple environment configurations
    let baseConfig = %*{
      "app": {
        "name": "MyApp",
        "version": "1.0.0"
      },
      "server": {
        "host": "localhost",
        "port": 8080
      }
    }
    
    let devConfig = %*{
      "server": {
        "host": "localhost",
        "port": 3000
      },
      "database": {
        "url": "sqlite://dev.db"
      },
      "debug": true
    }
    
    let prodConfig = %*{
      "server": {
        "host": "0.0.0.0",
        "port": 8080,
        "ssl": true
      },
      "database": {
        "url": "postgres://prod-db.example.com/myapp"
      },
      "debug": false
    }
    
    let testConfig = %*{
      "server": {
        "port": 4000
      },
      "database": {
        "url": "sqlite://:memory:"
      },
      "debug": false
    }
    
    # Register environments
    configManager.registerEnvironment("base", baseConfig)
    configManager.registerEnvironment("development", devConfig)
    configManager.registerEnvironment("production", prodConfig) 
    configManager.registerEnvironment("test", testConfig)
    
    # Set environment inheritance
    configManager.setEnvironmentInheritance("development", "base")
    configManager.setEnvironmentInheritance("production", "base")
    configManager.setEnvironmentInheritance("test", "development")
    
    # Test development environment
    configManager.setEnvironment("development")
    check(configManager.get("app.name") == "MyApp")  # From base
    check(configManager.get("server.host") == "localhost")  # From dev
    check(configManager.getInt("server.port") == 3000)  # From dev
    check(configManager.get("database.url") == "sqlite://dev.db")  # From dev
    check(configManager.getBool("debug") == true)  # From dev
    
    # Test production environment
    configManager.setEnvironment("production")
    check(configManager.get("app.name") == "MyApp")  # From base
    check(configManager.get("server.host") == "0.0.0.0")  # From prod
    check(configManager.getInt("server.port") == 8080)  # From prod
    check(configManager.getBool("server.ssl") == true)  # From prod
    check(configManager.get("database.url") == "postgres://prod-db.example.com/myapp")
    check(configManager.getBool("debug") == false)  # From prod
    
    # Test test environment (inherits from dev)
    configManager.setEnvironment("test")
    check(configManager.get("app.name") == "MyApp")  # From base
    check(configManager.get("server.host") == "localhost")  # From dev
    check(configManager.getInt("server.port") == 4000)  # From test
    check(configManager.get("database.url") == "sqlite://:memory:")  # From test
    check(configManager.getBool("debug") == false)  # From test
    
    # Test environment switching at runtime
    check(configManager.getCurrentEnvironment() == "test")
    
    # Switch back to development
    configManager.setEnvironment("development")
    check(configManager.getInt("server.port") == 3000)
    
    # Test undefined environment
    expect(ConfigError):
      configManager.setEnvironment("staging")
    
  test "Configuration composition and overlays":
    # Base configuration
    let base = %*{
      "app": {
        "name": "MyApp",
        "features": {
          "auth": true,
          "cache": false,
          "api": {
            "version": "v1",
            "rate_limit": 100
          }
        }
      }
    }
    
    # Overlay 1: Feature flags
    let featureFlags = %*{
      "app": {
        "features": {
          "cache": true,
          "beta": true,
          "api": {
            "rate_limit": 200
          }
        }
      }
    }
    
    # Overlay 2: Local overrides
    let localOverrides = %*{
      "app": {
        "features": {
          "api": {
            "version": "v2",
            "debug": true
          }
        }
      }
    }
    
    # Apply overlays
    configManager.loadJson(base)
    configManager.applyOverlay("features", featureFlags)
    configManager.applyOverlay("local", localOverrides)
    
    # Check merged configuration
    check(configManager.get("app.name") == "MyApp")  # From base
    check(configManager.getBool("app.features.auth") == true)  # From base
    check(configManager.getBool("app.features.cache") == true)  # From featureFlags
    check(configManager.getBool("app.features.beta") == true)  # From featureFlags
    check(configManager.get("app.features.api.version") == "v2")  # From localOverrides
    check(configManager.getInt("app.features.api.rate_limit") == 200)  # From featureFlags
    check(configManager.getBool("app.features.api.debug") == true)  # From localOverrides
    
    # Test overlay priority
    configManager.setOverlayPriority(@["local", "features"])
    
    # Remove and re-apply overlays in new order
    configManager.removeOverlay("features")
    configManager.removeOverlay("local")
    configManager.applyOverlay("features", featureFlags)
    configManager.applyOverlay("local", localOverrides)
    
    # Local should now have higher priority
    check(configManager.get("app.features.api.version") == "v2")  # From local (higher priority)
    
  test "Configuration macros and templates":
    # Configuration with templates
    let configWithTemplates = %*{
      "app": {
        "name": "MyApp",
        "version": "1.0.0"
      },
      "server": {
        "base_url": "http://localhost:${port}",
        "api_url": "${server.base_url}/api/${app.version}",
        "port": 8080
      },
      "database": {
        "url": "${DB_URL:-postgres://localhost/myapp}",
        "pool_size": "${DB_POOL_SIZE:-10}"
      }
    }
    
    # Set environment variables
    putEnv("DB_URL", "postgres://prod-db.example.com/myapp")
    
    # Process templates
    let processedConfig = configManager.processTemplates(configWithTemplates)
    
    # Check resolved values
    check(processedConfig["server"]["base_url"].getStr() == "http://localhost:8080")
    check(processedConfig["server"]["api_url"].getStr() == "http://localhost:8080/api/1.0.0")
    check(processedConfig["database"]["url"].getStr() == "postgres://prod-db.example.com/myapp")
    check(processedConfig["database"]["pool_size"].getStr() == "10")  # Default value
    
    # Test with environment variable set
    putEnv("DB_POOL_SIZE", "20")
    let processedConfig2 = configManager.processTemplates(configWithTemplates)
    check(processedConfig2["database"]["pool_size"].getStr() == "20")
    
    # Clean up
    delEnv("DB_URL")
    delEnv("DB_POOL_SIZE")