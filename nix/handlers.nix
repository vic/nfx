{ nfx, api, ... }:
let
  inherit (api) mk;
  inherit (api.types) fn fx;
in
mk {
  doc = "Effect handlers and middleware";
  value = {
    via = mk {
      doc = ''
        Applies a handler to an effect.

        A handler is any function that transforms effects, typically
        `Fx<A,U> -> Fx<B,V>`. This combinator simply applies the handler,
        providing a named operation for documentation and readability.

        ## Type Signature
        `(Fx<A,U> -> Fx<B,V>) -> Fx<A,U> -> Fx<B,V>`

        ## Parameters
        - `handler`: A function that transforms effects
        - `e`: The effect to handle

        ## Example
        ```nix
        # Apply a mapping handler
        via (map (x: x + 1)) (pure 41)  # => Fx producing 42

        # Chain multiple handlers
        via (map toString) (via (map (x: x * 2)) (pure 21))
        ```

        ## Notes
        While `via handler e` is equivalent to `handler e`, using `via`
        makes the intent clearer and enables future middleware patterns.

        ## See Also
        - `map`, `contraMap` - Common handlers
        - `provide` - Handler that eliminates requirements
      '';
      type = fn (fn fx);
      value = handler: e: handler e;
      tests = {
        "via applies handler" = {
          expr = nfx.runFx (nfx.via (nfx.map (x: x + 1)) (nfx.pure 41));
          expected = 42;
        };
      };
    };
  };
}
