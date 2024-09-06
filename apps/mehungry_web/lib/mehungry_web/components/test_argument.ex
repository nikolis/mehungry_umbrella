defmodule MehungryWeb.TestArgument do
  # In Phoenix apps, the line is typically: use MyAppWeb, :html
  use Phoenix.Component

  def tab_content(%{state: "first"} = assigns) do
    ~H"""
    <p>Hello, <%= @name %>!</p>
    """
  end

  def tab_content(%{state: "second"} = assigns) do
    ~H"""
    <p>Hello, <%= @name %>!</p>
    """
  end

  def tab_content(%{state: "third"} = assigns) do
    ~H"""
    <h3>Hello, <%= @name %>!</h3>
    """
  end


end
