defmodule Mehungry.AI.ImageGenerator do
  @moduledoc """
  Builds the (model-agnostic) recipe-cover prompt and dispatches image
  generation to the backend selected by the `:recipe_image_provider` config:

    * `:openai` (default) — the OpenAI gpt-image-2 API, implemented here.
    * `:flux` — Black Forest Labs FLUX 2 pro, in `Mehungry.AI.FluxImageGenerator`.

  Both providers receive the same engineered prompt and return JPEG binary data
  ready to upload to object storage, so they are drop-in interchangeable and can
  be A/B'd on live recipes by flipping `RECIPE_IMAGE_PROVIDER`.
  """

  require Logger

  @api_url "https://api.openai.com/v1/images/generations"
  # gpt-image-2: quality-first successor to gpt-image-1 (which OpenAI retires on
  # 2026-10-23). Same /images/generations contract — size WxH (divisible by 16),
  # quality low|medium|high, output_format jpeg + output_compression, b64_json
  # response — so this is a drop-in model swap.
  @model "gpt-image-2"
  # Landscape 3:2 — recipe covers render as landscape/aspect-video across the app,
  # so a square image just gets cropped. Generating landscape keeps the framing
  # the model composed and stops throwing away resolution.
  @size "1536x1024"
  @default_quality "medium"
  @valid_qualities ~w(low medium high)
  # JPEG at a fixed compression so we control output quality/size instead of
  # silently relabeling the model's default PNG bytes as image/jpeg.
  @output_format "jpeg"
  @output_compression 90
  @timeout_ms 90_000

  @doc """
  Generates a food photo for the given recipe title and description.

  Options:

    * `:cuisine` — drives the visual styling (tableware, surface, background,
      palette) so photos stop converging on the old hardcoded warm/rustic
      "amber" look. Omit or pass `nil` when the cuisine is unknown.
    * `:quality` — `"low" | "medium" | "high"` (default `"medium"`). The caller
      picks the tier; see `Mehungry.RecipeImageWorker`.
    * `:provider` — `:openai | :flux`, forces a specific backend and bypasses the
      configured default. Used by the owner "regenerate with the alternative
      provider" action; omit to use the configured provider.

  Returns `{:ok, jpeg_binary}` or `{:error, reason}`.
  """
  @spec generate(String.t(), String.t(), keyword()) ::
          {:ok, binary()} | {:error, term()}
  def generate(title, description, opts \\ []) do
    cuisine = Keyword.get(opts, :cuisine)
    quality = normalize_quality(Keyword.get(opts, :quality, @default_quality))

    # The prompt is model-agnostic — the exact same engineered prompt feeds
    # whichever provider is configured, so swapping backends never silently
    # changes what we ask for.
    prompt = build_prompt(title, description, cuisine)
    # Provider precedence: explicit :provider opt → admin DB toggle →
    # RECIPE_IMAGE_PROVIDER env → :openai.
    provider =
      case Keyword.get(opts, :provider) do
        p when p in [:openai, :flux] -> p
        _ -> Mehungry.Settings.image_provider()
      end

    Logger.info(
      "ImageGenerator: generating image for '#{title}' via #{provider}" <>
        "#{quality_note(provider, quality)}#{cuisine && " (#{cuisine})"}"
    )

    case provider do
      :flux -> Mehungry.AI.FluxImageGenerator.generate(prompt, quality: quality)
      _ -> generate_openai(prompt, quality)
    end
  end

  defp quality_note(:openai, quality), do: " (#{quality} quality)"
  defp quality_note(_, _), do: ""

  defp generate_openai(prompt, quality) do
    api_key = Application.get_env(:mehungry, :openai_api_key, "")

    if api_key == "" do
      {:error, "OPENAI_API_KEY is not configured"}
    else
      request_image(api_key, prompt, quality)
    end
  end

  # ── internals ─────────────────────────────────────────────────────────────────

  defp normalize_quality(quality) when quality in @valid_qualities, do: quality
  defp normalize_quality(_), do: @default_quality

  defp build_prompt(title, description, cuisine) do
    clean_desc =
      description
      |> to_string()
      |> String.replace(~r/#\S+/, "")
      |> String.trim()

    # Goal: an image indistinguishable from a real photo a person took of the
    # plate — NOT a glossy studio/editorial shoot (that over-styled look is the
    # tell of an AI image). So we chase authentic realism, and we describe the
    # finished plated dish, never a list of ingredients (naming ingredients makes
    # the model scatter raw items across the frame).
    "A candid, realistic photo of #{title}, a single finished dish plated and " <>
      "ready to eat, as if a person snapped it at the table just before eating. " <>
      "#{clean_desc}. " <>
      "Depict exactly this one dish so it is immediately and unambiguously " <>
      "recognisable as #{title} — commit to a single, definite interpretation of " <>
      "the dish rather than a vague, generic, or hybrid plate. Keep the composition " <>
      "clear: recognisable components at realistic scale and proportion, no merged, " <>
      "morphed, or unidentifiable elements, one plate as the sole subject. " <>
      "Looks like a genuine everyday photo, not a professional studio or magazine " <>
      "shoot: natural imperfections, true-to-life colours and portion sizes, real " <>
      "authentic tableware, honest home or restaurant table setting. " <>
      cuisine_setting(cuisine) <>
      "Shot handheld on a modern smartphone in soft natural ambient light from a " <>
      "casual 45-degree angle, natural white balance. Frame tightly on the plated " <>
      "dish so it fills most of the image and reads as the clear subject, keeping " <>
      "any small, fiddly garnishes minimal. " <>
      "Appetising but understated and believable — avoid the over-styled, glossy, " <>
      "hyper-saturated, perfectly-symmetrical CGI look; no artificial perfection. " <>
      "No scattered raw ingredients, no text overlays, no watermarks. " <>
      "Photorealistic, indistinguishable from a real photograph."
  end

  # Derive the setting from the cuisine rather than hardcoding one look. The
  # explicit "do not default to warm amber tones" is what breaks the old
  # every-photo-looks-the-same problem.
  defp cuisine_setting(cuisine) when is_binary(cuisine) and cuisine != "" do
    "Styled authentically for #{cuisine} cuisine: use tableware, serving vessels, " <>
      "surface, and background that genuinely belong to #{cuisine} food culture, with " <>
      "a colour palette true to how this food really looks — do NOT default to warm " <>
      "amber/golden tones. "
  end

  defp cuisine_setting(_),
    do:
      "Plated simply and realistically on a surface that suits the dish; let the palette " <>
        "follow the food itself rather than defaulting to warm amber/golden tones. "

  defp request_image(api_key, prompt, quality) do
    body =
      Jason.encode!(%{
        model: @model,
        prompt: prompt,
        n: 1,
        size: @size,
        quality: quality,
        output_format: @output_format,
        output_compression: @output_compression
      })

    headers = [
      {"Content-Type", "application/json"},
      {"Authorization", "Bearer #{api_key}"}
    ]

    case HTTPoison.post(@api_url, body, headers, recv_timeout: @timeout_ms) do
      {:ok, %HTTPoison.Response{status_code: 200, body: resp_body}} ->
        case Jason.decode(resp_body) do
          {:ok, %{"data" => [%{"b64_json" => b64} | _]}} ->
            {:ok, Base.decode64!(b64)}

          {:ok, unexpected} ->
            Logger.warning("ImageGenerator: unexpected response: #{inspect(unexpected)}")
            {:error, "Unexpected OpenAI response format"}

          {:error, reason} ->
            {:error, "Failed to parse OpenAI response: #{inspect(reason)}"}
        end

      {:ok, %HTTPoison.Response{status_code: code, body: resp_body}} ->
        Logger.warning("ImageGenerator: OpenAI error #{code}: #{resp_body}")
        {:error, "OpenAI API returned status #{code}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.warning("ImageGenerator: HTTP error: #{inspect(reason)}")
        {:error, "HTTP request failed: #{inspect(reason)}"}
    end
  end
end
