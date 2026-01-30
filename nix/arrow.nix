{ nfx, api, ... }:
let
  inherit (api) mk;
  inherit (api.types) fn any;
in
mk {
  doc = ''
    Arrow utilities for pure function capabilities.

    Arrows are simpler than abilities - they are pure functions that can
    be stored in context and requested by name. Unlike abilities which
    return effects, arrows are just `A -> B` functions.

    ## Namespace Contents

    - `new` - Creates an arrow from a pure function
    - `request` - Requests an arrow by name and applies it
    - `adapt` - Transforms an arrow with pre/post functions

    ## Difference from Abilities
    - Ability: `Input -> Fx<S, Output>` (effectful)
    - Arrow: `Input -> Output` (pure)

    ## Example
    ```nix
    runFx (
      provide { double = x: x * 2; }
        (arrow.request "double" 21)
    )  # => 42
    ```

    ## See Also
    - `request` - For effectful abilities
    - `func` - For state-dependent pure functions
  '';
  value = {
    new = mk {
      doc = ''
        Creates an arrow from a pure function.

        Arrows are pure functions (`A -> B`) that can be stored in context
        and requested by name. Unlike abilities which return effects,
        arrows perform simple transformations.

        ## Type Signature
        `(A -> B) -> Arrow A B`

        ## Parameters
        - `f`: Pure function to wrap as arrow

        ## Example
        ```nix
        let double = arrow.new (x: x * 2);
        in double 21  # => 42

        # Store in context for later use
        provide {double = arrow.new (x: x * 2);} ...
        ```

        ## See Also
        - `request` - Retrieve arrow from context
        - `adapt` - Transform arrows
      '';
      type = fn any;
      value = f: f;
      tests = {
        "arrow.new creates arrow" = {
          expr = (nfx.arrow.new (x: x * 2)) 21;
          expected = 42;
        };
      };
    };

    request = mk {
      doc = ''
        Requests an arrow by name from context and applies it.

        Retrieves a stored arrow function from the context and applies
        it to an input value, returning the result wrapped in an effect.

        ## Type Signature
        `String -> A -> Fx<{name: Arrow A B}, B>`

        ## Parameters
        - `name`: Name of arrow in context
        - `i`: Input value

        ## Example
        ```nix
        runFx (
          provide {double = arrow.new (x: x * 2);} (
            arrow.request "double" 21
          )
        )  # => 42
        ```

        ## See Also
        - `new` - Create arrows
        - `request.request` - Request abilities (returns effects)
      '';
      type = fn (fn api.types.fx);
      value = name: i:
        nfx.pending (
          ctx:
          let
            f = ctx.${name};
          in
          nfx.immediate ctx (f i)
        );
      tests = {
        "arrow.request invokes arrow from context" = {
          expr = nfx.runFx (nfx.provide { double = x: x * 2; } (nfx.arrow.request "double" 21));
          expected = 42;
        };
      };
    };

    adapt = mk {
      doc = ''
        Transforms an arrow with pre/post processing functions.

        Wraps an arrow with preprocessing (contramap) and postprocessing
        (map) functions, creating a new arrow with adapted types.

        ## Type Signature
        `(A' -> A) -> (B -> B') -> Arrow A B -> Arrow A' B'`

        ## Parameters
        - `cmap`: Preprocess input (A' -> A)
        - `fmap`: Postprocess output (B -> B')
        - `f`: Original arrow
        - `i`: Input value

        ## Example
        ```nix
        let inc = x: x + 1;
            adapted = arrow.adapt (x: x * 2) (x: x * 10) inc;
        in adapted 5  # => (5 * 2 + 1) * 10 = 110
        ```

        ## See Also
        - `map` - Transform effect outputs
        - `contraMap` - Transform effect inputs
      '';
      type = fn (fn (fn any));
      value = cmap: fmap: f: i:
        fmap (f (cmap i));
      tests = {
        "arrow.adapt transforms arrow" = {
          expr =
            let
              f = x: x + 1;
              adapted = nfx.arrow.adapt (x: x * 2) (x: x * 10) f;
            in
            adapted 5;
          expected = 110;
        };
      };
    };
  };
}
