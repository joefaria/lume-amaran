#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
mkdir -p .build/tests .build/clang .build/swift
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang"
export SWIFT_MODULECACHE_PATH="$PWD/.build/swift"
node Tests/vectors.mjs .build/vectors.json
xcrun swiftc -swift-version 5 -O -module-cache-path "$SWIFT_MODULECACHE_PATH" Sources/Mesh.swift Sources/Pairing.swift Sources/Configuration.swift Tests/ProtocolTests.swift -o .build/tests/protocol-tests -framework Security -lsqlite3
.build/tests/protocol-tests "$PWD/.build/vectors.json" "$PWD/.build/tests"
