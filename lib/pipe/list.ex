defmodule Pipe.List do
  @moduledoc """
  Pipes which act in a list-like (or stream-like) manner.
  """
  require Pipe, as: P

  ## Sources

  @doc """
  Yield all elements of the list.
  """
  def source_list(list)
  def source_list([]) do
    P.source do
      P.return nil
    end
  end
  def source_list([h|t]) do
    P.source do
      P.yield(h)
      source_list(t)
    end
  end

  ## Conduits

  @doc """
  Only pass those values for which the filter returns a non-nil non-false value.
  
  The result is the upstream result.
  """
  def filter(f) do
    P.conduit do
      t <- P.await_result()
      case t do
        { :result, r }  ->
          return r
        { :value, x } -> P.conduit do
          if (f.(x)) do
            P.yield(x)
          end
          filter(f)
        end
      end
    end
  end

  @doc """
  Map a function over the input values.

  The result is the upstream result.
  """
  def map(f) do
    P.conduit do
      t <- P.await_result()
      case t do
        { :result, r }  ->
          return r
        { :value, x } -> P.conduit do
          P.yield(f.(x))
          map(f)
        end
      end
    end
  end

  ## Sinks

  @doc """
  Return all remaining elements as a list.
  """
  def consume(), do: do_consume([])

  defp do_consume(acc) do
    P.sink do
      r <- P.await()
      case r do
        []  ->
          return(:lists.reverse(acc)) 
        [x] ->
          do_consume([x|acc])
      end
    end
  end 

  @doc """
  Ignore all the input and return the upstream result.
  """
  def skip_all() do
    P.sink do
      t <- P.await_result()
      case t do
        { :result, r }  ->
          return r
        { :value, _ } ->
          skip_all()
      end
    end
  end

  @doc """
  Consume input values while the predicate function returns a true value and
  return those input values as a list.
  """
  def take_while(f), do: do_take_while([], f)

  defp do_take_while(acc, f) do
    P.sink do
      t <- P.await()
      case t do
        []  -> return :lists.reverse(acc)
        [x] -> 
          if f.(x) do
            do_take_while([x|acc], f)
          else
            P.return_leftovers(:lists.reverse(acc), [x])
          end
      end
    end
  end
end
