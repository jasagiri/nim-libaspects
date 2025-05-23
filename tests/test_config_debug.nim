## Debug test for configuration validation
import json
import nim_libaspects/config_extended
import nim_libaspects/errors
import results

# Test validation
let mgr = newConfigManager()

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

# Test with invalid config - missing required field
let invalidConfig = %*{
  "server": {
    # missing port
  }
}

let result = mgr.validate(invalidConfig)
echo "Result isOk: ", result.isOk
echo "Result isErr: ", result.isErr  
if result.isErr:
  echo "Error message: ", result.error().msg
else:
  echo "Validation passed unexpectedly"

# Print the schema to debug
echo "\nSchema: ", pretty(mgr.schema)
echo "\nConfig: ", pretty(invalidConfig)