{ nfx, api, ... }:
let
  inherit (api) mk;
  inherit (api.types) fn fx;
in
mk {
  doc = "Pair context transformation utilities";
  value = {
    andNil = mk {
      doc = ''
        Extends an effect's context with unit on the right.

        Transforms an effect requiring `S` to one requiring `{fst: S, snd: {}}`.
        This is useful for uniformity when combining with effects that use
        paired contexts.

        ## Type Signature
        `Fx<S, V> -> Fx<{fst: S, snd: {}}, V>`

        ## Parameters
        - `e`: Effect to extend

        ## Example
        ```nix
        runFx (
          provide { fst = 10; snd = {}; } (
            andNil (pending (n: immediate n (n * 2)))
          )
        )  # => 20
        ```

        ## See Also
        - `andCollapse` - Opposite direction (merges same-type pairs)
        - `flatMap` - Creates paired context requirements
      '';
      type = fn fx;
      value =
        e:
        nfx.contraMap (p: p.fst) (_: s: {
          fst = s;
          snd = { };
        }) e;
      tests = {
        "andNil extends with unit" = {
          expr = nfx.runFx (
            nfx.provide {
              fst = 10;
              snd = { };
            } (nfx.andNil (nfx.pending (n: nfx.immediate n (n * 2))))
          );
          expected = 20;
        };
      };
    };

    andCollapse = mk {
      doc = ''
        Collapses a paired context where both parts are the same type.

        When an effect requires `{fst: S, snd: S}`, this transforms it to
        require just `S`, duplicating the single context to satisfy both sides.

        ## Type Signature
        `Fx<{fst: S, snd: S}, V> -> Fx<S, V>`

        ## Parameters
        - `e`: Effect requiring paired same-type context

        ## Example
        ```nix
        runFx (
          provide 10 (
            andCollapse (
              pending (p: immediate p (p.fst + p.snd))
            )
          )
        )  # => 20 (10 + 10)
        ```

        ## See Also
        - `andNil` - Extends with unit instead
        - `andSwap` - Swaps pair components
      '';
      type = fn fx;
      value =
        e:
        nfx.contraMap (s: {
          fst = s;
          snd = s;
        }) (_: p: p.snd) e;
      tests = {
        "andCollapse merges same-type contexts" = {
          expr = nfx.runFx (
            nfx.provide 10 (nfx.andCollapse (nfx.pending (p: nfx.immediate p (p.fst + p.snd))))
          );
          expected = 20;
        };
      };
    };

    andSwap = mk {
      doc = ''
        Swaps the components of a paired context requirement.

        Transforms an effect requiring `{fst: A, snd: B}` to one requiring
        `{fst: B, snd: A}`. Useful for reordering context structure.

        ## Type Signature
        `Fx<{fst: A, snd: B}, V> -> Fx<{fst: B, snd: A}, V>`

        ## Parameters
        - `e`: Effect requiring paired context

        ## Example
        ```nix
        runFx (
          provide { fst = "hello"; snd = 10; } (
            andSwap (
              pending (p: immediate p p.fst)
            )
          )
        )  # => 10 (was in snd, now accessed as fst)
        ```

        ## See Also
        - `pair.swap` - Underlying pair operation
        - `andCollapse` - Merges same-type pairs
      '';
      type = fn fx;
      value = e: nfx.contraMap nfx.pair.bwd (_: p: nfx.pair.bwd p) e;
      tests = {
        "andSwap swaps pair components" = {
          expr = nfx.runFx (
            nfx.provide {
              fst = "hello";
              snd = 10;
            } (nfx.andSwap (nfx.pending (p: nfx.immediate p p.fst)))
          );
          expected = 10;
        };
      };
    };
  };
}
