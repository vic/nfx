{ nfx, api, ... }:
let
  inherit (api) mk;
  inherit (api.types)
    fn
    any
    fx
    fxImmediate
    ;
in
mk {
  doc = "Basic effect constructors for lifting values";
  value = {
    pure = mk {
      doc = ''
        Creates a pure (effect-free) value with no context requirements.

        This is the simplest way to lift a plain value into the effect system.
        The resulting effect is immediately available and requires no context.
        Equivalent to `immediate {}`.

        ## Type Signature
        `V -> Fx<{}, V>`

        ## Parameters
        - `value`: Any value to wrap in an effect

        ## Example
        ```nix
        pure 42           # => Fx<{}, Int>
        pure "hello"      # => Fx<{}, String>
        runFx (pure 42)    # => 42
        ```

        ## See Also
        - `value` - Similar but preserves any context type
        - `immediate` - Lower-level constructor used internally
      '';
      type = fn fxImmediate;
      value = value: nfx.immediate { } value;
      tests = {
        "pure creates immediate with unit state" = {
          expr = nfx.runFx (nfx.pure 42);
          expected = 42;
        };
      };
    };

    value = mk {
      doc = ''
        Creates an effect that produces a value while preserving any context.

        Unlike `pure` which requires empty context, `value` works polymorphically
        over any context type. The context passes through unchanged.

        ## Type Signature
        `V -> Fx<S, V>` (for any S)

        ## Parameters
        - `v`: The value to produce

        ## Example
        ```nix
        # Works in any context
        provide { x = 1; } (value 42)  # => 42

        # Useful in sequencing when you need a constant
        mapM (x: value (x * 2)) someEffect
        ```

        ## See Also
        - `pure` - When you know context is empty
        - `func` - When value depends on state
      '';
      type = fn fx;
      value = v: nfx.pending (s: nfx.immediate s v);
      tests = {
        "value passes through context" = {
          expr =
            let
              fx = nfx.value 42;
            in
            nfx.runFx (nfx.provide { x = 1; } fx);
          expected = 42;
        };
      };
    };
  };
}
