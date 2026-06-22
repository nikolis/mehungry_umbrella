#!/bin/bash

echo "# Contexts" > docs/knowledge/contexts.md

find apps/mehungry/lib/mehungry \
  -name "*.ex" \
  | while read file
do
  if grep -q "defmodule" "$file"; then
    module=$(grep "defmodule" "$file" | head -1)

    echo "" >> docs/knowledge/contexts.md
    echo "## $module" >> docs/knowledge/contexts.md

    grep "^  def " "$file" >> docs/knowledge/contexts.md
  fi
done
