defmodule Pipe.ListTest do
  use ExUnit.Case

  require Pipe, as: P
  alias Pipe.List, as: PL

  test "map" do
    assert (P.yield(4) |> PL.map(&(&1+1)) |> P.await()) == [5]
    assert (P.return(0) |> PL.map(&(&1+1)) |> P.await()) == []
  end
end
