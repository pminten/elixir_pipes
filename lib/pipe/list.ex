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
    P.return nil
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
  """
  def filter(source // nil, f) do
    P.connect(source, do_filter(f))
  end

  defp do_filter(f) do
    P.conduit do
      r <- P.await()
      case r do
        []  ->
          return nil
        [x] ->
          if (f.(x)) do
            P.yield(f.(x))
          end
          do_filter(f)
      end
    end
  end

  @doc """
  Map a function over the input values.
  """
  def map(source // nil, f) do
    P.connect(source, do_map(f))
  end

  def do_map(f) do
    P.conduit do
      r <- P.await()
      case r do
        []  ->
          return nil
        [x] ->
          P.yield(f.(x))
          do_map(f)
      end
    end
  end

  ## Sinks

  @doc """
  Return all remaining elements as a list.
  """
  def consume(source // nil) do
    P.connect(source, do_consume([]))
  end

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
end
