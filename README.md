# Elixir Pipes

A [conduit](http://hackage.haskell.org/package/conduit) like pipe system for
Elixir.

## Common problems

* `function r/0 undefined` (where `r` is some variable on the left side of `<-`
  in a do-notation expression): Often this is caused by forgetting to use
  `Pipe.connect/2` when writing a conduit or sink with `Pipe.conduit` or
  `Pipe.sink`.

## TODO

* Better documentation
