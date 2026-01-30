{ nfx, api, ... }:
let
  inherit (api) mk;
  inherit (api.types) fn fx;
in
mk {
  doc = "Ability request mechanism";
  value = {
    request = mk {
      doc = ''
        Requests an ability by name from the context.

        This is the primary mechanism for invoking capabilities. The context
        must provide an attribute with the given name, which should be a
        function (ability) that handles the input and returns an effect.

        ## Type Signature
        `String -> Input -> Fx<{name: Input -> Fx<S,O>}, O>`

        ## Parameters
        - `name`: Name of the ability to invoke
        - `input`: Input to pass to the ability

        ## Example
        ```nix
        runFx (
          provide { double = x: pure (x * 2); }
            (request "double" 21)
        )  # => 42
        ```

        ## How It Works
        1. Creates a pending effect
        2. When evaluated, extracts the ability from context by name
        3. Calls the ability with the input
        4. Returns the ability's result

        ## Notes
        Abilities are effectful handlers - they receive input and return
        effects. For pure functions, use `arrow.request` instead.

        ## See Also
        - `arrow.request` - For pure functions in context
        - `provide` - Supplies abilities to effects
      '';
      type = fn (fn fx);
      value =
        name: input:
        nfx.pending (
          ctx:
          let
            ability = ctx.${name};
          in
          ability input
        );
      tests = {
        "request invokes ability from context" = {
          expr = nfx.runFx (nfx.provide { double = x: nfx.pure (x * 2); } (nfx.request "double" 21));
          expected = 42;
        };
      };
    };
  };
}
