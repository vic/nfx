{ nfx, api, ... }:
let
  inherit (api) mk;
  inherit (api.types) fn any fx;
in
mk {
  doc = "Stream combination operations - concatenating, interleaving, and zipping streams";
  value = rec {
    concat = mk {
      doc = ''
        Concatenates two streams.

        Yields all elements from first stream, then all from second.
        Second stream is not evaluated until first completes.

        ## Type Signature
        `Stream<S, V> -> Stream<S, V> -> Stream<S, V>`

        ## Parameters
        - `s1`: First stream
        - `s2`: Second stream

        ## Example
        ```nix
        runFx (toList (concat (fromList [1 2]) (fromList [3 4])))
        # => [1 2 3 4]
        ```

        ## See Also
        - `flatten` - Concatenate stream of streams
        - `zip` - Combine elements pairwise
      '';
      type = fn (fn fx);
      value = s1: s2:
        nfx.flatMap (step:
          if step.more
          then nfx.stream.more step.value (concat.value step.next s2)
          else s2
        ) s1;
      tests = {
        "concat.value joins streams" = {
          expr = nfx.runFx (
            nfx.stream.toList (
              concat.value (nfx.stream.fromList [ 1 2 ]) (nfx.stream.fromList [ 3 4 ])
            )
          );
          expected = [ 1 2 3 4 ];
        };
      };
    };

    interleave = mk {
      doc = ''
        Fair interleaving of two streams (miniKanren-style mplus).

        Alternates between streams for complete search. Unlike `concat`
        which exhausts first stream before trying second, `interleave`
        swaps streams at each step ensuring fairness.

        Essential for logic programming where infinite streams must be
        explored fairly.

        ## Type Signature
        `Stream<S, V> -> Stream<S, V> -> Stream<S, V>`

        ## Parameters
        - `s1`: First stream
        - `s2`: Second stream

        ## Example
        ```nix
        # With concat, infinite stream blocks second
        # With interleave, both explored fairly
        runFx (take 6 (interleave
          (fromList [1 2 3])
          (fromList [10 20 30])))
        # => [1 10 2 20 3 30]
        ```

        ## See Also
        - `concat` - Unfair concatenation (exhausts first)
        - `flatten` - For stream of streams
        - Logic programming: mplus (OR) operation
      '';
      type = fn (fn fx);
      value = s1: s2:
        nfx.flatMap (step:
          if step.more
          then nfx.stream.more step.value (interleave.value s2 step.next)
          else s2
        ) s1;
      tests = {
        "interleave.value fairly alternates" = {
          expr = nfx.runFx (
            nfx.stream.toList (
              interleave.value
                (nfx.stream.fromList [ 1 2 3 ])
                (nfx.stream.fromList [ 10 20 30 ])
            )
          );
          expected = [ 1 10 2 20 3 30 ];
        };
        "interleave.value handles empty first" = {
          expr = nfx.runFx (
            nfx.stream.toList (
              interleave.value
                nfx.stream.done
                (nfx.stream.fromList [ 1 2 ])
            )
          );
          expected = [ 1 2 ];
        };
        "interleave.value handles empty second" = {
          expr = nfx.runFx (
            nfx.stream.toList (
              interleave.value
                (nfx.stream.fromList [ 1 2 ])
                nfx.stream.done
            )
          );
          expected = [ 1 2 ];
        };
      };
    };

    flatten = mk {
      doc = ''
        Flattens a stream of streams into a single stream.

        Concatenates all inner streams in order. Useful after
        mapping operations that produce streams.

        ## Type Signature
        `Stream<S, Stream<S, V>> -> Stream<S, V>`

        ## Parameters
        - `stream`: Stream of streams

        ## Example
        ```nix
        runFx (toList (flatten (fromList [
          fromList [1 2]
          fromList [3 4]
        ])))  # => [1 2 3 4]
        ```

        ## See Also
        - `flatMap` - Map and flatten
        - `concat` - Join two streams
        - `interleave` - Fair stream combination
      '';
      type = fn fx;
      value = stream:
        nfx.flatMap (step:
          if !step.more
          then nfx.stream.done
          else concat.value step.value (flatten.value step.next)
        ) stream;
      tests = {
        "flatten.value concatenates nested" = {
          expr = nfx.runFx (
            nfx.stream.toList (
              flatten.value (
                nfx.stream.fromList [
                  (nfx.stream.fromList [ 1 2 ])
                  (nfx.stream.fromList [ 3 4 ])
                ]
              )
            )
          );
          expected = [ 1 2 3 4 ];
        };
      };
    };

    flatMap = mk {
      doc = ''
        Maps each element to a stream and flattens.

        Powerful combinator for complex stream transformations.
        Each element can produce zero or more output elements.

        ## Type Signature
        `(V -> Stream<S, U>) -> Stream<S, V> -> Stream<S, U>`

        ## Parameters
        - `f`: Function producing stream
        - `stream`: Source stream

        ## Example
        ```nix
        runFx (toList (flatMap (x: fromList [x x]) (fromList [1 2])))
        # => [1 1 2 2]
        ```

        ## See Also
        - `map` - Transform values
        - `flatten` - Flatten without mapping
      '';
      type = fn (fn fx);
      value = f: stream:
        nfx.flatMap (step:
          if !step.more
          then nfx.stream.done
          else concat.value (f step.value) (flatMap.value f step.next)
        ) stream;
      tests = {
        "flatMap.value duplicates elements" = {
          expr = nfx.runFx (
            nfx.stream.toList (
              flatMap.value
                (x: nfx.stream.fromList [ x x ])
                (nfx.stream.fromList [ 1 2 ])
            )
          );
          expected = [ 1 1 2 2 ];
        };
      };
    };

    zip = mk {
      doc = ''
        Zips two streams into pairs.

        Combines elements pairwise. Terminates when either stream ends.

        ## Type Signature
        `Stream<S, A> -> Stream<S, B> -> Stream<S, {fst: A, snd: B}>`

        ## Parameters
        - `s1`: First stream
        - `s2`: Second stream

        ## Example
        ```nix
        runFx (toList (zip (fromList [1 2]) (fromList ["a" "b"])))
        # => [{fst=1; snd="a";} {fst=2; snd="b";}]
        ```

        ## See Also
        - `pair.make` - Create pairs
        - `concat` - Sequential combination
      '';
      type = fn (fn fx);
      value = s1: s2:
        nfx.flatMap (step1:
          if !step1.more
          then nfx.stream.done
          else nfx.flatMap (step2:
            if !step2.more
            then nfx.stream.done
            else nfx.stream.more
              {
                fst = step1.value;
                snd = step2.value;
              }
              (zip.value step1.next step2.next)
          ) s2
        ) s1;
      tests = {
        "zip pairs elements" = {
          expr = nfx.runFx (
            nfx.stream.toList (
              zip.value
                (nfx.stream.fromList [ 1 2 3 ])
                (nfx.stream.fromList [ 4 5 6 ])
            )
          );
          expected = [
            { fst = 1; snd = 4; }
            { fst = 2; snd = 5; }
            { fst = 3; snd = 6; }
          ];
        };
      };
    };
  };
}
