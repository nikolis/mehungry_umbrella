defmodule MehungryWeb.Api.DocsController do
  @moduledoc """
  Serves the public API's OpenAPI 3.0 spec and a Swagger UI page over it.

      GET /api/docs           → Swagger UI (HTML)
      GET /api/docs/openapi.json → the OpenAPI 3.0 document

  Both are unauthenticated so the docs are readable; the endpoints they describe
  are token-guarded (see the `bearerAuth` security scheme). Hand-written for now.

  Covers two surfaces: the static-token **Public API** (`GET /api/foundemental_foods`)
  and the per-user **Mobile API** (`/api/v1/**`, tag `mobile`). The mobile paths are
  summarized here; the full request/response contract lives in
  `docs/new_dec_specs/mobile_api_spec.md`.
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
          bearerAuth: %{type: "http", scheme: "bearer"},
          mobileBearerAuth: %{
            type: "http",
            scheme: "bearer",
            description: "Per-user token from POST /api/v1/auth/login (spec §3)."
          }
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
      tags: [
        %{name: "public", description: "Static-token system-integration API."},
        %{name: "mobile", description: "Per-user mobile API (/api/v1). See docs/new_dec_specs/mobile_api_spec.md."}
      ],
      paths: Map.merge(public_paths(), v1_paths())
    }
  end

  defp public_paths do
    %{
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
  end

  # Mobile API (/api/v1) — summarized; full contract in the markdown spec.
  defp v1_paths do
    public = [%{mobileBearerAuth: []}, %{}]
    secured = [%{mobileBearerAuth: []}]

    %{
      "/api/v1/auth/register" => op("post", "mobile", "Register + return a bearer token", [%{}]),
      "/api/v1/auth/login" => op("post", "mobile", "Log in + return a bearer token", [%{}]),
      "/api/v1/auth/oauth/{provider}" => op("post", "mobile", "Exchange a provider token for a bearer token", [%{}]),
      "/api/v1/auth/logout" => op("delete", "mobile", "Revoke the current token", secured),
      "/api/v1/me" => op("get", "mobile", "Current user + profile + tier + quota", secured),
      "/api/v1/me/profile" => op("put", "mobile", "Update profile", secured),
      "/api/v1/me/preferences" => op("get", "mobile", "Get onboarding/diet preferences", secured),
      "/api/v1/preferences/options" => op("get", "mobile", "Static onboarding vocabulary", public),
      "/api/v1/feed" => op("get", "mobile", "Home feed (paginated)", public),
      "/api/v1/recipes/{id}" => op("get", "mobile", "Recipe detail", public),
      "/api/v1/recipes" => op("post", "mobile", "Create a recipe", secured),
      "/api/v1/recipes/{recipe_id}/like" => op("post", "mobile", "Like a recipe", secured),
      "/api/v1/recipes/{recipe_id}/save" => op("post", "mobile", "Save a recipe", secured),
      "/api/v1/recipes/{recipe_id}/comments" => op("post", "mobile", "Comment on a recipe", secured),
      "/api/v1/users/{id}/follow" => op("post", "mobile", "Follow a user", secured),
      "/api/v1/search" => op("get", "mobile", "Recipe search", public),
      "/api/v1/ingredients/search" => op("get", "mobile", "USDA ingredient search", secured),
      "/api/v1/species" => op("get", "mobile", "List food species", public),
      "/api/v1/species/{slug}" => op("get", "mobile", "Species detail", public),
      "/api/v1/conditions" => op("get", "mobile", "List health conditions", public),
      "/api/v1/conditions/{id}" => op("get", "mobile", "Condition detail", public),
      "/api/v1/meals" => op("get", "mobile", "Weekly meal plan (start/end)", secured),
      "/api/v1/meals/plan-with-ai" => op("post", "mobile", "Async AI meal-plan generation (202)", secured),
      "/api/v1/basket" => op("get", "mobile", "Active shopping basket", secured),
      "/api/v1/basket/items" => op("post", "mobile", "Add a basket item", secured),
      "/api/v1/uploads/presign" => op("post", "mobile", "Presigned S3 upload URL", secured),
      "/api/v1/subscription" => op("get", "mobile", "Subscription info + plans + quota", secured),
      "/api/v1/subscription/checkout" => op("post", "mobile", "Stripe checkout URL", secured),
      "/api/v1/me/invitations" => op("get", "mobile", "Pending nutritionist invitations", secured),
      "/api/v1/feedback" => op("post", "mobile", "Submit app feedback (optional auth)", public),
      "/api/v1/nutritionist/clients" => op("get", "mobile", "List a nutritionist's clients (pro tier)", secured)
    }
  end

  # Compact OpenAPI operation object for a single method/path.
  defp op(method, tag, summary, security) do
    %{
      method => %{
        tags: [tag],
        summary: summary,
        security: security,
        responses: %{
          "200" => %{description: "Success"},
          "401" => %{description: "Missing or invalid token."}
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
