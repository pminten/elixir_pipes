defmodule Pipe do
  @moduledoc """
  A [conduit](http://hackage.haskell.org/package/conduit) like pipe system for Elixir.

  See the [README](README.html) for high level documentation.
  """

  use Monad

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

  defrecord RegisterCleanup, func: nil, next: nil do
    @moduledoc """
    A pipe that wants to register a cleanup function.

    Cleanup functions get run when the complete pipe has finished running.

    The `func` field should contain a nullary function which should be safe
    to call multiple times.

    The `next` field should contain a nullary function which when evaluated
    returns a new pipe.
    """
    record_type func: (() -> none), next: (() -> Pipe.t)
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
  Allow the use of a list for connecting pipes.
  
  This simply reduces the list using `connect/2`.

  Note that connecting a source to a sink runs a pipe.

  See `connect/2` for more information.

  ## Examples

    iex> Pipe.connect [Pipe.yield(1), Pipe.await]
    [1]
  """
  def connect(pipes) when is_list(pipes), do: Enum.reduce(pipes, &connect(&2, &1))

  @doc """
  Connect two pipes.

  Note that this is a function while `connect/1` is a macro.

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
  defp run(RegisterCleanup[func: f, next: n]) do
    # If 3 resources are registered the run function will be on the stack 3
    # times, registering too many resources would therefore not be a too
    # brilliant idea. However I doubt this will be a problem in practice.
    try do
      run(n.())
    after
      f.()
    end
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
  defp step(RegisterCleanup[func: f, next: n], b) do
    RegisterCleanup[func: f, next: fn -> step(n.(), b) end]
  end
  defp step(a, RegisterCleanup[func: f, next: n]) do
    RegisterCleanup[func: f, next: fn -> step(a, n.()) end]
  end
  defp step(Source[step: s], b), do: step(force(s), b)
  defp step(Conduit[step: s], b), do: step(force(s), b)
  defp step(Sink[step: s], b), do: step(force(s), b)

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
    HaveOutput[value: v, next: fn -> bind(n.(), f) end]
  end
  def bind(p = Done[], nil) do
    # A nil step can easily result from an if without an else case. Gracefully
    # handle it by considering it to mean return.
    bind(p, &(return(&1)))
  end
  def bind(nil, f) do
    # An expression like if ... do ... end should be taken to have an else
    # clause that returns nil.
    bind(return(nil), f)
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
  def bind(RegisterCleanup[func: cf, next: n], f) do
    RegisterCleanup[func: cf, next: fn -> bind(n.(), f) end]
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
  def with_leftovers(RegisterCleanup[func: f, next: n], l) do
    RegisterCleanup[func: f, next: fn -> with_leftovers(n.(), l) end]
  end

  @doc """
  A do-notation macro for a source. Creates a strict source.
  """
  defmacro source(opts) do
    quote do 
      Source[step: Pipe.m(do: unquote(opts[:do]))]
    end
  end

  @doc """
  A do-notation macro for a source. Creates a lazy source.
  """
  defmacro lazy_source(opts) do
    quote do 
      Source[step: fn -> Pipe.m(do: unquote(opts[:do])) end]
    end
  end
  
  @doc """
  A do-notation macro for a conduit. Creates a strict conduit.
  """
  defmacro conduit(opts), do: do_conduit(opts)
  
  @doc """
  A do-notation macro for a conduit. Creates a lazy conduit.
  """
  defmacro lazy_conduit(opts), do: do_lazy_conduit(opts)
  
  defp do_conduit(opts) do
    quote do 
      Conduit[step: Pipe.m(do: unquote(opts[:do]))]
    end
  end

  defp do_lazy_conduit(opts) do
    quote do 
      Conduit[step: fn -> Pipe.m(do: unquote(opts[:do])) end]
    end
  end
  
  @doc """
  A do-notation macro for a sink. Creates a strict sink.
  """
  defmacro sink(opts), do: do_sink(opts)
  
  @doc """
  A do-notation macro for a sink. Creates a lazy sink.
  """
  defmacro lazy_sink(opts), do: do_lazy_sink(opts)
  
  defp do_sink(opts) do
    quote do 
      Sink[step: Pipe.m(do: unquote(opts[:do]))]
    end
  end

  defp do_lazy_sink(opts) do
    quote do 
      Sink[step: fn -> Pipe.m(do: unquote(opts[:do])) end]
    end
  end

  ## Primitive pipes
  
  @doc """
  Wait for a value to be provided by upstream.
  
  If a value is provided return it wrapped in a single element list, otherwise
  return an empty list.
  """
  @spec await() :: Sink.t
  def await() do
    Sink[step: NeedInput[on_value: &Done[result: [&1]],
                         on_done: fn _ -> Done[result: []] end]]
  end

  @doc """
  Wait for a value or result to be provided by upstream.

  Returns either `{ :value, value }` (if a value is provided) or `{ :result,
  result }` (if the upstream is done).
  """
  @spec await_result() :: Sink.t
  def await_result() do
    Sink[step: NeedInput[on_value: &Done[result: { :value, &1 }],
                         on_done:  &Done[result: { :result, &1 }]]]
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

  @doc """
  Register a cleanup function to be called when the complete pipe has finished
  running.

  The cleanup function should be safe to call multiple times.

  This is a good way to prevent resource leaks.

  Note that `register_cleanup/1` returns a step and thus can't be used directly
  in `connect/2` (not that you'd ever want to).
  """
  @spec register_cleanup((() -> none)) :: step 
  def register_cleanup(f) do
    RegisterCleanup[func: f, next: fn -> Done[result: nil] end]
  end

  ## Misc
  @doc """
  Zip two sources.
  
  Yields `{a, b}` where `a` is a value from the first source and `b` is a value
  from the second source.

  If both of the sources are done the result value will be `{ result_of_a,
  result_of_b }`. If only one of the sources is done a similar tuple will be
  returned but with :not_done instead of the result value of the other source.

  ## Examples

      iex> Pipe.connect [
      ...>   Pipe.zip_sources(Pipe.yield(1), Pipe.yield(2)),
      ...>   Pipe.List.consume
      ...> ]
      [{1, 2}]
  
      iex> Pipe.connect [
      ...>   Pipe.zip_sources(Pipe.done(:a), Pipe.done(:b)),
      ...>   Pipe.List.skip_all
      ...> ]
      { :a, :b }
      
      iex> Pipe.connect [
      ...>   Pipe.zip_sources(Pipe.done(:a), Pipe.yield(2)),
      ...>   Pipe.List.skip_all
      ...> ]
      { :a, :not_done }
  """
  @spec zip_sources(Source.t, Source.t) :: Source.t
  def zip_sources(Source[step: a], Source[step: b]),
    do: Source[step: do_zip_sources(force(a), force(b))]

  defp do_zip_sources(Source[step: a], b), do: do_zip_sources(force(a), b)
  defp do_zip_sources(a, Source[step: b]), do: do_zip_sources(a, force(b))
  defp do_zip_sources(NeedInput[on_done: od], b), do: do_zip_sources(od.(nil), b)
  defp do_zip_sources(a, NeedInput[on_done: od]), do: do_zip_sources(a, od.(nil))
  defp do_zip_sources(RegisterCleanup[func: f, next: n], b) do
    RegisterCleanup[func: f, next: fn -> do_zip_sources(n.(), b) end]
  end
  defp do_zip_sources(a, RegisterCleanup[func: f, next: n]) do
    RegisterCleanup[func: f, next: fn -> do_zip_sources(a, n.()) end]
  end
  defp do_zip_sources(HaveOutput[value: va, next: na], HaveOutput[value: vb, next: nb]) do
    HaveOutput[value: { va, vb }, next: fn -> do_zip_sources(na.(), nb.()) end]
  end
  defp do_zip_sources(Done[result: ra], Done[result: rb]) do
    Done[result: { ra, rb }]
  end
  defp do_zip_sources(Done[result: r], HaveOutput[]) do
    Done[result: { r, :not_done }]
  end
  defp do_zip_sources(HaveOutput[], Done[result: r]) do
    Done[result: { :not_done, r }]
  end
end
