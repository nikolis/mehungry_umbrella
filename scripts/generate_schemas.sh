#!/usr/bin/env bash

set -e

OUTPUT_DIR="docs/knowledge"

SCHEMAS_FILE="$OUTPUT_DIR/schemas.md"
GRAPH_FILE="$OUTPUT_DIR/domain_graph.md"

mkdir -p "$OUTPUT_DIR"

echo "# Schema Inventory" > "$SCHEMAS_FILE"
echo "" >> "$SCHEMAS_FILE"

echo "# Domain Relationship Graph" > "$GRAPH_FILE"
echo "" >> "$GRAPH_FILE"

find apps -type f -name "*.ex" | while read -r file
do

if ! grep -q 'schema "' "$file"; then
continue
fi

MODULE=$(grep 'defmodule ' "$file" | head -1 | sed 's/.*defmodule //' | sed 's/ do//')

TABLE=$(grep 'schema "' "$file" | head -1 | sed 's/.*schema "//' | sed 's/".*//')

echo "## $MODULE" >> "$SCHEMAS_FILE"
echo "" >> "$SCHEMAS_FILE"

echo "**Table:** `$TABLE`" >> "$SCHEMAS_FILE"
echo "" >> "$SCHEMAS_FILE"

echo "### Fields" >> "$SCHEMAS_FILE"
echo "" >> "$SCHEMAS_FILE"

grep -E 'field :|timestamps(' "$file" | sed 's/^/- /' 
>> "$SCHEMAS_FILE" || true

echo "" >> "$SCHEMAS_FILE"

echo "### Relationships" >> "$SCHEMAS_FILE"
echo "" >> "$SCHEMAS_FILE"

grep -E 
'belongs_to :|has_many :|has_one :|many_to_many :|embeds_one :|embeds_many :' "$file" | sed 's/^/- /' 
>> "$SCHEMAS_FILE" || true

echo "" >> "$SCHEMAS_FILE"

##################################################

# DOMAIN GRAPH

##################################################

echo "## $MODULE" >> "$GRAPH_FILE"
echo "" >> "$GRAPH_FILE"

grep -E 
'belongs_to :|has_many :|has_one :|many_to_many :|embeds_one :|embeds_many :' "$file" | while read -r relation
do
echo "- $relation" >> "$GRAPH_FILE"
done

echo "" >> "$GRAPH_FILE"

done

echo "Generated:"
echo "  $SCHEMAS_FILE"
echo "  $GRAPH_FILE"

