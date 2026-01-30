{ nfx, api, ... }:
let
  inherit (api) mk;
  inherit (api.types) fn any fx;
in
mk {
  doc = "Stream reduction operations - folding, collecting, and iterating";
  value = rec {
    fold = mk {
      doc = ''
        Reduces stream to single value with effectful accumulator.

        Threads accumulator through stream, applying function to each
        element. The accumulator function can be effectful.

        ## Type Signature
        `A -> (A -> V -> Fx<S, A>) -> Stream<S, V> -> Fx<S, A>`

        ## Parameters
        - `initial`: Initial accumulator
        - `f`: Accumulator function
        - `stream`: Source stream

        ## Example
        ```nix
        runFx (fold 0 (acc: x: pure (acc + x)) (fromList [1 2 3]))
        # => 6
        ```

        ## See Also
        - `toList` - Collect to list
        - `forEach` - Execute for side effects
      '';
      type = fn (fn (fn fx));
      value = initial: f: stream:
        nfx.flatMap (step:
          if !step.more
          then nfx.pure initial
          else nfx.flatMap (acc:
            fold.value acc f step.next
          ) (f initial step.value)
        ) stream;
      tests = {
        "fold.value reduces to value" = {
          expr = nfx.runFx (
            fold.value 0 (acc: x: nfx.pure (acc + x)) (nfx.stream.fromList [ 1 2 3 ])
          );
          expected = 6;
        };
      };
    };

    toList = mk {
      doc = ''
        Collects all stream elements to a list.

        Forces entire stream evaluation and gathers results.
        Be careful with infinite streams!

        ## Type Signature
        `Stream<S, V> -> Fx<S, [V]>`

        ## Parameters
        - `stream`: Source stream

        ## Example
        ```nix
        runFx (toList (fromList [1 2 3]))  # => [1 2 3]
        ```

        ## See Also
        - `fromList` - Convert from list
        - `fold` - Custom reduction
      '';
      type = fn fx;
      value = stream:
        fold.value [ ] (acc: v: nfx.pure (acc ++ [ v ])) stream;
      tests = {
        "toList.value collects elements" = {
          expr = nfx.runFx (toList.value (nfx.stream.fromList [ 1 2 3 ]));
          expected = [ 1 2 3 ];
        };
      };
    };

    forEach = mk {
      doc = ''
        Executes an effect for each stream element.

        Runs side effects while consuming stream. Returns unit.
        The effect can access and modify context.

        ## Type Signature
        `(V -> Fx<S, {}>) -> Stream<S, V> -> Fx<S, {}>`

        ## Parameters
        - `f`: Effect to execute
        - `stream`: Source stream

        ## Example
        ```nix
        # Print each element (conceptually)
        runFx (forEach (x: state.modify (s: s + x)) stream)
        ```

        ## See Also
        - `fold` - Reduce with accumulator
        - `map` - Transform without consuming
      '';
      type = fn (fn fx);
      value = f: stream:
        fold.value { } (acc: v: nfx.map (_: acc) (f v)) stream;
      tests = {
        "forEach executes for each" = {
          expr = nfx.runFx (
            nfx.provide 0 (
              nfx.then' nfx.state.get (
                forEach
                  (x: nfx.state.modify (s: s + x))
                  (nfx.stream.fromList [ 1 2 3 ])
              )
            )
          );
          expected = 6;
        };
      };
    };
  };
}
