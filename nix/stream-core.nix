{ nfx, api, ... }:
let
  inherit (api) mk;
  inherit (api.types) fn any fx;
in
mk {
  doc = "Stream constructors - building streams from values and lists";
  value = rec {
    done = mk {
      doc = ''
        Creates a terminated (empty) stream.

        Represents the end of a stream - no more elements to produce.
        This is the base case for stream recursion.

        ## Type Signature
        `Fx<{}, Step<{}, V>>`

        ## Example
        ```nix
        eval done.value  # => { more = false; }
        ```

        ## See Also
        - `more` - Continue stream with value
        - `fromList` - Create from list (empty list -> done)
      '';
      type = fx;
      value = nfx.pure { more = false; };
      tests = {
        "done.value terminates" = {
          expr = nfx.runFx done.value;
          expected = {
            more = false;
          };
        };
      };
    };

    more = mk {
      doc = ''
        Creates a stream step with value and continuation.

        Produces a stream that yields one value and continues with
        the next stream. The continuation is not evaluated until needed,
        enabling lazy, infinite streams.

        ## Type Signature
        `V -> Stream<S, V> -> Fx<{}, Step<S, V>>`

        ## Parameters
        - `value`: Value to yield
        - `next`: Continuation stream (lazy)

        ## Example
        ```nix
        more 1 (more 2 (more 3 done))
        # Stream of [1, 2, 3]
        ```

        ## See Also
        - `done` - Terminate stream
        - `fromList` - Build from list
      '';
      type = fn (fn fx);
      value =
        value: next:
        nfx.pure {
          more = true;
          inherit value next;
        };
      tests = {
        "more.value continues" = {
          expr = nfx.runFx (more.value 42 done.value);
          expected = {
            more = true;
            value = 42;
            next = done.value;
          };
        };
      };
    };

    fromList = mk {
      doc = ''
        Converts a list to a stream.

        Creates a stream that yields each list element in order.
        Empty list produces a terminated stream.

        ## Type Signature
        `[V] -> Stream<{}, V>`

        ## Parameters
        - `list`: List to convert

        ## Example
        ```nix
        runFx (toList (fromList [1 2 3]))  # => [1 2 3]
        runFx (fromList [])                # => { more = false; }
        ```

        ## See Also
        - `toList` - Convert stream to list
        - `singleton` - Single element stream
      '';
      type = fn fx;
      value =
        list:
        if list == [ ] then
          done.value
        else
          more.value (builtins.head list) (fromList.value (builtins.tail list));
      tests = {
        "fromList.value converts list" = {
          expr = nfx.runFx (
            nfx.stream.toList (
              fromList.value [
                1
                2
                3
              ]
            )
          );
          expected = [
            1
            2
            3
          ];
        };
        "fromList.value empty" = {
          expr = nfx.runFx (fromList.value [ ]);
          expected = {
            more = false;
          };
        };
      };
    };

    singleton = mk {
      doc = ''
        Creates a single-element stream.

        ## Type Signature
        `V -> Stream<{}, V>`

        ## Parameters
        - `value`: Single value to yield

        ## Example
        ```nix
        runFx (toList (singleton 42))  # => [42]
        ```

        ## See Also
        - `fromList` - Multiple elements
        - `done` - No elements
      '';
      type = fn fx;
      value = value: more.value value done.value;
      tests = {
        "singleton creates one-element stream" = {
          expr = nfx.runFx (nfx.stream.toList (singleton 42));
          expected = [ 42 ];
        };
      };
    };

    repeat = mk {
      doc = ''
        Repeats an effect n times as a stream.

        Creates a stream that executes the same effect n times,
        yielding each result. Useful for effectful generation.

        ## Type Signature
        `Int -> Fx<S, V> -> Stream<S, V>`

        ## Parameters
        - `n`: Number of times to repeat
        - `effect`: Effect to execute

        ## Example
        ```nix
        runFx (provide 5 (
          toList (repeat 3 state.get)
        ))  # => [5 5 5]
        ```

        ## See Also
        - `forEach` - Execute for each element
        - `map` - Transform elements
      '';
      type = fn (fn fx);
      value =
        n: effect:
        if n <= 0 then done.value else nfx.flatMap (v: more.value v (repeat.value (n - 1) effect)) effect;
      tests = {
        "repeat.value generates n elements" = {
          expr = nfx.runFx (nfx.stream.toList (repeat.value 3 (nfx.pure 42)));
          expected = [
            42
            42
            42
          ];
        };
        "repeat.value zero is empty" = {
          expr = nfx.runFx (repeat.value 0 (nfx.pure 1));
          expected = {
            more = false;
          };
        };
      };
    };
  };
}
