defmodule Pipe.ListTest do
  use ExUnit.Case

  require Pipe, as: P
  alias Pipe.List, as: PL

  test "map" do
    assert P.connect([P.yield(4), PL.map(&(&1+1)), P.await_result()]) == { :value, 5 }
    assert P.connect([P.done(0), PL.map(&(&1+1)), P.await_result()]) == { :result, 0 }
    
    assert P.connect([P.yield(4), PL.map(&(&1+1)), PL.skip_all()]) == nil 
    assert P.connect([P.done(0), PL.map(&(&1+1)), PL.skip_all()]) == 0
  end
  
  test "source_list, filter and consume" do
    assert P.connect([PL.source_list([1,2,3,4]), PL.filter(&(rem(&1, 2) == 0)), PL.consume()]) == [2,4]
    assert P.connect([PL.source_list([]), PL.filter(&(rem(&1, 2) == 0)), PL.consume()]) == []
    
    assert P.connect([PL.source_list([1,2,3,4]), PL.filter(&(rem(&1, 2) == 0)), PL.skip_all()]) == nil
  end

  # take_while is a typical leftover generating function.
  test "take_while" do
    assert P.connect([
      PL.source_list([1,2,3]),
      P.sink do
        a <- PL.take_while(&(&1 < 3))
        b <- PL.consume()
        return {a, b}
      end])== { [1,2], [3] }
    assert P.connect([
      PL.source_list([3,4]),
      P.sink do
        a <- PL.take_while(&(&1 < 3))
        b <- PL.consume()
        return {a, b}
      end]) == { [], [3,4] }
  end

  defmodule ReadmeExamples do
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
  end

  test "terminated_by_semicolon example from README" do
    assert P.connect([
      PL.source_list(["AB;C", "D;E", ";", "F"]),
      ReadmeExamples.terminated_by_semicolon(),
      PL.consume()]) == ["AB", "CD", "E"]
    assert P.connect([
      PL.source_list(["AB;C", "D;E", ";"]),
      ReadmeExamples.terminated_by_semicolon(),
      PL.consume()]) == ["AB", "CD", "E"]
  end
end
