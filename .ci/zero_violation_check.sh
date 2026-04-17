#!/bin/bash

echo "🔍 Running ZERO VIOLATION CHECK..."

fail=0

check() {
  pattern=$1
  label=$2

  count=$(grep -R "$pattern" lib/ | wc -l)

  if [ "$count" -ne 0 ]; then
    echo "❌ $label found: $count"
    grep -R "$pattern" lib/
    fail=1
  else
    echo "✅ $label: 0"
  fi
}

check "Future<List" "Future<List>"
check "Stream<List" "Stream<List>"
check "return \[\]" "return []"
check "\?\? \[\]" "?? []"
check "snapshot\.data" "snapshot.data"
check "catch (" "catch"

if [ "$fail" -ne 0 ]; then
  echo "🚫 BUILD FAILED — ZERO VIOLATION POLICY BREACHED"
  exit 1
else
  echo "🎉 ZERO VIOLATION PASSED"
fi
