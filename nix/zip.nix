{ nfx, api, ... }:
let
  inherit (api) mk;
  inherit (api.types) fn fx;
in
mk {
  doc = "Zip utilities for combining effects";
  value = {
    zip = mk {
      doc = ''
        Combines two effects into one producing a pair of values.

        Both effects share the same context type. The result is an effect
        producing `{fst: V1, snd: V2}` containing both values.

        ## Type Signature
        `Fx<S, V2> -> Fx<S, V1> -> Fx<S, {fst: V1, snd: V2}>`

        ## Parameters
        - `other`: Second effect (provides `snd`)
        - `e`: First effect (provides `fst`)

        ## Example
        ```nix
        runFx (zip (pure 2) (pure 1))  # => { fst = 1; snd = 2; }
        ```

        ## Notes
        The order may seem reversed because it's designed for piping:
        `e |> zip other` runs `e` first, then `other`.

        ## See Also
        - `zipLeft` - Keeps only first value
        - `zipRight` - Keeps only second value
      '';
      type = fn (fn fx);
      value =
        other: e:
        nfx.mapM (
          v1:
          nfx.map (v2: {
            fst = v1;
            snd = v2;
          }) other
        ) e;
      tests = {
        "zip combines values" = {
          expr = nfx.runFx (nfx.zip (nfx.pure 2) (nfx.pure 1));
          expected = {
            fst = 1;
            snd = 2;
          };
        };
      };
    };

    zipLeft = mk {
      doc = ''
        Combines two effects, keeping only the first value.

        Runs both effects in sequence but discards the second value.
        Useful when the second effect is run only for its side effects.

        ## Type Signature
        `Fx<S, V2> -> Fx<S, V1> -> Fx<S, V1>`

        ## Parameters
        - `other`: Second effect (value discarded)
        - `e`: First effect (value kept)

        ## Example
        ```nix
        runFx (zipLeft (pure 2) (pure 1))  # => 1
        ```

        ## See Also
        - `zip` - Keeps both values
        - `zipRight` - Keeps second value
        - `then'` - Similar but second effect runs first conceptually
      '';
      type = fn (fn fx);
      value = other: e: nfx.mapM (v: nfx.map (_: v) other) e;
      tests = {
        "zipLeft keeps first" = {
          expr = nfx.runFx (nfx.zipLeft (nfx.pure 2) (nfx.pure 1));
          expected = 1;
        };
      };
    };

    zipRight = mk {
      doc = ''
        Combines two effects, keeping only the second value.

        Runs both effects in sequence but discards the first value.
        Useful when the first effect is run only for its side effects.

        ## Type Signature
        `Fx<S, V2> -> Fx<S, V1> -> Fx<S, V2>`

        ## Parameters
        - `other`: Second effect (value kept)
        - `e`: First effect (value discarded)

        ## Example
        ```nix
        runFx (zipRight (pure 2) (pure 1))  # => 2
        ```

        ## See Also
        - `zip` - Keeps both values
        - `zipLeft` - Keeps first value
      '';
      type = fn (fn fx);
      value = other: e: nfx.mapM (_: other) e;
      tests = {
        "zipRight keeps second" = {
          expr = nfx.runFx (nfx.zipRight (nfx.pure 2) (nfx.pure 1));
          expected = 2;
        };
      };
    };
  };
}
