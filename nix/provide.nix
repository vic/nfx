{ nfx, api, ... }:
let
  inherit (api) mk;
  inherit (api.types) fn any fx;
in
mk {
  doc = "Context provision and manipulation";
  value = {
    provide = mk {
      doc = ''
        Satisfies a context requirement, eliminating it.

        This is the primary way to "run" effects - by providing the context
        they need. The provided value becomes the context for the inner effect,
        and the resulting effect has no requirements for that context.

        ## Type Signature
        `S -> Fx<S, V> -> Fx<T, V>` (for any T)

        ## Parameters
        - `s`: The context value to provide
        - `e`: Effect that requires context `S`

        ## Example
        ```nix
        # Effect needing a number
        double = pending (n: immediate n (n * 2))

        # Provide the number to get a runnable effect
        runFx (provide 21 double)  # => 42

        # Provide a record context
        runFx (provide { x = 5; y = 3; }
          (pending (ctx: immediate ctx (ctx.x + ctx.y))))  # => 8
        ```

        ## See Also
        - `provideLeft` - Provides left side of paired context
        - `providePart` - Provides part using custom getter/setter
      '';
      type = fn (fn fx);
      value = s: e: nfx.contraMap (_: s) (t: _s: t) e;
      tests = {
        "provide satisfies requirement" = {
          expr = nfx.runFx (nfx.provide 10 (nfx.pending (n: nfx.immediate n (n + 1))));
          expected = 11;
        };
        "provide with attrset context" = {
          expr = nfx.runFx (
            nfx.provide {
              x = 5;
              y = 3;
            } (nfx.pending (ctx: nfx.immediate ctx (ctx.x + ctx.y)))
          );
          expected = 8;
        };
      };
    };

    provideLeft = mk {
      doc = ''
        Provides the left component of a paired context requirement.

        When an effect requires `{fst: A, snd: B}`, this provides the `A`
        part, leaving an effect that only requires `B`.

        ## Type Signature
        `A -> Fx<{fst: A, snd: B}, V> -> Fx<B, V>`

        ## Parameters
        - `a`: Value for the left/first context component
        - `e`: Effect requiring paired context

        ## Example
        ```nix
        provide 20 (
          provideLeft 10
            (pending (ctx: immediate ctx (ctx.fst + ctx.snd)))
        )  # => 30
        ```

        ## See Also
        - `provide` - Provides entire context
        - `andNil` - Extends context given unit on right
      '';
      type = fn (fn fx);
      value = a: e:
        nfx.contraMap (b: {
          fst = a;
          snd = b;
        }) (_b: ctx: ctx.snd) e;
      tests = {
        "provideLeft provides fst" = {
          expr = nfx.runFx (
            nfx.provide 20 (nfx.provideLeft 10 (nfx.pending (ctx: nfx.immediate ctx (ctx.fst + ctx.snd))))
          );
          expected = 30;
        };
      };
    };

    providePart = mk {
      doc = ''
        Provides part of a context using custom getter/setter.

        A generalized version of `provide` that allows partial satisfaction
        of context requirements using custom lensing functions.

        ## Type Signature
        `A -> (A -> B -> S) -> (B -> S -> B) -> Fx<S, V> -> Fx<B, V>`

        ## Parameters
        - `a`: Value to inject into context
        - `cmap`: Combines `A` and remaining context `B` to form full context `S`
        - `fmap`: Extracts remaining context from result state
        - `e`: Effect requiring full context `S`

        ## Example
        ```nix
        provide 5 (
          providePart 10
            (a: b: { x = a; y = b; })
            (_b: ctx: ctx.y)
            (pending (ctx: immediate ctx (ctx.x + ctx.y)))
        )  # => 15
        ```

        ## See Also
        - `provide` - Simpler full context provision
        - `provideLeft` - Standard paired context provision
      '';
      type = fn (fn (fn (fn fx)));
      value = a: cmap: fmap: e:
        nfx.contraMap (b: cmap a b) fmap e;
      tests = {
        "providePart provides partial context" = {
          expr = nfx.runFx (
            nfx.provide 5 (
              nfx.providePart 10 (a: b: {
                x = a;
                y = b;
              }) (_b: ctx: ctx.y) (nfx.pending (ctx: nfx.immediate ctx (ctx.x + ctx.y)))
            )
          );
          expected = 15;
        };
      };
    };

    func = mk {
      doc = ''
        Creates an effect from a function on state.

        This is a convenience combinator that reads the state and applies
        a pure function to produce the value. Equivalent to `map f state.get`.

        ## Type Signature
        `(S -> V) -> Fx<S, V>`

        ## Parameters
        - `f`: A pure function from state to value

        ## Example
        ```nix
        provide 10 (func (n: n * 2))  # => 20
        provide { x = 5; } (func (ctx: ctx.x + 1))  # => 6
        ```

        ## See Also
        - `state.get` - Just reads state without transformation
        - `map` - Transforms value of an existing effect
      '';
      type = fn fx;
      value = f: nfx.map f nfx.state.get;
      tests = {
        "func applies function to state" = {
          expr = nfx.runFx (nfx.provide 10 (nfx.func (n: n * 2)));
          expected = 20;
        };
      };
    };
  };
}
