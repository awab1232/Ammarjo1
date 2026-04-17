#!/bin/bash
# zero_violation_check.sh
#
# Runs ONLY on Dart files that are staged for the current commit (lib/**/*.dart).
# This ensures backend-only commits are never blocked by pre-existing Flutter
# patterns, and avoids false positives from file paths used as string literals
# inside test/contract files.

echo "🔍 Running ZERO VIOLATION CHECK..."

# Collect staged dart files that live under lib/
STAGED_DART=$(git diff --cached --name-only --diff-filter=ACM | grep '^lib/.*\.dart$' || true)

if [ -z "$STAGED_DART" ]; then
  echo "✅ No staged lib/*.dart files — skipping Flutter violation scan."
  exit 0
fi

fail=0

check() {
  pattern=$1
  label=$2
  # Known exclusion: deterministic_guard.dart stores the forbidden strings as
  # string literals (test fixtures) — they are not real violations.
  EXCLUDE="lib/core/security/deterministic_guard.dart"

  matches=""
  while IFS= read -r f; do
    # Normalise path separator so the exclusion works on Linux CI too.
    normalized=$(echo "$f" | tr '\\' '/')
    if echo "$normalized" | grep -qF "$EXCLUDE"; then
      continue
    fi
    hits=$(grep -n "$pattern" "$f" 2>/dev/null || true)
    if [ -n "$hits" ]; then
      matches="$matches
$f: $hits"
    fi
  done <<EOF
$STAGED_DART
EOF

  count=$(echo "$matches" | grep -c '[^[:space:]]' || true)

  if [ "$count" -gt 0 ]; then
    echo "❌ $label found: $count"
    echo "$matches"
    fail=1
  else
    echo "✅ $label: 0"
  fi
}

check "Future<List"  "Future<List>"
check "Stream<List"  "Stream<List>"
check "return \[\]"  "return []"
check "\?\? \[\]"    "?? []"
check "snapshot\.data" "snapshot.data"
check "} catch (" "bare catch"

if [ "$fail" -ne 0 ]; then
  echo "🚫 BUILD FAILED — ZERO VIOLATION POLICY BREACHED"
  exit 1
else
  echo "🎉 ZERO VIOLATION PASSED"
fi
