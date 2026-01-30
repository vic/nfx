{ nfx, api, ... }:
let
  inherit (api) mk;
  inherit (api.types) any;
in
mk {
  doc = ''
    Pair utilities for composing context requirements.

    When effects have different requirements, pair combines them into
    a single context `{fst: A, snd: B}`. This module provides utilities
    for creating and manipulating these paired contexts.

    ## Pair Structure
    A pair is an attrset with `fst` and `snd` attributes.

    ## See Also
    - `flatMap` - Combines effects with different requirements
    - `andSwap`, `andNil` - Context transformations using pairs
  '';
  value = {
    make = mk {
      doc = ''
        Creates a pair from two values.

        Pairs are fundamental structures in NFX for managing paired contexts
        (like state and accumulator). This constructs a pair with given values
        as the first and second components.

        ## Type Signature
        `A -> B -> {fst: A, snd: B}`

        ## Parameters
        - `a`: Value for first component
        - `b`: Value for second component

        ## Example
        ```nix
        pair.make 1 2         # => {fst = 1; snd = 2;}
        pair.make "x" [1 2]   # => {fst = "x"; snd = [1 2];}
        ```

        ## See Also
        - `fst`, `snd` - Extract components
        - `swap` - Reverse components
      '';
      value = a: b: {
        fst = a;
        snd = b;
      };
      tests = {
        "pair.make creates pair" = {
          expr = nfx.pair.make 1 2;
          expected = {
            fst = 1;
            snd = 2;
          };
        };
      };
    };

    fst = mk {
      doc = ''
        Extracts the first component of a pair.

        ## Type Signature
        `{fst: A, snd: B} -> A`

        ## Parameters
        - `p`: A pair structure

        ## Example
        ```nix
        pair.fst {fst = 42; snd = 1;}  # => 42
        pair.fst (pair.make "x" "y")   # => "x"
        ```

        ## See Also
        - `snd` - Extract second component
        - `make` - Create pairs
      '';
      type = api.types.fn any;
      value = p: p.fst;
      tests = {
        "pair.fst extracts first" = {
          expr = nfx.pair.fst {
            fst = 42;
            snd = 1;
          };
          expected = 42;
        };
      };
    };

    snd = mk {
      doc = ''
        Extracts the second component of a pair.

        ## Type Signature
        `{fst: A, snd: B} -> B`

        ## Parameters
        - `p`: A pair structure

        ## Example
        ```nix
        pair.snd {fst = 1; snd = 42;}  # => 42
        pair.snd (pair.make "x" "y")   # => "y"
        ```

        ## See Also
        - `fst` - Extract first component
        - `make` - Create pairs
      '';
      type = api.types.fn any;
      value = p: p.snd;
    };

    swap = mk {
      doc = ''
        Swaps the components of a pair.

        Exchanges first and second components, useful when adapting
        between different context orderings or symmetrizing operations.

        ## Type Signature
        `{fst: A, snd: B} -> {fst: B, snd: A}`

        ## Parameters
        - `p`: A pair structure

        ## Example
        ```nix
        pair.swap {fst = 1; snd = 2;}  # => {fst = 2; snd = 1;}
        pair.swap (pair.make "a" "b")  # => {fst = "b"; snd = "a";}
        ```

        ## See Also
        - `bwd` - Alias for swap
        - `fwd` - Identity (no swap)
      '';
      type = api.types.fn any;
      value = p: {
        fst = p.snd;
        snd = p.fst;
      };
      tests = {
        "pair.swap swaps components" = {
          expr = nfx.pair.swap {
            fst = 1;
            snd = 2;
          };
          expected = {
            fst = 2;
            snd = 1;
          };
        };
      };
    };

    fwd = mk {
      doc = ''
        Identity function on pairs (forward direction).

        Returns the pair unchanged. Provided for symmetry with `bwd`
        and for explicit control flow in pair transformations.

        ## Type Signature
        `{fst: A, snd: B} -> {fst: A, snd: B}`

        ## Parameters
        - `p`: A pair structure

        ## Example
        ```nix
        pair.fwd {fst = 1; snd = 2;}  # => {fst = 1; snd = 2;}
        ```

        ## See Also
        - `bwd` - Swap (reverse direction)
        - `swap` - Same as bwd
      '';
      type = api.types.fn any;
      value = p: p;
      tests = {
        "pair.fwd is identity" = {
          expr = nfx.pair.fwd {
            fst = 1;
            snd = 2;
          };
          expected = {
            fst = 1;
            snd = 2;
          };
        };
      };
    };

    bwd = mk {
      doc = ''
        Swaps pair components (backward direction).

        Same as `swap` but named for directional symmetry with `fwd`.
        Useful in bidirectional transformations or when reversing
        context orderings.

        ## Type Signature
        `{fst: A, snd: B} -> {fst: B, snd: A}`

        ## Parameters
        - `p`: A pair structure

        ## Example
        ```nix
        pair.bwd {fst = 1; snd = 2;}  # => {fst = 2; snd = 1;}
        ```

        ## See Also
        - `swap` - Same operation
        - `fwd` - Identity (no swap)
      '';
      type = api.types.fn any;
      value = p: {
        fst = p.snd;
        snd = p.fst;
      };
      tests = {
        "pair.bwd swaps" = {
          expr = nfx.pair.bwd {
            fst = 1;
            snd = 2;
          };
          expected = {
            fst = 2;
            snd = 1;
          };
        };
      };
    };

    nest = mk {
      doc = ''
        Restructures nested pairs from right-associated to left-associated.

        Transforms `(A, (B, C))` to `((A, B), C)`, moving nesting from
        right to left. Useful for normalizing paired contexts or adapting
        between different effect compositions.

        ## Type Signature
        `{fst: A, snd: {fst: B, snd: C}} -> {fst: {fst: A, snd: B}, snd: C}`

        ## Parameters
        - `p`: Right-nested pair structure

        ## Example
        ```nix
        nest {fst = 1; snd = {fst = 2; snd = 3;}}
        # => {fst = {fst = 1; snd = 2;}; snd = 3;}
        ```

        ## See Also
        - `unnest` - Opposite transformation
      '';
      type = api.types.fn any;
      value = p: {
        fst = {
          fst = p.fst;
          snd = p.snd.fst;
        };
        snd = p.snd.snd;
      };
      tests = {
        "pair.nest restructures" = {
          expr = nfx.pair.nest {
            fst = 1;
            snd = {
              fst = 2;
              snd = 3;
            };
          };
          expected = {
            fst = {
              fst = 1;
              snd = 2;
            };
            snd = 3;
          };
        };
      };
    };

    unnest = mk {
      doc = ''
        Restructures nested pairs from left-associated to right-associated.

        Transforms `((A, B), C)` to `(A, (B, C))`, moving nesting from
        left to right. Inverse of `nest`, useful for adapting effect
        context structures.

        ## Type Signature
        `{fst: {fst: A, snd: B}, snd: C} -> {fst: A, snd: {fst: B, snd: C}}`

        ## Parameters
        - `p`: Left-nested pair structure

        ## Example
        ```nix
        unnest {fst = {fst = 1; snd = 2;}; snd = 3;}
        # => {fst = 1; snd = {fst = 2; snd = 3;}}
        ```

        ## See Also
        - `nest` - Opposite transformation
      '';
      type = api.types.fn any;
      value = p: {
        fst = p.fst.fst;
        snd = {
          fst = p.fst.snd;
          snd = p.snd;
        };
      };
    };
  };
}
