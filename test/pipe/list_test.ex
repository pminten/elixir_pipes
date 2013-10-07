defmodule Pipe.ListTest do
  use ExUnit.Case

  require Pipe, as: P
  alias Pipe.List, as: PL

  test "map" do
    assert (P.yield(4) |> PL.map(&(&1+1)) |> P.await_result()) == [5]
    assert (P.return(0) |> PL.map(&(&1+1)) |> P.await_result()) == []
    
    assert (P.yield(4) |> PL.map(&(&1+1)) |> P.skip_all()) == nil 
    assert (P.return(0) |> PL.map(&(&1+1)) |> P.skip_all()) == 0 
  end
  
  test "source_list, filter and consume" do
    assert (P.source_list([1,2,3,4]) |> PL.filter(&(rem(&1, 2) == 0)) |> P.consume()) == [2,4]
    assert (P.source_list([]) |> PL.filter(&(rem(&1, 2) == 0)) |> P.consume()) == []
    
    assert (P.source_list([1,2,3,4]) |> PL.filter(&(rem(&1, 2) == 0)) |> P.skip_all()) == nil
  end
end
