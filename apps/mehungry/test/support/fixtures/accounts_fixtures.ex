defmodule Mehungry.AccountsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Mehungry.Accounts` context.
  """

  def unique_user_email, do: "user#{System.unique_integer()}@example.com"
  def valid_user_password, do: "hello world!"

  def valid_user_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      email: unique_user_email(),
      password: valid_user_password()
    })
  end

  def user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> valid_user_attributes()
      |> Mehungry.Accounts.register_user()

    user
  end

  def extract_user_token(fun) do
    {:ok, captured_email} = fun.(&"[TOKEN]#{&1}[TOKEN]")
    [_, token | _] = String.split(captured_email.text_body, "[TOKEN]")
    token
  end

  @doc """
  Generate a user_category_rule.
  """
  def user_category_rule_fixture(attrs \\ %{}) do
    {:ok, user_category_rule} =
      attrs
      |> Enum.into(%{})
      |> Mehungry.Accounts.create_user_category_rule()

    user_category_rule
  end

  @doc """
  Generate a user_ingredient_rule.
  """
  def user_ingredient_rule_fixture(attrs \\ %{}) do
    {:ok, user_ingredient_rule} =
      attrs
      |> Enum.into(%{})
      |> Mehungry.Accounts.create_user_ingredient_rule()

    user_ingredient_rule
  end

  @doc """
  Generate a user_profile.
  """
  def user_profile_fixture(attrs \\ %{}) do
    {:ok, user_profile} =
      attrs
      |> Enum.into(%{
        alias: "some alias",
        intro: "some intro"
      })
      |> Mehungry.Accounts.create_user_profile()

    user_profile
  end
end
