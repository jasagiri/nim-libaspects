## Simplified test for extended configuration features
import unittest
import json
import strutils
import nim_libaspects/config_extended
import nim_libaspects/errors
import results

suite "Simple Configuration Tests":
  var mgr: ConfigManager
  
  setup:
    mgr = newConfigManager()
  
  test "Basic validation works":
    let schema = %*{
      "server": {
        "type": "object",
        "properties": {
          "port": {
            "type": "integer",
            "required": true
          }
        }
      }
    }
    
    mgr.setSchema(schema)
    
    # Valid config
    let validConfig = %*{
      "server": {
        "port": 8080
      }
    }
    
    let validResult = mgr.validate(validConfig)
    check(validResult.isOk)
    
    # Invalid config - missing required field
    let invalidConfig = %*{
      "server": {
        # missing port
      }
    }
    
    let invalidResult = mgr.validate(invalidConfig)
    check(invalidResult.isErr)