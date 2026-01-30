{ nfx, api, ... }:
let
  inherit (api) mk;
  inherit (api.types) fn any fx;
in
mk {
  doc = "Do-notation for readable effect sequencing";
  value = {
    do = mk {
      doc = ''
        Monadic do-notation for composing effects with binding.

        Takes a list of functions `V -> Fx<S, U>` and chains them left-to-right,
        threading values through. Each function receives the result of the previous
        computation. Much more readable than nested `mapM` calls.

        The first function receives `null` as input (use `_:` to ignore).
        The last function's result becomes the final value.

        ## Type Signature
        `[V -> Fx<S, V>] -> Fx<S, V>`

        ## Parameters
        - `steps`: List of functions to chain

        ## Example
        ```nix
        # Instead of nested mapM:
        mapM (user:
          mapM (posts:
            mapM (comments:
              pure (processAll user posts comments)
            ) (getComments posts)
          ) (getPosts user)
        ) getUser

        # Use do notation:
        do [
          (_: getUser)
          (user: getPosts user)
          (posts: getComments posts)
          (comments: pure (processAll user posts comments))
        ]
        ```

        ## See Also
        - `do'` - Sequence effects without binding
        - `mapM` - Single monadic bind
        - `then'` - Sequence ignoring first value
      '';
      type = fn fx;
      value = steps:
        builtins.foldl'
          (acc: step: nfx.mapM step acc)
          (nfx.pure null)
          steps;
      tests = {
        "do chains effects with binding" = {
          expr = nfx.runFx (
            nfx.do [
              (_: nfx.pure 10)
              (x: nfx.pure (x * 2))
              (y: nfx.pure (y + 1))
            ]
          );
          expected = 21;
        };
        "do threads state" = {
          expr = nfx.runFx (
            nfx.provide 5 (
              nfx.do [
                (_: nfx.state.get)
                (s: nfx.pure (s * 2))
                (x: nfx.mapM (_: nfx.pure x) (nfx.state.modify (n: n + 1)))
              ]
            )
          );
          expected = 10;
        };
      };
    };

    do' = mk {
      doc = ''
        Sequence effects left-to-right, returning the last value.

        Takes a list of effects and runs them in order, discarding intermediate
        values. Useful for side effects (state changes, logging) when you only
        care about the final result.

        More readable than nested `then'` calls.

        ## Type Signature
        `[Fx<S, V>] -> Fx<S, V>`

        ## Parameters
        - `effects`: List of effects to sequence

        ## Example
        ```nix
        # Instead of nested then':
        then' result (
          then' (state.modify inc) (
            then' (tell "starting") (
              tell "init"
            )))

        # Use do' notation:
        do' [
          (tell "init")
          (tell "starting")
          (state.modify inc)
          result
        ]
        ```

        ## See Also
        - `do` - With value binding
        - `then'` - Sequence two effects
      '';
      type = fn fx;
      value = effects:
        builtins.foldl'
          (acc: e: nfx.then' e acc)
          (builtins.head effects)
          (builtins.tail effects);
      tests = {
        "do' sequences effects" = {
          expr = nfx.runFx (
            nfx.do' [
              (nfx.pure 1)
              (nfx.pure 2)
              (nfx.pure 42)
            ]
          );
          expected = 42;
        };
        "do' runs side effects" = {
          expr = nfx.runFx (
            nfx.provide 0 (
              nfx.do' [
                (nfx.state.modify (x: x + 1))
                (nfx.state.modify (x: x * 2))
                (nfx.state.get)
              ]
            )
          );
          expected = 2;
        };
      };
    };
  };
}
