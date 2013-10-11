defmodule PipeTest do
  use ExUnit.Case, async: true
  doctest Pipe

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
          P.connect(source, P.lazy_conduit do
            r <- P.await()
            case r do
              [x] -> P.yield(x + 1)
              []  -> P.yield(nil)
            end
          end)
        end
    assert (P.yield(4) |> f.() |> P.await()) == [5]
    # Again, in a shorter way.
    assert (P.yield(4) |>
            P.lazy_conduit_c do
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
  
  test "await_result" do
    assert (P.done(1) |> P.connect(P.await_result())) == { :result, 1 }
    assert (P.yield(1) |> P.await_result()) == { :value, 1 }
  end

  test "cleanup" do
    try do
      Process.put(:cleanup_1, false)
      Process.put(:cleanup_2, false)
      Process.put(:cleanup_3, false)
      assert (P.source do
                P.register_cleanup(fn -> Process.put(:cleanup_1, true) end)
                P.yield(1)
                P.yield(2)
                P.register_cleanup(fn -> Process.put(:cleanup_2, true) end)
                return 3
              end
              |> P.connect(P.sink do
                r <- P.await()
                P.register_cleanup(fn -> Process.put(:cleanup_3, true) end)
                return r
              end)) == [1]
      assert Process.get(:cleanup_1) == true
      # Execution never reached call to register_cleanup #2
      assert Process.get(:cleanup_2) == false
      assert Process.get(:cleanup_3) == true
    after
      Process.delete(:cleanup_1)
      Process.delete(:cleanup_2)
      Process.delete(:cleanup_3)
    end 
  end
end
