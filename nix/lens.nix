{ nfx, api, ... }:
let
  inherit (api) mk;
  inherit (api.types) any;
in
mk {
  doc = ''
    Lens utilities for focusing on parts of larger contexts.

    Lenses are a powerful abstraction for accessing and updating nested
    data structures. A lens encapsulates a getter and setter pair,
    enabling effects to work with focused subparts of their context.

    ## Lens Structure
    A lens is an attrset with:
    - `get : A -> B` - extracts the focused part
    - `set : A -> B -> A` - updates the focused part

    ## Example
    ```nix
    let
      l = lens.fromAttr "x";
    in
      l.get { x = 42; y = 1; }  # => 42
      l.set { x = 1; y = 2; } 99  # => { x = 99; y = 2; }
    ```

    ## See Also
    - `contraMap` - Lower-level context transformation
    - `lift` - Simple attribute-based lifting
  '';
  value = {
    make = mk {
      doc = ''
        Creates a lens from getter and setter functions.

        A lens provides composable access to nested data structures.
        It consists of a getter (extracting a value) and setter
        (updating a value immutably).

        ## Type Signature
        `(S -> A) -> (S -> A -> S) -> Lens S A`

        ## Parameters
        - `get`: Function to extract value from structure
        - `set`: Function to update value in structure

        ## Example
        ```nix
        # Lens for first list element
        lens.make (list.head) (list: v: [v] ++ (list.tail list))
        ```

        ## See Also
        - `fromAttr` - Lens for attribute access
        - `compose` - Combine lenses
      '';
      value = get: set: { inherit get set; };
    };

    fromAttr = mk {
      doc = ''
        Creates a lens focusing on a named attribute.

        Provides getter/setter for accessing an attribute by name within
        an attribute set. The setter preserves all other attributes.

        ## Type Signature
        `String -> Lens {name: A, ...} A`

        ## Parameters
        - `name`: Name of attribute to focus on

        ## Example
        ```nix
        let xLens = lens.fromAttr "x";
        in xLens.get {x = 42; y = 1;}  # => 42

        xLens.set {x = 1; y = 2;} 99   # => {x = 99; y = 2;}
        ```

        ## See Also
        - `zoomOut` - Use lens with effects
        - `compose` - Nest attribute access
      '';
      value = name: {
        get = ctx: ctx.${name};
        set = ctx: v: ctx // { ${name} = v; };
      };
      tests = {
        "lens.fromAttr creates working lens" = {
          expr =
            let
              l = nfx.lens.fromAttr "x";
            in
            l.get {
              x = 42;
              y = 1;
            };
          expected = 42;
        };
        "lens.set updates via lens" = {
          expr =
            let
              l = nfx.lens.fromAttr "x";
            in
            l.set {
              x = 1;
              y = 2;
            } 99;
          expected = {
            x = 99;
            y = 2;
          };
        };
      };
    };

    left = mk {
      doc = ''
        Lens focusing on the `fst` component of a pair.

        Provides access to the first element of a pair structure,
        commonly used with paired contexts like state + accumulator.

        ## Type Signature
        `Lens {fst: A, snd: B} A`

        ## Example
        ```nix
        lens.left.get {fst = 42; snd = 1;}  # => 42

        lens.left.set {fst = 1; snd = 2;} 99
        # => {fst = 99; snd = 2;}
        ```

        ## See Also
        - `right` - Focus on second component
        - `pair.fst` - Direct accessor
      '';
      value = {
        get = p: p.fst;
        set = p: a: {
          fst = a;
          snd = p.snd;
        };
      };
      tests = {
        "lens.left focuses on fst" = {
          expr = nfx.lens.left.get {
            fst = 42;
            snd = 1;
          };
          expected = 42;
        };
      };
    };

    right = mk {
      doc = ''
        Lens focusing on the `snd` component of a pair.

        Provides access to the second element of a pair structure,
        commonly used with paired contexts like state + accumulator.

        ## Type Signature
        `Lens {fst: A, snd: B} B`

        ## Example
        ```nix
        lens.right.get {fst = 1; snd = 42;}  # => 42

        lens.right.set {fst = 1; snd = 2;} 99
        # => {fst = 1; snd = 99;}
        ```

        ## See Also
        - `left` - Focus on first component
        - `pair.snd` - Direct accessor
      '';
      value = {
        get = p: p.snd;
        set = p: b: {
          fst = p.fst;
          snd = b;
        };
      };
      tests = {
        "lens.right focuses on snd" = {
          expr = nfx.lens.right.get {
            fst = 1;
            snd = 42;
          };
          expected = 42;
        };
      };
    };

    compose = mk {
      doc = ''
        Chains two lenses for nested access.

        Composes two lenses to create a lens that focuses through both,
        enabling access to deeply nested structures in a composable way.

        ## Type Signature
        `Lens S A -> Lens A B -> Lens S B`

        ## Parameters
        - `outer`: Lens from S to A
        - `inner`: Lens from A to B

        ## Example
        ```nix
        # Focus on x.y in nested structure
        let xLens = lens.fromAttr "x";
            yLens = lens.fromAttr "y";
            xyLens = lens.compose xLens yLens;
        in xyLens.get {x = {y = 42;};}  # => 42
        ```

        ## See Also
        - `fromAttr` - Create attribute lenses
        - `zoomOut` - Use composed lenses with effects
      '';
      value = outer: inner: {
        get = a: inner.get (outer.get a);
        set = a: c: outer.set a (inner.set (outer.get a) c);
      };
      tests = {
        "lens.compose chains lenses" = {
          expr =
            let
              outer = nfx.lens.fromAttr "nested";
              inner = nfx.lens.fromAttr "value";
              composed = nfx.lens.compose outer inner;
            in
            composed.get {
              nested = {
                value = 42;
              };
            };
          expected = 42;
        };
      };
    };

    zoomOut = mk {
      doc = ''
        Adapts an effect to work with a larger context via a lens.

        Takes an effect requiring small context A and adapts it to work
        with larger context S, using a lens to focus on the A within S.
        The effect sees only its portion while outer context provides the rest.

        ## Type Signature
        `Lens S A -> Fx<A, V> -> Fx<S, V>`

        ## Parameters
        - `l`: Lens from S to A
        - `e`: Effect requiring context A

        ## Example
        ```nix
        # Effect needs just "num", but context has more
        zoomOut (fromAttr "num") (pending (n: immediate n (n * 2)))
        # Now works with {num = 10; other = ...;}
        ```

        ## See Also
        - `zoomIn` - For continuations
        - `contraMap` - General context transformation
      '';
      value = l: e: nfx.contraMap l.get l.set e;
      tests = {
        "lens.zoomOut focuses effect" = {
          expr = nfx.runFx (
            nfx.provide { num = 10; } (
              nfx.lens.zoomOut (nfx.lens.fromAttr "num") (nfx.pending (n: nfx.immediate n (n * 2)))
            )
          );
          expected = 20;
        };
      };
    };

    zoomIn = mk {
      doc = ''
        Like zoomOut but for continuations (reverse direction).

        Adapts a continuation that modifies small context A to work with
        larger context S via a lens. The continuation can update its
        portion while preserving the rest of S.

        ## Type Signature
        `Lens S A -> (A -> Fx<A, V>) -> Fx<S, V> -> Fx<S, V>`

        ## Parameters
        - `l`: Lens from S to A
        - `inner`: Continuation producing effect from A
        - `e`: Source effect

        ## Example
        ```nix
        let countLens = fromAttr "count";
        in zoomIn countLens (n: pure (n + 1)) (pure 0)
        # Increments count while preserving other fields
        ```

        ## See Also
        - `zoomOut` - For effects
        - `mapM` - Transform with effects
      '';
      value =
        l: inner: e:
        nfx.mapM (v: nfx.lens.zoomOut l (inner v)) e;
    };
  };
}
