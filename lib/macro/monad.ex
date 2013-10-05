defmodule Macro.Monad do
  use Behaviour

  @moduledoc """
  Helpers for writing monadic do-notation macros.

  ## Examples

      defmacro pipe(opts) do
        Macro.Monad.monad_do_notation(Pipe, opts[:do])
      end
  """
  @doc """
  Given a module which implements Macro.Monad parse the do-block and return an
  appropriate AST.
  """
  def monad_do_notation(mod, do_block)
  def monad_do_notation(mod, nil) do
    raise ArgumentError, message: "no or empty do block"
  end
  def monad_do_notation(mod, {:__block__, meta, exprs}) do
    process_exprs(mod, meta, exprs)
  end
  def monad_do_notation(mod, expr) do
    process_exprs(mod, [], [expr])
  end

  defp process_exprs(mod, meta, exprs) do
    # The import makes return work. It's a lot cleaner than trying to parse it
    # out of the AST plus it automatically works well with scoping.
    x = { :__block__, meta,
      [quote do import unquote(mod), only: [return: 1] end | do_process_exprs(mod, exprs)] }
    # To inspect the conversion this works well:
    #   x = <result of the conversion>
    #   IO.puts(x |> Macro.to_string)
    #   x
  end

  defp do_process_exprs(mod, []) do
    []
  end
  defp do_process_exprs(mod, [expr]) do
    [expr]
  end
  defp do_process_exprs(mod, [{ :let, _, let_exprs } | exprs]) do
    if length(let_exprs) == 1 and is_list(hd(let_exprs)) do
      case Keyword.fetch(hd(let_exprs), :do) do
        :error     -> let_exprs ++ do_process_exprs(mod, exprs)
        { :ok, e } -> 
          [ e | do_process_exprs(mod, exprs) ]
      end
    else
      let_exprs ++ do_process_exprs(mod, exprs)
    end
  end
  defp do_process_exprs(mod, [{ :<-, _, [lhs, rhs] } | exprs]) do
    # x <- m  ==>  bind(b, fn x -> ... end)
    do_process_bind(mod, lhs, rhs, exprs)
  end
  defp do_process_exprs(mod, [ expr | exprs ]) do
    # m       ==>  bind(b, fn _ -> ... end)
    do_process_bind(mod, quote(do: _), expr, exprs)
  end

  defp do_process_bind(mod, lhs, rhs, exprs) do
    [quote do 
      unquote(mod).bind(unquote(rhs), fn unquote(lhs) -> unquote_splicing(do_process_exprs(mod, exprs)) end)
    end]
  end

  @type monad :: any

  @callback return(any) :: monad
  @callback bind(monad, (any -> monad)) :: monad
end
