defmodule MehungryWeb.LiveUtils do
  @moduledoc """
  A modolue to keep small utils functions for live views
  """

  @doc """
  Created out of the need fot getting certain structures only when a user
  exists in the current session or nil for example a comment pre-populated stru  cture that will enable the a comment form
  """
  def get_when_first_exists(nil, _reutn_func) do
    nil
  end

  def get_when_first_exists(_control_variable, return_func) do
    return_func.()
  end
end
