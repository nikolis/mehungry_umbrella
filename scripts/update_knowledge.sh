#!/bin/bash

mkdir -p docs/knowledge

tree lib > docs/knowledge/project_tree.md

mix phx.routes \
  > docs/knowledge/routes.md

mix deps.tree \
  > docs/knowledge/dependencies.md

./scripts/generate_contexts.sh

mix knowledge.schemas

./scripts/generate_features.sh
