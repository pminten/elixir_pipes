# Elixir Pipes

A [conduit](http://hackage.haskell.org/package/conduit) like pipe system for
Elixir.


## Overview 

Pipes are a different approach to what enumerators and streams do: passing
values from one function to another. Pipes allow more things than enumerators
and it's easier to perform complicated tasks with them (really anything more
complicated than a simple map or filter).


### Sources, conduits and sinks

Pipes come in three basic forms: sources, conduits and sinks. Sources produce
values, sinks consume them and conduits to both. Take for example the following
pipeline:

```elixir
require Pipe, as: P
alias Pipe.List, as: PL
P.connect [PL.source_list([1,2,3]), P.map(&(&1+1)), P.take_while(&(&1<=2))]
# Result: [1, 2]
```

`PL.source_list` is a source, `PL.map` is a conduit and `PL.take_while` is a
sink.

These aren't the only types in the pipes library, there are also steps. Steps
are internal things, they represent a pipe that's currently running. See the
`Pipe` module docs for more details. Under normal circumstances you shouldn't
have to think about steps.

Each pipe is an individual value. `PL.source_list([1,2,3])` produces a
`Pipe.Source`, `PL.map(&(&1+1))` produces a `Pipe.Conduit` and
`PL.take_while(&(&1<=2))` produces a `Pipe.Sink`. To run a pipe you have to
connect all individual bits using the `Pipe.connect/2` function. This function
connects two pipes to result in a new pipe, or if a source and sink are given
runs the pipe. For connecting multiple pipes there iss `Pipe.connect/1`, which
takes a list of pipes.

The above example could have been written as:
    
```elixir
alias Pipe, as: P
alias Pipe.List, as: PL
source = PL.source_list([1,2,3])
conduit = PL.map(&(&1+1))
sink = PL.take_while(&(&1<=2))
new_source = P.connect(source, conduit)
result = P.connect(new_source, sink)
```

It could also have been written as:
    
```elixir
source = PL.source_list([1,2,3])
conduit = PL.map(&(&1+1))
sink = PL.take_while(&(&1<=2))
new_sink = P.connect(conduit, sink)
result = P.connect(source, new_sink)
```

By the way, using `Pipe.connect/2` is sometimes called horizontal composition
(because of how the code looks when you put it on a single line). There's also
vertical composition: using the do-notation to write pipes.


### Do-notation and writing pipes

One of the great things about pipes is that they allow you to compose simple
pipes to pipes that do complicated stuff. For example say you want to cut up
input text to pass strings terminated by a semicolon. But the input text may
arrive in long or short pieces. Here's one way to do this:

```elixir
require Pipe, as: P # Uses macro's from Pipe
alias Pipe.List, as: PL

def terminated_by_semicolon(source // nil) do
  P.connect(source, do_term_by_semi(<<>>))
end

defp do_term_by_semi(buffer) do
  P.conduit do
    r <- P.await()
    case r do
      []    -> return nil # end of input
      [str] -> P.conduit do
        let parts = String.split(buffer <> str, ";")
        PL.source_list(Enum.take(parts, -1))
        do_term_by_semi(Enum.at(parts, -1))
      end
    end
  end
end
```

Here's how it works:

```elixir
P.connect [
  PL.source_list(["AB;C", "D;E", ";", "F"]),
  do_term_by_semi(),
  PL.consume()
]
=# Result: ["AB", "CD", "E"]
```

Let's go over this piece by piece. The main `terminated_by_semicolon` function
uses the `connect` hack to allow it to be used in a pipeline. The
`do_term_by_semi` function contains the worker. It takes a buffer argument which
is the input it has received so far that hasn't been terminated by a semicolon
yet.

At every iteration of the `do_term_by_semi` function it waits for a string from
the source (`P.await()`). The source might be done, in which case the result of
`Pipe.await/0` is an empty list. If that's the case the `do_term_by_semi`
function simply is done as well. This is indicated by using `return` to wrap the
result value in a step, this is needed because of the underlying machinery, just
remember to use `return` before returning. The `return` function is
automatically available in a `P.conduit` do-block as a result of the underlying
machinery.

If there is input it is appended to the buffer and the result is split on the
semicolon. The `let` tells the machinery that this is simply a value assignment,
it doesn't have anything to do with pipes.

The used approach is slightly inefficient, I could also have written

```elixir
[str] -> P.conduit do
  let do
    splitted = String.split(str, ";")
    parts = [buffer <> hd(splitted) | tl(splitted)]
  end
  PL.source_list(Enum.take(parts, -1))
  do_term_by_semi(Enum.at(parts, -1))
end
```

The do-block with `let` is a way of telling the machinery that everything in
the do-block is unrelated to conduits. It's also a bit more sturdy than
let-without-do, if you ever run into weird problems with let-without-do add a
do-block.

Once we have the strings that are terminated by a semicolon we send them
downstream (i.e. to the next conduit or sink). This is done using
`PL.source_list` which returns a source that yields (sends downstream) each of
the values in the past list in turn. Yes, you can use a source inside a conduit
do-block, inside such a do-block the actual pipe type doesn't matter.

Finally the last part of the list (the bit not terminated by a semicolon) is
used as buffer for the next iteration.

I haven't explained the `<-` syntax yet, that simply means "run this pipe" (or
more exactly step) and put the result of it in the variable on the left hand
side. That is "a <- b" means "run b then do a = result-of-b". You are allowed to
use pattern matching for the left hand side just as in a normal assignment.

