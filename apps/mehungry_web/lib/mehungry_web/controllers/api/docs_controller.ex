defmodule MehungryWeb.Api.DocsController do
  @moduledoc """
  Serves the public API's OpenAPI 3.0 spec and a Swagger UI page over it.

      GET /api/docs           → Swagger UI (HTML)
      GET /api/docs/openapi.json → the OpenAPI 3.0 document

  Both are unauthenticated so the docs are readable; the endpoints they describe
  are token-guarded (see the `bearerAuth` security scheme). Hand-written for now —
  currently documents only `GET /api/foundemental_foods`.
  """
  use MehungryWeb, :controller

  @swagger_ui_version "5.17.14"

  def openapi(conn, _params) do
    json(conn, spec())
  end

  def ui(conn, _params) do
    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, ui_html())
  end

  defp spec do
    %{
      openapi: "3.0.3",
      info: %{
        title: "Mehungry Public API",
        version: "1.0.0",
        description:
          "System-integration REST API. All endpoints require a static bearer token " <>
            "(`Authorization: Bearer <token>`)."
      },
      components: %{
        securitySchemes: %{
          bearerAuth: %{type: "http", scheme: "bearer"}
        },
        schemas: %{
          FoundementalFood: %{
            type: "object",
            description: "A fundamental food species with all stored fields.",
            properties: %{
              id: %{type: "integer", example: 1},
              name: %{type: "string", example: "Apple"},
              variety: %{type: "string", nullable: true, example: "Gala"},
              alternative_name: %{type: "string", nullable: true, example: "Malus"},
              scientific_name: %{
                type: "string",
                nullable: true,
                example: "Malus domestica"
              },
              family: %{type: "string", nullable: true, example: "Rosaceae"},
              inserted_at: %{type: "string", format: "date-time"},
              updated_at: %{type: "string", format: "date-time"}
            },
            required: ["id", "name", "inserted_at", "updated_at"]
          }
        }
      },
      security: [%{bearerAuth: []}],
      paths: %{
        "/api/foundemental_foods" => %{
          get: %{
            operationId: "listFoundementalFoods",
            summary: "List all fundamental food species",
            description:
              "Returns every fundamental food species with all stored data, name-ordered.",
            security: [%{bearerAuth: []}],
            responses: %{
              "200" => %{
                description: "The full list of species.",
                content: %{
                  "application/json" => %{
                    schema: %{
                      type: "object",
                      properties: %{
                        data: %{
                          type: "array",
                          items: %{"$ref" => "#/components/schemas/FoundementalFood"}
                        }
                      },
                      required: ["data"]
                    }
                  }
                }
              },
              "401" => %{description: "Missing or invalid bearer token."}
            }
          }
        }
      }
    }
  end

  defp ui_html do
    spec_url = "/api/docs/openapi.json"
    base = "https://unpkg.com/swagger-ui-dist@#{@swagger_ui_version}"

    """
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>Mehungry Public API — Docs</title>
        <link rel="stylesheet" href="#{base}/swagger-ui.css" />
      </head>
      <body>
        <div id="swagger-ui"></div>
        <script src="#{base}/swagger-ui-bundle.js"></script>
        <script>
          window.onload = function () {
            window.ui = SwaggerUIBundle({
              url: "#{spec_url}",
              dom_id: "#swagger-ui"
            });
          };
        </script>
      </body>
    </html>
    """
  end
end
