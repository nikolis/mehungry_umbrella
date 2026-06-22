defmodule Mix.Tasks.Knowledge.Schemas do
  use Mix.Task

  @shortdoc "Generate schema knowledge documentation"

  @relationship_types [
    :belongs_to,
    :has_many,
    :has_one,
    :many_to_many,
    :embeds_one,
    :embeds_many
  ]

  def run(_args) do
    Mix.shell().info("Generating schema documentation...")

    #File.mkdir_p!("docs/knowledge")
    IO.inspect(File.cwd())
    schemas =
      "apps"
      |> Path.join("**/*.ex")
      |> Path.wildcard()
      |> Enum.flat_map(&extract_schema/1)

    generate_schemas_md(schemas)
    generate_domain_graph_md(schemas)

    Mix.shell().info("Done.")
  end

  defp extract_schema(file) do
    source = File.read!(file)

    case Code.string_to_quoted(source) do
      {:ok, ast} ->
        walk_ast(ast)

      _ ->
        []
    end
  end

  defp walk_ast(ast) do
    {_ast, schemas} =
      Macro.prewalk(ast, [], fn
        {:defmodule, _, [module_ast, [do: body]]} = node, acc ->
          module_name = Macro.to_string(module_ast)

          schema =
            extract_schema_info(module_name, body)

          if schema do
            {node, [schema | acc]}
          else
            {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    schemas
  end

  defp extract_schema_info(module_name, body) do
    {_body, result} =
      Macro.prewalk(body, %{schema: nil, fields: [], relations: []}, fn
        {:schema, _, [table, [do: schema_block]]} = node, acc ->
          acc =
            schema_block
            |> extract_schema_block(acc)
            |> Map.put(:schema, table)

          {node, acc}

        node, acc ->
          {node, acc}
      end)

    if result.schema do
      %{
        module: module_name,
        table: result.schema,
        fields: Enum.reverse(result.fields),
        relations: Enum.reverse(result.relations)
      }
    end
  end

  defp extract_schema_block(ast, acc) do
    {_ast, acc} =
      Macro.prewalk(ast, acc, fn

        {:field, _, [name, type | _]} = node, acc ->
          field = %{
            name: name,
            type: Macro.to_string(type)
          }

          {node, %{acc | fields: [field | acc.fields]}}

        {rel_type, _, [name, target | _]} = node, acc
        when rel_type in @relationship_types ->

          relation = %{
            type: rel_type,
            name: name,
            target: Macro.to_string(target)
          }

          {node, %{acc | relations: [relation | acc.relations]}}

        {:timestamps, _, _} = node, acc ->
          field = %{
            name: :timestamps,
            type: "timestamps"
          }

          {node, %{acc | fields: [field | acc.fields]}}

        node, acc ->
          {node, acc}
      end)

    acc
  end

  defp generate_schemas_md(schemas) do
    content =
      schemas
      |> Enum.sort_by(& &1.module)
      |> Enum.map_join("\n\n", fn schema ->
        """
        ## #{schema.module}

        **Table:** `#{schema.table}`

        ### Fields

        #{format_fields(schema.fields)}

        ### Relationships

        #{format_relationships(schema.relations)}
        """
      end)

    File.write!("./docs/knowledge/schemas.md", "# Schema Inventory\n\n" <> content)
  end

  defp generate_domain_graph_md(schemas) do
    content =
      schemas
      |> Enum.sort_by(& &1.module)
      |> Enum.map_join("\n\n", fn schema ->
        relations =
          schema.relations
          |> Enum.map_join("\n", fn rel ->
            "- #{rel.type} #{rel.name} -> #{rel.target}"
          end)

        """
        ## #{schema.module}

        #{relations}
        """
      end)

    File.write!(
      "./docs/knowledge/domain_graph.md",
      "# Domain Graph\n\n" <> content
    )
  end

  defp format_fields([]), do: "_none_"

  defp format_fields(fields) do
    Enum.map_join(fields, "\n", fn field ->
      "- #{field.name}: #{field.type}"
    end)
  end

  defp format_relationships([]), do: "_none_"

  defp format_relationships(relations) do
    Enum.map_join(relations, "\n", fn rel ->
      "- #{rel.type} #{rel.name} -> #{rel.target}"
    end)
  end
end
