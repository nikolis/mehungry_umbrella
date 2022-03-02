defmodule MehungryApiTest do
  use ExUnit.Case
  doctest MehungryApi

  test "greets the world" do
    assert MehungryApi.hello() == :world
  end
end
