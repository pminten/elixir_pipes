defmodule PipeTest do
  use ExUnit.Case

  import Pipe

  test "simple" do
    # producer -> consumer
    assert run(yield(4) |> connect(await())) == 4
    # producer -> transformer -> consumer
    assert run(yield(4) 
               |> connect(await() |> bind(&yield(&1+1)))
               |> connect(await())) == 5
  end

  test "await" do
    assert run(return(1) |> connect(await())) == nil
    assert run(return(1) |> connect(await(&[&1]))) == nil
    assert run(return(1) |> connect(await(&[&1], []))) == []
    assert run(yield(1) |> connect(await(&[&1], []))) == [1]
  end
end
