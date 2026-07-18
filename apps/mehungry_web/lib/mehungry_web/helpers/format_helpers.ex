defmodule MehungryWeb.FormatHelpers do
  @moduledoc """
  Shared display-formatting helpers for LiveViews.

  Only helpers whose duplicated copies were byte-identical live here; views
  with intentionally different formats (e.g. the per-dashboard `format_dt`
  variants, the Greek-aware `CalendarLive.Calendar.Locale.month_name/2`)
  keep their local versions.
  """

  @doc "English month name for a 1-12 month number."
  def month_name(1), do: "January"
  def month_name(2), do: "February"
  def month_name(3), do: "March"
  def month_name(4), do: "April"
  def month_name(5), do: "May"
  def month_name(6), do: "June"
  def month_name(7), do: "July"
  def month_name(8), do: "August"
  def month_name(9), do: "September"
  def month_name(10), do: "October"
  def month_name(11), do: "November"
  def month_name(12), do: "December"
  def month_name(_), do: "Unknown"

  @doc "Truncates `text` to `max` characters, appending an ellipsis."
  def truncate(nil, _), do: "—"

  def truncate(text, max) do
    if String.length(text) > max, do: String.slice(text, 0, max) <> "…", else: text
  end
end
