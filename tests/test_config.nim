import unittest
import ../src/nim_libaspects/config
import std/[json, os, tempfiles, strutils]

suite "Config Module Tests":
  test "ConfigValue types":
    # Test different ConfigValue types
    let nullVal = ConfigValue(kind: cvkNull)
    check nullVal.kind == cvkNull
    
    let boolVal = ConfigValue(kind: cvkBool, boolVal: true)
    check boolVal.kind == cvkBool
    check boolVal.boolVal == true
    
    let intVal = ConfigValue(kind: cvkInt, intVal: 42)
    check intVal.kind == cvkInt
    check intVal.intVal == 42
    
    let floatVal = ConfigValue(kind: cvkFloat, floatVal: 3.14)
    check floatVal.kind == cvkFloat
    check floatVal.floatVal == 3.14
    
    let stringVal = ConfigValue(kind: cvkString, stringVal: "test")
    check stringVal.kind == cvkString
    check stringVal.stringVal == "test"
  
  test "JSON to ConfigValue conversion":
    let jsonStr = """{"name": "test", "port": 8080, "enabled": true}"""
    let jsonNode = parseJson(jsonStr)
    let configVal = jsonNode.toConfigValue()
    
    check configVal.kind == cvkObject
    check configVal["name"].stringVal == "test"
    check configVal["port"].intVal == 8080
    check configVal["enabled"].boolVal == true
  
  test "Basic config operations":
    let config = newConfig()
    
    # Set defaults
    config.setDefault("host", "localhost")
    config.setDefault("port", 8080)
    config.setDefault("debug", false)
    
    # Get values
    check config.getString("host") == "localhost"
    check config.getInt("port") == 8080
    check config.getBool("debug") == false
    
    # Non-existent keys
    check config.getString("missing", "default") == "default"
    check config.getInt("missing", 999) == 999
  
  test "Load JSON config":
    let config = newConfig()
    
    # Create temporary JSON config file
    let (file, path) = createTempFile("config_", ".json")
    file.write("""{"server": {"host": "example.com", "port": 3000}}""")
    file.close()
    
    # Load config
    let result = config.loadJson(path)
    check result.isOk
    
    # Check values
    let serverSection = config.getSection("server")
    check serverSection.isOk
    
    let server = serverSection.get()
    check server.getString("host") == "example.com"
    check server.getInt("port") == 3000
    
    # Cleanup
    removeFile(path)
  
  test "Load TOML config":
    let config = newConfig()
    
    # Create temporary TOML config file
    let (file, path) = createTempFile("config_", ".toml")
    file.write("""
[database]
host = "db.example.com"
port = 5432
ssl = true
""")
    file.close()
    
    # Load config
    let result = config.loadToml(path)
    check result.isOk
    
    # Check values
    let dbSection = config.getSection("database")
    check dbSection.isOk
    
    let db = dbSection.get()
    check db.getString("host") == "db.example.com"
    check db.getInt("port") == 5432
    check db.getBool("ssl") == true
    
    # Cleanup
    removeFile(path)
  
  test "Environment variable loading":
    # Set test env vars
    putEnv("TEST_APP_SERVER_HOST", "env.example.com")
    putEnv("TEST_APP_SERVER_PORT", "9000")
    
    let config = newConfig(envPrefix = "TEST_APP_")
    let result = config.loadEnv()
    check result.isOk
    
    # Check values (env vars are lowercased and prefix is stripped)
    check config.getString("server_host") == "env.example.com"
    check config.getString("server_port") == "9000"
    
    # Cleanup
    delEnv("TEST_APP_SERVER_HOST")
    delEnv("TEST_APP_SERVER_PORT")
  
  test "Command line argument loading":
    let config = newConfig()
    
    # Simulate command line args
    let args = @["--host", "cli.example.com", "--port", "7000", "--verbose"]
    let result = config.loadCommandLine(args)
    check result.isOk
    
    
    # Check values
    check config.getString("host") == "cli.example.com"
    check config.getString("port") == "7000"
    check config.getBool("verbose") == true
  
  test "Config cascading":
    let config = newConfig(envPrefix = "TEST_")
    
    # Set defaults (lowest priority)
    config.setDefault("host", "default.com")
    config.setDefault("port", 1000)
    config.setDefault("debug", false)
    
    # Create config file (medium priority)
    let (file, path) = createTempFile("cascade_", ".json")
    file.write("""{"host": "file.com", "port": 2000}""")
    file.close()
    
    # Set env var (higher priority)
    putEnv("TEST_PORT", "3000")
    
    # Load cascade (file + env, no command line)
    let result = config.loadCascade(@[path], loadEnv = true, loadCmdLine = false)
    check result.isOk
    
    
    # Check cascaded values
    check config.getString("host") == "file.com"  # From file (overrides default)
    check config.getInt("port") == 3000          # From env (overrides file)
    check config.getBool("debug") == false       # From default (not overridden)
    
    # Cleanup
    removeFile(path)
    delEnv("TEST_PORT")
  
  test "Config merging":
    let config1 = newConfig()
    config1.setDefault("a", "1")
    config1.setDefault("b", "2")
    
    let config2 = newConfig()
    config2.setDefault("b", "22")
    config2.setDefault("c", "3")
    
    # Merge config2 into config1
    config1.merge(config2)
    
    check config1.getString("a") == "1"   # Original
    check config1.getString("b") == "22"  # Overwritten
    check config1.getString("c") == "3"   # Added
  
  test "Nested configuration access":
    let config = newConfig()
    
    # Create nested structure using JSON
    let (file, path) = createTempFile("nested_", ".json")
    file.write("""
{
  "app": {
    "name": "MyApp",
    "version": "1.0.0",
    "features": {
      "auth": true,
      "cache": false
    }
  }
}
""")
    file.close()
    
    let result = config.loadJson(path)
    check result.isOk
    
    # Access nested values
    let appSection = config.getSection("app")
    check appSection.isOk
    
    let app = appSection.get()
    check app.getString("name") == "MyApp"
    check app.getString("version") == "1.0.0"
    
    # Access deeply nested values
    let featuresSection = app.getSection("features")
    check featuresSection.isOk
    
    let features = featuresSection.get()
    check features.getBool("auth") == true
    check features.getBool("cache") == false
    
    # Cleanup
    removeFile(path)
  
  test "Error handling":
    let config = newConfig()
    
    # Non-existent file
    let result1 = config.loadJson("non_existent.json")
    check result1.isErr
    check "not found" in result1.error().msg
    
    # Invalid JSON
    let (file, path) = createTempFile("invalid_", ".json")
    file.write("{invalid json}")
    file.close()
    
    let result2 = config.loadJson(path)
    check result2.isErr
    check "parse" in result2.error().msg.toLowerAscii()
    
    # Cleanup
    removeFile(path)
  
  test "Config string representation":
    let config = newConfig()
    config.setDefault("key1", "value1")
    config.setDefault("key2", 42)
    
    let str = $config
    check "key1: value1" in str
    check "key2: 42" in str
    check "source: " in str  # Should show source info