The do-notation only works for the immediate block, not for subexpressions of
it. So inside the `[str] ->` another call to `P.conduit` is needed. Because of
how `return` is transformed (it's imported locally) it is available even outside
the immediate do-block.


### Strict and lazy pipes

By default `Pipe.source`, `Pipe.conduit` and `Pipe.sink` create strict pipes. That
is to say typing `Pipe.source do let IO.puts("A") end` in an iex session
will cause "A" to be printed. A strict pipe runs immediately upon creation until
it reaches a point where it can't continue anymore (typically because it needs
input or needs someone to consume a piece of output).

If you want to create a lazy pipe use `Pipe.lazy_source` and friends.
`Pipe.lazy_source do let IO.puts("A") end` will not print "A" immediately but
will do so when you run the pipe.

Lazy pipes are very useful, in a small number of situations. For example if a
pipe opens a file you'll want to make it lazy so it doesn't do the work before
it's needed.

Strict pipes on the other hand are slightly faster due to not creating a nullary
function and then running it. Because in the vast majority of cases you don't
need lazyness strict is the default.


### Passing on results

Every pipe has a result. In do-notation you can get the result of a pipe using
the `res <- pipe` syntax. When using `connect/2` the result of a completed
source is passed to the sink and can be obtained using `await_result/1`. For
example `Pipe.connect(Pipe.done(4), Pipe.await_result())` == `{ :result, 4 }`
(whereas `Pipe.connect(Pipe.yield(3), Pipe.await_result())` == `{ :value, 3 }`).
The `Pipe.done/1` function does the same as `return`, except that it returns a
pipe, not a step, so it can be used with `connect/2`.

In general when you write a conduit that doesn't have a return value (when you'd
just always return nil) it's a good idea to return the upstream return value,
maybe some pipe downstream has use for it. For example here's how
`do_term_by_semi` would look when returning the upstream return value.

```elixir
defp do_term_by_semi(buffer) do
  P.conduit do
    r <- P.await_result()
    case r do
      { :result, res } -> return res # end of input
      { :value, str } -> P.conduit do
        let parts = String.split(buffer <> str, ";")
        PL.source_list(Enum.take(parts, -1))
        do_term_by_semi(Enum.at(parts, -1))
      end
    end
  end
end
```

### Leftovers

Sometimes you want to "look" at a particular value from upstream but not "eat"
it. The typical example of this is `take_while`. This sink gathers values while
a particular function returns true and returns the gathered values once the
function returns false or there is no more input. Here's one, wrong, way to
write it:

```elixir
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
          P.return(:lists.reverse(acc))
        end
    end
  end
end
```

So what's the problem here? Well let's say you want to create a sink that
returns a tuple where the first element is all values that contiguously match
the function and the second element is all remaining values.

```elixir
def cont_consume(f) do
  P.sink do
    a <- take_while(f)
    b <- consume
    return { a, b }
  end
end
```

When you call it like this: `P.connect(PL.source_list([1, 2, :a, 3, :b]),
cont_consume(&is_integer/1))` the result isn't `{ [1, 2], [:a, 3, :b] }` but `{
    [1, 2], [3, :b] }`. The `:a` is eaten by `take_while`.

To avoid this problem you can use `return_leftovers` to give back unused input
values. Here's how the real `do_take_while` looks:
  
```elixir
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
```

When using `return_leftovers` be sure to only pass actually received input
values and in the correct order. Otherwise you might end up with weird results.


### Resource cleanup

Some pipes deal with resources that should be closed when the pipe is done. For
example say you have a source that reads blocks of at most 64 bytes from a file.

```elixir
def read64(filename) do
  P.lazy_source do
    f <- File.open!(filename, [:read])
    do_read64(f)
  end
end

defp do_read64(f) do
  P.lazy_source do
    case IO.binread(f, 64) do
      :eof               -> return nil
      # Slightly abusing StreamError, though this is similar to a stream 
      { :error, reason } -> raise IO.StreamError, reason: reason,
                                                  message: "binread failed"
      data               -> P.source do P.yield(data); do_read64(f) end
    end
  end
end
```

The problem with this is that if you run `P.connect(read64("/tmp/foo"),
Pipe.List.consume())` it opens a file but doesn't close it. Sure, you could
rewrite `read64` to:
    
```elixir
def read64(filename) do
  P.lazy_source do
    f <- File.open!(filename, [:read])
    do_read64(f)
    File.close(f)
  end
end
```

And that would work for `consume` but it wouldn't work for
`P.connect(read64("/tmp/foo"), Pipe.List.take(0))` because the sink says "I'm
done" before the source is done.  The `IO.close` line is never reached in this
case. It also wouldn't work in case of an exception somewhere in a sink.

There is a better with. Using `Pipe.register_cleanup/1` you can register a
function that gets called when the pipe has finished running even if there is an
exception. This doesn't leave the file open:
   
```elixir
def read64(filename) do
  P.lazy_source do
    f <- File.open!(filename, [:read])
    P.register_cleanup(fn -> File.close(f) end)
    do_read64(f)
  end
end
```

It's not recommended btw to register too many (think thousands) of cleanup
handlers because each one causes a new entry on the stack to be created.

## Pipes versus enumerators

Pipes and the standard library enumerators each have their own strengths and
weaknesses:

* Pipes are more powerful, you can't detect in a reduce function that there is
  no more input but you can detect it in a sink.
* Pipes compose more easily due to the do-notation.
* With pipes a sink can open a resource and be sure it's closed when the pipe
  has finished executing whereas with enumerators a reduce function doesn't get
  that assurance.
* Enumerators have less overhead and are therefore faster.
* Enumerator functions (similar to sources) are easier to implement for some
  data structures such as `HashDict`.


## Common problems

* `function r/0 undefined` (where `r` is some variable on the left side of `<-`
  in a do-notation expression): Often this is caused by forgetting to use
  `Pipe.connect/2` when writing a conduit or sink with `Pipe.conduit` or
  `Pipe.sink`.
