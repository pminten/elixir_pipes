defmodule Pipe.List do
  @moduledoc """
  Pipes which act in a list-like (or stream-like) manner.
  """
  require Pipe, as: P

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
end
