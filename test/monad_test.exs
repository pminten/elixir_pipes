defmodule MonadTest do
  use ExUnit.Case

  defmodule Identity do
    @behaviour Macro.Monad

    def return(x), do: x
    def bind(x, f), do: f.(x)
  end

  defmacro identity(opts) do
    Macro.Monad.monad_do_notation(MonadTest.Identity, opts[:do])
  end

  test "no monad magic" do
    one = identity do 1 end
    assert one == 1
  end

  test "return" do
    one = identity do return 1 end
    assert one == 1
  end
  
  test "return >>= id" do
    one = identity do a <- return 1; a end
    assert one == 1
  end

  test "everything at once" do
    ten = identity do
      a <- return 1
      let b = 2
      let do 
        c = 3
        d = 4
      end
      return a + b + c + d
    end
    assert ten == 10
  end

end
