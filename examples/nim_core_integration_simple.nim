## Simple example demonstrating nim-lang-core integration
## Shows the basic enhanced features available

import ../src/nim_libaspects/cache
import ../src/nim_libaspects/config as libconfig
import std/strutils

echo "=== nim-lang-core Integration Demo ==="
echo ""

# 1. Enhanced cache with nim-lang-core backend
echo "1. Enhanced Cache Integration:"
let enhancedCache = newNimCoreCache[string, string](maxEntries = 100)
echo "  ✓ Created enhanced cache using nim-lang-core AST cache backend"
echo ""

# 2. Configuration with improvements
echo "2. Configuration Module:"
let config = libconfig.newConfig("APP_")
config.setDefault("port", 8080)
config.setDefault("host", "localhost")
config.setDefault("debug", true)
config.setDefault("timeout", 30)

# Get suggestions
let suggestions = config.suggestConfigImprovements()
echo "  Configuration suggestions:"
for suggestion in suggestions:
  echo "    - ", suggestion

# Generate schema
echo ""
echo "  Generated config schema preview:"
let schema = config.generateConfigSchema()
let lines = schema.split('\n')
for i, line in lines:
  if i < 4:
    echo "    ", line

echo ""
echo "=== Integration Features ==="
echo "✓ Enhanced caching with nim-lang-core AST cache"
echo "✓ Configuration validation and suggestions"
echo "✓ AI-powered code analysis (available in testing, profiler modules)"
echo "✓ Performance optimization recommendations"
echo ""
echo "See the source code for full API usage examples."