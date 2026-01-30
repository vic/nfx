{ nfx, api, ... }:
let
  inherit (api) mk;
  inherit (api.types) fn any fx;
in
mk {
  doc = "Context manipulation utilities for attribute-based state";
  value = {
    has = mk {
      doc = ''
        Extracts a named attribute from a context.

        A utility function for working with attrset-based contexts.
        In Nix, any attrset naturally "has" its attributes, so this is
        simply attribute access.

        ## Type Signature
        `AttrSet -> String -> Value`

        ## Parameters
        - `ctx`: An attrset context
        - `name`: Name of the attribute to extract

        ## Example
        ```nix
        has { x = 42; y = 1; } "x"  # => 42
        ```

        ## See Also
        - `put` - Updates an attribute in context
        - `lift` - Uses has/put implicitly for effect lifting
      '';
      type = fn (fn any);
      value = ctx: name: ctx.${name};
      tests = {
        "has extracts attribute" = {
          expr = nfx.has {
            x = 42;
            y = 1;
          } "x";
          expected = 42;
        };
      };
    };

    put = mk {
      doc = ''
        Updates a named attribute in a context.

        Returns a new attrset with the specified attribute updated.
        If the attribute doesn't exist, it is added.

        ## Type Signature
        `AttrSet -> String -> Value -> AttrSet`

        ## Parameters
        - `ctx`: The original context attrset
        - `name`: Name of the attribute to update
        - `value`: New value for the attribute

        ## Example
        ```nix
        put { x = 1; } "x" 42    # => { x = 42; }
        put { x = 1; } "y" 2     # => { x = 1; y = 2; }
        ```

        ## See Also
        - `has` - Reads an attribute from context
        - `state.set` - Sets the entire state, not just an attribute
      '';
      type = fn (fn (fn any));
      value = ctx: name: value:
        ctx // { ${name} = value; };
      tests = {
        "put updates attribute" = {
          expr = nfx.put { x = 1; } "x" 42;
          expected = {
            x = 42;
          };
        };
        "put adds attribute" = {
          expr = nfx.put { x = 1; } "y" 2;
          expected = {
            x = 1;
            y = 2;
          };
        };
      };
    };

    lift = mk {
      doc = ''
        Lifts an effect to work with larger contexts.

        An effect requiring type `A` can run in any context that has an
        attribute containing `A`. This is the standard way to compose effects
        that work on different parts of a shared context.

        ## Type Signature
        `String -> Fx<A, V> -> Fx<Ctx, V>`

        where `Ctx` is an attrset containing attribute `name: A`

        ## Parameters
        - `name`: The attribute name in the larger context
        - `e`: Effect requiring the inner type

        ## Example
        ```nix
        runFx (
          provide { num = 10; other = "x"; } (
            lift "num"
              (pending (n: immediate n (n * 3)))
          )
        )  # => 30
        ```

        ## How It Works
        Uses `contraMap` to:
        1. Extract the named attribute for the inner effect
        2. Update the named attribute with any state changes

        ## See Also
        - `contraMap` - Lower-level context transformation
        - `lens.zoomOut` - Lens-based version
      '';
      type = fn (fn fx);
      value = name: e: nfx.contraMap (ctx: ctx.${name}) (ctx: inner: ctx // { ${name} = inner; }) e;
      tests = {
        "lift extracts nested requirement" = {
          expr = nfx.runFx (
            nfx.provide {
              num = 10;
              other = "x";
            } (nfx.lift "num" (nfx.pending (n: nfx.immediate n (n * 3))))
          );
          expected = 30;
        };
      };
    };
  };
}
