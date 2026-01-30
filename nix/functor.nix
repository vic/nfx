{ nfx, api, ... }:
let
  inherit (api) mk;
  inherit (api.types) fn any fx;
in
mk {
  doc = "Functor operations for transforming effects";
  value = {
    map = mk {
      doc = ''
        Functor map: transforms the value inside an effect.

        Applies a pure function to the result of an effect without changing
        the effect's context requirements. This is the standard functor fmap.

        ## Type Signature
        `(V -> U) -> Fx<S, V> -> Fx<S, U>`

        ## Parameters
        - `f`: A pure function `V -> U`
        - `e`: The effect to transform

        ## Example
        ```nix
        map (x: x * 2) (pure 21)  # => Fx producing 42
        map toString (pure 42)    # => Fx producing "42"
        ```

        ## Laws
        - Identity: `map id e == e`
        - Composition: `map (f . g) e == map f (map g e)`

        ## See Also
        - `mapM` - When transformation produces an effect
        - `contraMap` - For transforming context instead of value
      '';
      type = fn (fn fx);
      value =
        f: e:
        nfx.adapt e (s: s) (
          _t: s: v:
          nfx.immediate s (f v)
        );
      tests = {
        "map transforms value" = {
          expr = nfx.runFx (nfx.map (x: x * 2) (nfx.pure 21));
          expected = 42;
        };
        "map preserves state" = {
          expr =
            let
              fx = nfx.map (x: x + 1) (nfx.pending (s: nfx.immediate s s.n));
            in
            nfx.runFx (nfx.provide { n = 10; } fx);
          expected = 11;
        };
      };
    };

    contraMap = mk {
      doc = ''
        Transforms context requirements (contravariant mapping).

        Adapts an effect that needs context `Inner` to work in context `Outer`.
        This is how effects compose when they have different requirements -
        you can zoom into a larger context to satisfy a smaller requirement.

        ## Type Signature
        `(Outer -> Inner) -> (Outer -> Inner -> Outer) -> Fx<Inner,V> -> Fx<Outer,V>`

        ## Parameters
        - `getter`: Extracts inner context from outer `Outer -> Inner`
        - `setter`: Updates outer context given new inner state `Outer -> Inner -> Outer`
        - `e`: Effect requiring `Inner`

        ## Example
        ```nix
        # Effect needing a number
        inner = pending (n: immediate n (n * 2))

        # Adapt to work in record containing the number
        outer = contraMap
          (ctx: ctx.num)
          (ctx: n: ctx // { num = n; })
          inner

        runFx (provide { num = 5; other = "x"; } outer)  # => 10
        ```

        ## See Also
        - `lift` - Named attribute version of contraMap
        - `lens.zoomOut` - Lens-based focusing
      '';
      type = fn (fn (fn fx));
      value =
        getter: setter: e:
        nfx.adapt e (outer: getter outer) (
          outer: inner: v:
          nfx.immediate (setter outer inner) v
        );
      tests = {
        "contraMap extracts nested context" = {
          expr =
            let
              inner = nfx.pending (n: nfx.immediate n (n * 2));
              outer = nfx.contraMap (ctx: ctx.num) (ctx: n: ctx // { num = n; }) inner;
            in
            nfx.runFx (
              nfx.provide {
                num = 5;
                other = "x";
              } outer
            );
          expected = 10;
        };
      };
    };
  };
}
