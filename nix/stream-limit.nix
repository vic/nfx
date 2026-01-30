{ nfx, api, ... }:
let
  inherit (api) mk;
  inherit (api.types) fn any fx;
in
mk {
  doc = "Stream limiting operations - taking first n elements or while condition holds";
  value = rec {
    take = mk {
      doc = ''
        Takes first n elements from stream.

        Terminates after n elements even if source continues.
        Enables working with infinite streams.

        ## Type Signature
        `Int -> Stream<S, V> -> Stream<S, V>`

        ## Parameters
        - `n`: Number of elements to take
        - `stream`: Source stream

        ## Example
        ```nix
        runFx (toList (take 2 (fromList [1 2 3 4])))
        # => [1 2]
        ```

        ## See Also
        - `takeWhile` - Take until condition
        - `filter` - Conditional selection
      '';
      type = fn (fn fx);
      value = n: stream:
        if n <= 0
        then nfx.stream.done
        else nfx.flatMap (step:
          if step.more
          then nfx.stream.more step.value (take.value (n - 1) step.next)
          else nfx.stream.done
        ) stream;
      tests = {
        "take.value limits elements" = {
          expr = nfx.runFx (
            nfx.stream.toList (take.value 2 (nfx.stream.fromList [ 1 2 3 4 ]))
          );
          expected = [ 1 2 ];
        };
        "take.value zero is empty" = {
          expr = nfx.runFx (take.value 0 (nfx.stream.fromList [ 1 2 3 ]));
          expected = { more = false; };
        };
      };
    };

    takeWhile = mk {
      doc = ''
        Takes elements while predicate holds.

        Terminates on first element that doesn't match predicate.

        ## Type Signature
        `(V -> Bool) -> Stream<S, V> -> Stream<S, V>`

        ## Parameters
        - `pred`: Predicate to test
        - `stream`: Source stream

        ## Example
        ```nix
        runFx (toList (takeWhile (x: x < 3) (fromList [1 2 3 4])))
        # => [1 2]
        ```

        ## See Also
        - `take` - Take fixed number
        - `filter` - Keep all matching
      '';
      type = fn (fn fx);
      value = pred: stream:
        nfx.flatMap (step:
          if !step.more || !pred step.value
          then nfx.stream.done
          else nfx.stream.more step.value (takeWhile.value pred step.next)
        ) stream;
      tests = {
        "takeWhile.value stops on false" = {
          expr = nfx.runFx (
            nfx.stream.toList (
              takeWhile.value (x: x < 3) (nfx.stream.fromList [ 1 2 3 4 ])
            )
          );
          expected = [ 1 2 ];
        };
      };
    };
  };
}
