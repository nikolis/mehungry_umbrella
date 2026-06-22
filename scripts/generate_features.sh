#!/bin/bash

echo "# Features" > docs/knowledge/features.md

for dir in apps/mehungry/lib/mehungry/*
do
  [ -d "$dir" ] || continue

  feature=$(basename "$dir")

  echo "" >> docs/knowledge/features.md
  echo "## $feature" >> docs/knowledge/features.md

  find "$dir" -name "*.ex" \
      | sed 's/^/- /' \
      >> docs/knowledge/features.md
done
