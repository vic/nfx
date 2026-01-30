{ nfx, api, ... }:
let
  inherit (api) mk;
  inherit (api.types) any;
in
mk {
  doc = ''
    Built-in state effect providing get/set/modify operations.

    The state effect is a fundamental capability that allows reading and
    writing to a mutable state. In NFX, state is managed through the
    context mechanism - the state IS the context.

    ## Namespace Contents

    - `get` - Reads the current state
    - `set` - Replaces the state with a new value
    - `modify` - Transforms state with a pure function
    - `modifyM` - Transforms state with an effectful function

    ## Example
    ```nix
    provide 10 (
      mapM (old:
        then' (state.get)
              (state.modify (x: x + 1))
      ) state.get
    )  # State goes 10 -> 11, returns 11
    ```

    ## See Also
    - `func` - Alternative for read-only state access
    - `context` - For named attribute-based state
  '';
  value = {
    get = nfx.pending (s: nfx.immediate s s);
    set = s: nfx.immediate s s;
    modify = f: nfx.mapM (s: nfx.state.set (f s)) nfx.state.get;
    modifyM =
      f:
      nfx.do [
        (_: nfx.state.get)
        (s: f s)
        (newState: nfx.state.set newState)
      ];
  };
  tests = {
    "state.get reads state" = {
      expr = nfx.runFx (nfx.provide 42 nfx.state.get);
      expected = 42;
    };
    "state.set replaces state" = {
      expr = (nfx.state.set 99).state;
      expected = 99;
    };
    "state.modify transforms state" = {
      expr = nfx.runFx (nfx.provide 10 (nfx.state.modify (x: x * 2)));
      expected = 20;
    };
  };
}
