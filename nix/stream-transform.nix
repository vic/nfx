{ nfx, api, ... }:
let
  inherit (api) mk;
  inherit (api.types) fn any fx;
in
mk {
  doc = "Stream transformation operations - mapping and filtering";
  value = rec {
    map = mk {
      doc = ''
        Transforms each element in a stream.

        Applies a pure function to every value in the stream,
        preserving structure and laziness.

        ## Type Signature
        `(V -> U) -> Stream<S, V> -> Stream<S, U>`

        ## Parameters
        - `f`: Transformation function
        - `stream`: Source stream

        ## Example
        ```nix
        runFx (toList (map (x: x * 2) (fromList [1 2 3])))
        # => [2 4 6]
        ```

        ## See Also
        - `filter` - Select elements
        - `flatMap` - Transform and flatten
      '';
      type = fn (fn fx);
      value = f: stream:
        nfx.flatMap (step:
          if step.more
          then nfx.stream.more (f step.value) (map.value f step.next)
          else nfx.stream.done
        ) stream;
      tests = {
        "map.value transforms values" = {
          expr = nfx.runFx (
            nfx.stream.toList (map.value (x: x * 2) (nfx.stream.fromList [ 1 2 3 ]))
          );
          expected = [ 2 4 6 ];
        };
      };
    };

    filter = mk {
      doc = ''
        Keeps only elements matching a predicate.

        Lazily filters stream, skipping elements that don't match.
        May need to evaluate multiple steps to find next match.

        ## Type Signature
        `(V -> Bool) -> Stream<S, V> -> Stream<S, V>`

        ## Parameters
        - `pred`: Predicate function
        - `stream`: Source stream

        ## Example
        ```nix
        runFx (toList (filter (x: x > 2) (fromList [1 2 3 4])))
        # => [3 4]
        ```

        ## See Also
        - `takeWhile` - Take until predicate fails
        - `map` - Transform all elements
      '';
      type = fn (fn fx);
      value = pred: stream:
        nfx.flatMap (step:
          if !step.more
          then nfx.stream.done
          else if pred step.value
          then nfx.stream.more step.value (filter.value pred step.next)
          else filter.value pred step.next
        ) stream;
      tests = {
        "filter.value selects matching" = {
          expr = nfx.runFx (
            nfx.stream.toList (
              filter.value (x: x > 2) (nfx.stream.fromList [ 1 2 3 4 ])
            )
          );
          expected = [ 3 4 ];
        };
      };
    };
  };
}
