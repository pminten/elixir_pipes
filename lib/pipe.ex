defmodule Pipe do
  @moduledoc """
  A [conduit](http://hackage.haskell.org/package/conduit) like pipe system for Elixir.
  """

  require Macro.Monad

  @typedoc "A pipe which hasn't started running yet"
  @type t :: Source.t | Conduit.t | Sink.t

  @typedoc "The result of stepping a pipe"
  @type step :: NeedInput.t | HaveOutput.t | Done.t

  @typedoc "A source or conduit, helper type for pipe functions"
  @type sourceish :: Source.t | Conduit.t

  # The step field may be strict or lazy depending on what works best.
  # Unneccesary lazyness costs performance but too little lazyness can cause
  # results to be computed before they are needed.

  defrecord Source, step: nil do
    @moduledoc """
    A source pipe that hasn't yet started.

    The `step` field should contain step or a a nullary function that returns a
    step (depending on whether you want the step to be computed immediately or
    when needed).
    """
    record_type step: Pipe.step | (() -> Pipe.step)
  end
  
  defrecord Conduit, step: nil do
    @moduledoc """
    A conduit pipe that hasn't yet started.
    
    The `step` field should contain step or a a nullary function that returns a
    step (depending on whether you want the step to be computed immediately or
    when needed).
    """
    record_type step: Pipe.step | (() -> Pipe.step)
  end
  
  defrecord Sink, step: nil do
    @moduledoc """
    A sink pipe that hasn't yet started.
    
    The `step` field should contain step or a a nullary function that returns a
    step (depending on whether you want the step to be computed immediately or
    when needed).
    """
    record_type step: Pipe.step | (() -> Pipe.step)
  end

  defrecord NeedInput, on_value: nil, on_done: nil do
    @moduledoc """
    A pipe that needs more input.

    The `on_value` field should contain a function that given an element of
    input returns a new pipe.

    The `on_done` field should contain a function that given the result of the
    upstream pipe returns a new pipe.
    """
    record_type on_value: (any -> Pipe.t), on_done: (any -> Pipe.t)
  end

  defrecord HaveOutput, value: nil, next: nil do
    @moduledoc """
    A pipe that has output.

    The `value` field should contain a single piece of output.

    The `next` field should contain a nullary function which when evaluated
    returns a new pipe.
    """
    record_type value: any, next: (() -> Pipe.t)
  end

  defrecord Done, result: nil, leftovers: [] do
    @moduledoc """
    A pipe that is done.

    The `result` field should contain the result of the pipe.
    The `leftovers` field should contain any unused input items.
    """
    record_type result: any, leftovers: [any]
  end

  defexception Invalid, message: nil do
    @moduledoc """
    Indicates that a pipe is invalid when run.

    Usually this is because the user didn't properly compose pipes.
    """
  end

  ## Helper macros
  
  # Force the computation of a nullary function or otherwise return the value.
  defmacrop force(p) do
    quote location: :keep do
      if is_function(unquote(p)), do: unquote(p).(), else: unquote(p)
    end
  end

  ## Connecting and running pipes (horizontal composition)
  
  @doc """
  Connect two pipes.

  Connecting a source to a conduit results in a conduit.
  Connecting a conduit to a conduit results in a conduit.
  Connecting a conduit to a sink results in a sink.
  Connecting a source to a sink runs the pipe.
  
  Connecting `nil` to anything results in the second argument being returned.
  
  Any other combination results in Pipe.Invalid being thrown.
  """
  @spec connect(Source.t, Conduit.t) :: Source.t
  @spec connect(Conduit.t, Conduit.t) :: Conduit.t
  @spec connect(Conduit.t, Sink.t) :: Sink.t
  @spec connect(Source.t, Sink.t) :: any()
  @spec connect(nil, t) :: t 
  def connect(a, b)
  def connect(Source[step: as], Conduit[step: bs]) do
    Source[step: fn -> step(force(as), force(bs)) end]
  end
  def connect(Conduit[step: as], Conduit[step: bs]) do
    Conduit[step: fn -> step(force(as), force(bs)) end]
  end
  def connect(Conduit[step: as], Sink[step: bs]) do
    Sink[step: fn -> step(force(as), force(bs)) end]
  end
  def connect(Source[step: as], Sink[step: bs]) do
    run(step(force(as), force(bs)))
  end
  def connect(nil, b) do
    b
  end
  def connect(a, b) do
    raise Invalid, message: "Invalid connect: #{inspect a} -> #{inspect b}"
  end

  # Run a fully composed pipe. 
  @spec run(step) :: any()
  defp run(NeedInput[on_done: od]) do
    run(od.(nil))
  end
  defp run(HaveOutput[]) do
    raise Invalid, message: "Fully composed pipes shouldn't provide output"
  end
  defp run(Done[result: r]) do
    r
  end

  # Perform a step or as much steps as possible.
  @spec step(step, step) :: step | Done.t
  defp step(NeedInput[on_value: ov, on_done: od], b) do
    NeedInput[on_value: &step(ov.(&1), b), on_done: &step(od.(&1), b)]
  end
  defp step(HaveOutput[value: v, next: n], NeedInput[on_value: ov]) do
    # Ensure the downstream gets stepped first. Not sure if it's needed but it
    # shouldn't hurt performance.
    new_b = ov.(v)
    step(n.(), new_b) 
  end
  defp step(a = Done[result: r], NeedInput[on_done: od]) do
    step(a, od.(r))
  end
  defp step(a, HaveOutput[value: v, next: n]) do
    HaveOutput[value: v, next: fn -> step(a, n.()) end]
  end
  defp step(_, Done[result: r]) do
    Done[result: r]
  end

  ## The monadic interface (vertical composition)

  @doc """
  Return a value inside a pipe.

  Note that you can't do `connect(return(1), await())` because return/1 doesn't
  return a source, conduit or sink but a pipe step. If you run into this problem
  use `done/1` instead.
  """
  @spec return(any()) :: Done.t
  def return(x) do
    Done[result: x]
  end
 
  # Not really a monadic interface part but it fits best here.
  @doc """
  Return a result and some leftovers.
  
  Note that you can't do `connect(return_leftovers(1, []), await())` because
  return_leftovers/2 doesn't return a source, conduit or sink but a pipe step.
  If you run into this problem use `done/2` instead.
  """
  @spec return_leftovers(any, [any]) :: Done.t
  def return_leftovers(x, l) do
    Done[result: x, leftovers: l]
  end

  @doc """
  Create a new pipe that first "runs" the passed pipe `p` and passes the result
  of that pipe to `f` (which should return a pipe).
  """
  @spec bind(t | step, (any -> t | step)) :: step
  def bind(p, f)
  def bind(Source[step: s], f),  do: bind(force(s), f)
  def bind(Conduit[step: s], f), do: bind(force(s), f)
  def bind(Sink[step: s], f),    do: bind(force(s), f)
  def bind(NeedInput[on_value: ov, on_done: od], f) do
    NeedInput[on_value: &(ov.(&1) |> bind(f)), on_done: &(od.(&1) |> bind(f))]
  end
  def bind(HaveOutput[value: v, next: n], f) do
    HaveOutput[value: v, next: bind(n, f)]
  end
  def bind(p = Done[result: r], nil) do
    # A nil step can easily result from an if without an else case. Gracefully
    # handle it by considering it to mean return.
    bind(p, &(return(&1)))
  end
  def bind(Done[result: r, leftovers: l], f) do
    x = f.(r)
    # It's quite possible, even normal, that we get not a step but a pipe which
    # hasn't started running, which basically means a lazily evaluated pipe
    # step. Force the step, otherwise the whole system won't work.
    s = case x do
      Source[step: s]   -> force(s)
      Conduit[step: s]  -> force(s)
      Sink[step: s]     -> force(s)
      _                 -> x
    end
    if l == [], do: s, else: with_leftovers(s, l)
  end

  @doc """
  Run the step with some leftovers present.
  """
  @spec with_leftovers(step, [any]) :: step
  def with_leftovers(s, []) do
    s
  end
  def with_leftovers(NeedInput[on_value: ov], [h|t]) do
    with_leftovers(ov.(h), t)
  end
  def with_leftovers(HaveOutput[value: v, next: n], l) do
    HaveOutput[value: v, next: fn -> with_leftovers(n, l) end]
  end
  def with_leftovers(Done[result: r, leftovers: l1], l2) do
    Done[result: r, leftovers: l1 ++ l2]
  end

  @doc """
  A do-notation macro for a source.

  Automatically wraps the generated pipe in a Source if `lazy: true` is given.
  """
  defmacro source(opts) do
    if opts[:lazy] do
      quote do
        Source[step: fn -> unquote(Macro.Monad.monad_do_notation(Pipe, opts[:do])) end]
      end
    else
      quote do
        Source[step: unquote(Macro.Monad.monad_do_notation(Pipe, opts[:do]))]
      end
    end
  end
  
  @doc """
  A do-notation macro for a conduit.

  Automatically wraps the generated pipe in a Conduit if `lazy: true` is given.

  If `source` is not `nil` the generated conduit is automatically connected to
  the source.
  """
  defmacro conduit(opts), do: do_conduit(opts)
  
  @doc """
  Like conduit/1 but connects the source to the generated conduit.
  
  Useful in pipelines.
  """
  defmacro conduit_c(source, opts) do
    quote do Pipe.connect(unquote(source), unquote(do_conduit(opts))) end
  end

  defp do_conduit(opts) do
    if opts[:strict] do
      quote do 
        Conduit[step: unquote(Macro.Monad.monad_do_notation(Pipe, opts[:do]))]
      end
    else
      quote do 
        Conduit[step: fn -> unquote(Macro.Monad.monad_do_notation(Pipe, opts[:do])) end]
      end
    end
  end
  
  @doc """
  A do-notation macro for a sink.

  Automatically wraps the generated pipe in a Sink if `lazy: true` is given.

  If `source` is not `nil` the generated sink is automatically connected to
  the source.
  """
  defmacro sink(opts), do: do_sink(opts)
  
  @doc """
  Like sink/1 but connects the source to the generated conduit.
  
  Useful in pipelines.
  """
  defmacro sink_c(source, opts) do
    quote do Pipe.connect(unquote(source), unquote(do_sink(opts))) end
  end

  defp do_sink(opts) do
    if opts[:strict] do
      quote do 
        Sink[step: unquote(Macro.Monad.monad_do_notation(Pipe, opts[:do]))]
      end
    else
      quote do 
        Sink[step: fn -> unquote(Macro.Monad.monad_do_notation(Pipe, opts[:do])) end]
      end
    end
  end

  ## Primitive pipes
  
  @doc """
  Wait for a value to be provided by upstream.
  
  If a value is provided return it wrapped in a single element list, otherwise
  return an empty list.
  """
  @spec await() :: Sink.t
  @spec await(sourceish) :: Sink.t
  def await(source // nil) do
    connect(source,
      Sink[step: NeedInput[on_value: &Done[result: [&1]],
                           on_done: fn _ -> Done[result: []] end]]
    )
  end

  @doc """
  Wait for a value or result to be provided by upstream.

  Returns either `{ :value, value }` (if a value is provided) or `{ :result,
  result }` (if the upstream is done).
  """
  @spec await_result() :: Sink.t
  @spec await_result(sourceish) :: Sink.t
  def await_result(source // nil) do
    connect(source,
      Sink[step: NeedInput[on_value: &Done[result: { :value, &1 }],
                           on_done:  &Done[result: { :result, &1 }]]]
    )
  end

  @doc """
  Yield a new output value.
  """
  @spec yield(any) :: Source.t
  def yield(v) do
    Source[step: HaveOutput[value: v, next: fn -> Done[result: nil] end]]
  end

  @doc """
  Return a value as a valid pipe and optionally pass along some leftover input
  values.

  Use this instead of `return/1` if you're going to immediately use the pipe in
  horizontal composition.
  
  Only return input values as leftovers, otherwise weird things might happen.
  """
  @spec done(any) :: Source.t
  @spec done(any, [any]) :: Source.t
  def done(v, l // []) do
    Source[step: return_leftovers(v, l)]
  end
end
