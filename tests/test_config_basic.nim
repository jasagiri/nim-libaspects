## Basic test for extended configuration features
import unittest
import json
import strformat
import strutils
import results
import nim_libaspects/config_extended

suite "Basic Configuration Management":
  var mgr: ConfigManager
  
  setup:
    mgr = newConfigManager()
    
  test "Basic validation":
    # Set simple schema
    let schema = %*{
      "server": {
        "type": "object",
        "properties": {
          "host": {"type": "string"},
          "port": {"type": "integer", "minimum": 1, "maximum": 65535}
        }
      }
    }
    
    mgr.setSchema(schema)
    
    # Valid config
    let validConfig = %*{
      "server": {
        "host": "localhost",
        "port": 8080
      }
    }
    
    let result = mgr.validate(validConfig)
    check(result.isOk())
    
    # Invalid config - wrong type
    let invalidConfig = %*{
      "server": {
        "host": "localhost",
        "port": "8080"  # String instead of integer
      }
    }
    
    let invalidResult = mgr.validate(invalidConfig)
    check(invalidResult.isErr())
    
  test "Basic encryption":
    mgr.setEncryptionKey("testkey")
    mgr.markSensitive(@["password"])
    
    let originalConfig = %*{
      "username": "admin",
      "password": "secret123"
    }
    
    # Encrypt
    let encryptedConfig = mgr.encrypt(originalConfig)
    check(encryptedConfig["password"].getStr().startsWith("enc:"))
    check(encryptedConfig["username"].getStr() == "admin")
    
    # Decrypt
    let decryptedConfig = mgr.decrypt(encryptedConfig)
    check(decryptedConfig["password"].getStr() == "secret123")
    check(decryptedConfig["username"].getStr() == "admin")
    
  test "Basic environment management":
    let baseConfig = %*{
      "app": {
        "name": "MyApp",
        "version": "1.0.0"
      }
    }
    
    let devConfig = %*{
      "app": {
        "debug": true
      },
      "server": {
        "port": 3000
      }
    }
    
    mgr.registerEnvironment("base", baseConfig)
    mgr.registerEnvironment("dev", devConfig)
    mgr.setEnvironmentInheritance("dev", "base")
    
    mgr.setEnvironment("dev")
    check(mgr.getCurrentEnvironment() == "dev")
    check(mgr.get("app.name") == "MyApp")  # From base
    check(mgr.getBool("app.debug") == true)  # From dev
    check(mgr.getInt("server.port") == 3000)  # From dev
    
  test "Basic overlay management":
    let baseConfig = %*{
      "app": {
        "name": "MyApp",
        "features": {
          "auth": true,
          "cache": false
        }
      }
    }
    
    mgr.loadJson(baseConfig)
    
    let overlay = %*{
      "app": {
        "features": {
          "cache": true,
          "beta": true
        }
      }
    }
    
    mgr.applyOverlay("features", overlay)
    
    check(mgr.get("app.name") == "MyApp")
    check(mgr.getBool("app.features.auth") == true)  # From base
    check(mgr.getBool("app.features.cache") == true)  # From overlay
    check(mgr.getBool("app.features.beta") == true)  # From overlay
    
  test "Basic template processing":
    let configWithTemplates = %*{
      "app": {
        "name": "MyApp",
        "version": "1.0.0"
      },
      "server": {
        "base_url": "http://localhost:${port}",
        "api_url": "${server.base_url}/api/${app.version}",
        "port": 8080
      }
    }
    
    let processed = mgr.processTemplates(configWithTemplates)
    
    check(processed["server"]["base_url"].getStr() == "http://localhost:8080")
    check(processed["server"]["api_url"].getStr() == "http://localhost:8080/api/1.0.0")