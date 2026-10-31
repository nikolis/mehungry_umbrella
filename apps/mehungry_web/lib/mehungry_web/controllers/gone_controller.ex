defmodule MehungryWeb.GoneController do
  @moduledoc """
  Returns `410 Gone` for URLs that were once public but have been permanently
  retired, so search engines de-index them promptly.

  Currently serves the retired public condition pages (`/:locale/conditions/*`).
  These were moved behind the nutritionist panel (`/nutritionist/conditions`) on
  2026-10-14 because condition-specific dietary advice makes the app a regulated
  medical device (EU MDR / YMYL) we can't publish publicly yet — see the notices
  in `CLAUDE.md` (Health context) and `docs/growth/seo.md`. They already 404; a 410 is
  the explicit "permanently gone, drop it" signal (404 reads as possibly
  temporary, so Google re-checks it for longer).
  """
  use MehungryWeb, :controller

  def gone(conn, _params) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(410, "410 Gone — this page has been permanently removed.")
    |> halt()
  end
end
