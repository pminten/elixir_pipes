defmodule PipeTest do
  use ExUnit.Case

  require Pipe
  alias Pipe, as: P

  test "yield to await with explicit connect" do
    assert (P.yield(4) |> P.connect(P.await())) == [4]
  end

  test "yield to conduit to await with explicit connect" do
    f = fn ->
      P.await() |> P.bind fn 
        [x] -> P.yield(x + 1)
        []  -> P.yield(nil)
      end
    end
    assert (P.yield(4) 
            |> P.connect(P.Conduit[step: f])
            |> P.connect(P.await())) == [5]
  end
  
  test "yield to conduit to await with explicit connect and do-notation" do
    f = fn source ->
          P.conduit(source) do
            r <- P.await()
            case r do
              [x] -> P.yield(x + 1)
              []  -> P.yield(nil)
            end
          end
        end
    assert (P.yield(4) |> f.() |> P.await()) == [5]

    # Again, in a shorter way.
    assert (P.yield(4) |>
            P.conduit do
              r <- P.await()
              case r do
                [x] -> P.yield(x + 1)
                []  -> P.yield(nil)
              end
            end |>
            P.await()) == [5]
  end
  
  test "yield to await with implicit connect" do
    assert (P.yield(4) |> P.await()) == [4]
  end

  test "await" do
    assert (P.done(1) |> P.connect(P.await())) == []
    assert (P.yield(1) |> P.await()) == [1]
  end
end
