defmodule NativeTest do
  use ExUnit.Case
  doctest Native

  test "greets the world" do
    assert Native.hello() == :world
  end
end
