defmodule Pipe do
  @moduledoc """
  A [conduit](http://hackage.haskell.org/package/conduit) like pipe system for Elixir.
  """

  defrecord Lazy, func: nil do
    @moduledoc """
    An unevaluated pipe.

    This is necessary to avoid pipes starting to run when they are connected.
    """
  end

  defrecord NeedInput, on_value: nil, on_done: nil do
    @moduledoc """
    A pipe that needs more input.

    The `on_value` field should contain a function that given an element of
    input returns a new pipe.

    The `on_done` field should contain a function that given the result of the
    upstream pipe returns a new pipe.
    """
  end

  defrecord HaveOutput, value: nil, next: nil do
    @moduledoc """
    A pipe that has output.

    The `value` field should contain a single piece of output.

    The `next` field should contain a nullary function which when evaluated
    returns a new pipe and represents the future of the computation of the pipe.
    """
  end

  defrecord Done, result: nil do
    @moduledoc """
    A pipe that is done.

    The `result` field should contain the result of the pipe.
    """
  end

  defexception Invalid, [why: nil] do
    @moduledoc """
    Indicates that a pipe is invalid when run.

    Usually this is because the user didn't properly compose pipes. A pipe
    that's passed to `Pipe.run/1` should not provide output, it should only
    return a value or request input (it won't get any, but it may ask for it).
    """
    def message(Invalid[why: :have_output]) do
      "invalid pipe: provides output when run"
    end
  end

  ## Running pipes

  @doc """
  Run a pipe.

  The pipe should be fully composed, it should not provide output.

  If the passed pipe requests input it will get a `nil` result value passed to
  it.
  """
  def run(Lazy[func: f]) do
    run(f.())
  end
  def run(NeedInput[on_done: od]) do
    run(od.(nil))
  end
  def run(HaveOutput[]) do
    raise Invalid[why: :have_output]
  end
  def run(Done[result: r]) do
    r
  end

  ## Connecting pipes (horizontal composition)
  
  @doc """
  Connect two pipes.
  """
  def connect(a, b)
  def connect(Lazy[func: af], Lazy[func: bf]) do 
    lazy(connect(af.(), bf.()))
  end
  def connect(a, Lazy[func: bf]) do
    lazy(connect(a, bf.()))
  end
  def connect(Lazy[func: af], b) do 
    lazy(connect(af.(), b))
  end
  def connect(NeedInput[on_value: ov, on_done: od], b) do
    NeedInput[on_value: &connect(ov.(&1), b), on_done: &connect(od.(&1), b)]
  end
  def connect(HaveOutput[value: v, next: n], NeedInput[on_value: ov]) do
    # Ensure the downstream gets stepped first. Not sure if it's needed but it
    # shouldn't hurt performance.
    new_b = ov.(v)
    connect(n, new_b) 
  end
  def connect(a = Done[result: r], NeedInput[on_done: od]) do
    connect(a, od.(r))
  end
  def connect(a, HaveOutput[value: v, next: n]) do
    HaveOutput[value: v, next: fn -> connect(a, n) end]
  end
  def connect(_, Done[result: r]) do
    Done[result: r]
  end

  ## The monadic interface (vertical composition)

  @doc """
  Return a value inside a pipe.
  """
  def return(x) do
    Done[result: x]
  end

  @doc """
  Create a new pipe that first "runs" the passed pipe `p` and passes the result
  of that pipe to `f` (which should return a pipe).
  """
  def bind(p, f)
  def bind(Lazy[func: lf], f) do
    lazy(bind(lf.(), f))
  end
  def bind(NeedInput[on_value: ov, on_done: od], f) do
    NeedInput[on_value: &(ov.(&1) |> bind(f)), on_done: &(od.(&1) |> bind(f))]
  end
  def bind(HaveOutput[value: v, next: n], f) do
    HaveOutput[value: v, next: bind(n, f)]
  end
  def bind(Done[result: r], f) do
    f.(r)
  end

  ## Primitive pipes

  @doc """
  Wait for a value to be provided by upstream and return it.

  Returns nil if there was no value from upstream. See `await/2` for an alternative.
  """
  def await() do
    lazy(NeedInput[on_value: &Done[result: &1], on_done: fn _ -> Done[result: nil] end])
  end

  @doc """
  Wait for a value to be provided by upstream and return it in a wrapper. If
  upstream is done returns the default.

  The wrapper should be a unary function. For example `await(&[&1], [])` returns
  `[1]` if upstream produces `1` and `[]` if upstream is done.
  """
  def await(wrapper, default // nil) do
    lazy(NeedInput[on_value: &Done[result: wrapper.(&1)], 
                   on_done: fn _ -> Done[result: default] end])
  end

  @doc """
  Yield a new output value.
  """
  def yield(v) do
    HaveOutput[value: v, next: lazy(Done[result: nil])]
  end
 
  ## Misc 
  
  @doc """
  Helper for writing `Lazy[func: fn -> v end]`.
  """
  def lazy(v) do
    Lazy[func: fn -> v end]
  end
end
