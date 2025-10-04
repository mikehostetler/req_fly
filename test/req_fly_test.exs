defmodule ReqFlyTest do
  use ExUnit.Case
  doctest ReqFly

  test "greets the world" do
    assert ReqFly.hello() == :world
  end
end
