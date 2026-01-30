{ nfx, api, ... }:
let
  inherit (api) mk;
  inherit (api.types) fn fx any;
in
mk {
  doc = ''
    Accumulator pattern for threading accumulated values through effects.

    The accumulator pattern allows collecting results as effects execute,
    maintaining an accumulator value in the context that effects can read
    and update. Useful for gathering build artifacts, tracking dependencies,
    logging, or any scenario where you need to collect information across
    effect invocations.

    ## Pattern

    Effects using accumulator run in `{acc, state}` context where:
    - `acc` - The accumulator value being threaded through
    - `state` - The actual program state

    ## See Also
    - `state` - For stateful computations without accumulation
    - `mapM` - For chaining effects
  '';
  value = {
    option = mk {
      doc = ''
        Option accumulator that replaces with new value.

        Implements accumulation semantics where each new item completely
        replaces the current accumulator value. Useful for tracking
        "latest value" or implementing optional results.

        ## Type Signature
        `A -> A -> Fx<{}, A>`

        ## Parameters
        - `current`: Current accumulator (ignored)
        - `item`: New value to use

        ## Example
        ```nix
        runFx (acc.option null 42)     # => 42
        runFx (acc.option 1 2)         # => 2
        ```

        ## See Also
        - `list` - Append accumulation
        - `collect` - Thread accumulator through effects
      '';
      value = _current: item: nfx.pure item;
      tests = {
        "option replaces value" = {
          expr = nfx.runFx (nfx.acc.option null 42);
          expected = 42;
        };
      };
    };

    list = mk {
      doc = ''
        List accumulator that appends items.

        Implements accumulation by appending each new item to the end
        of the list. The standard accumulator for collecting multiple
        values during effect execution.

        ## Type Signature
        `[A] -> A -> Fx<{}, [A]>`

        ## Parameters
        - `current`: Current list
        - `item`: Item to append

        ## Example
        ```nix
        runFx (acc.list [] 1)          # => [1]
        runFx (acc.list [1 2] 3)       # => [1 2 3]
        ```

        ## See Also
        - `collect` - Thread list accumulator
        - `withAccumulator` - Extract only accumulator
      '';
      value = current: item: nfx.pure (current ++ [ item ]);
      tests = {
        "list appends items" = {
          expr = nfx.runFx (nfx.acc.list [ 1 2 ] 3);
          expected = [
            1
            2
            3
          ];
        };
        "list starts empty" = {
          expr = nfx.runFx (nfx.acc.list [ ] 1);
          expected = [ 1 ];
        };
      };
    };

    set = mk {
      doc = ''
        Attribute set accumulator that merges attributes.

        Implements accumulation by merging new attributes into the current
        set. Later values override earlier ones on key conflicts, following
        Nix's standard merge semantics.

        ## Type Signature
        `{...A} -> {...B} -> Fx<{}, {...A, ...B}>`

        ## Parameters
        - `current`: Current attribute set
        - `item`: Attributes to merge

        ## Example
        ```nix
        runFx (acc.set {a = 1;} {b = 2;})    # => {a = 1; b = 2;}
        runFx (acc.set {a = 1;} {a = 2;})    # => {a = 2;}
        ```

        ## See Also
        - `list` - List accumulation
        - `collectWith` - Use custom accumulator
      '';
      value = current: item: nfx.pure (current // item);
      tests = {
        "set merges attrsets" = {
          expr = nfx.runFx (nfx.acc.set { a = 1; } { b = 2; });
          expected = {
            a = 1;
            b = 2;
          };
        };
        "set overrides on conflict" = {
          expr = nfx.runFx (
            nfx.acc.set {
              a = 1;
              b = 2;
            } { b = 3; }
          );
          expected = {
            a = 1;
            b = 3;
          };
        };
      };
    };

    collect = mk {
      doc = ''
        Threads accumulator through effect execution.

        Executes an effect while maintaining an accumulator in the context.
        The effect can call `accumulate` to add items. Returns both the
        final accumulator and the effect's value.

        ## Type Signature
        `A -> Fx<{acc: A}, V> -> Fx<{}, {acc: A, value: V}>`

        ## Parameters
        - `initial`: Initial accumulator value
        - `e`: Effect to execute

        ## Example
        ```nix
        runFx (collect [] (
          mapM (x: accumulate x) (pure [1 2 3])
        ))  # => {acc = [1 2 3]; value = [1 2 3];}
        ```

        ## See Also
        - `collectWith` - Use custom accumulator function
        - `withAccumulator` - Extract only accumulator
      '';
      value =
        initial: e:
        nfx.mapM
          (
            v:
            nfx.map (ctx: {
              acc = ctx.acc;
              value = v;
            }) nfx.state.get
          )
          (
            nfx.contraMap (s: {
              acc = initial;
              state = s;
            }) (_: ctx: ctx) e
          );
      tests = {
        "collect threads accumulator through state" = {
          expr = nfx.runFx (
            nfx.provide 10 (
              nfx.acc.collect [ ] (
                nfx.pending (
                  ctx:
                  nfx.immediate {
                    acc = ctx.acc ++ [ ctx.state ];
                    state = ctx.state;
                  } ctx.state
                )
              )
            )
          );
          expected = {
            acc = [ 10 ];
            value = 10;
          };
        };
      };
    };

    collectWith = mk {
      doc = ''
        Collects with a custom accumulation function.

        Like `collect` but allows specifying a custom accumulator function
        instead of using the default list append. Useful for custom
        accumulation strategies (sum, product, merge, etc.).

        ## Type Signature
        `A -> (A -> B -> Fx<S, A>) -> Fx<{acc: A} & S, V> -> Fx<S, {acc: A, value: V}>`

        ## Parameters
        - `initial`: Initial accumulator value
        - `accFn`: Function to accumulate items
        - `e`: Effect to execute

        ## Example
        ```nix
        # Sum accumulator
        collectWith 0 (acc: x: pure (acc + x)) ...

        # Custom merge accumulator  
        collectWith {} (acc: x: pure (acc // x)) ...
        ```

        ## See Also
        - `collect` - Standard list collection
        - `option`, `list`, `set` - Built-in accumulators
      '';
      value =
        initial: accFn: e:
        nfx.mapM
          (
            v:
            nfx.map (ctx: {
              acc = ctx.acc;
              value = v;
            }) nfx.state.get
          )
          (
            nfx.contraMap (s: {
              acc = initial;
              state = s;
            }) (_: ctx: ctx) e
          );
      tests = {
        "collectWith uses custom accumulator" = {
          expr = nfx.runFx (nfx.provide 5 (nfx.acc.collectWith [ ] nfx.acc.list (nfx.func (ctx: ctx.state))));
          expected = {
            acc = [ ];
            value = 5;
          };
        };
      };
    };

    accumulate = mk {
      doc = ''
        Adds an item to the accumulator in context.

        Uses the provided accumulator function to add an item to the
        current accumulator value. Must be used within `collectWith`.

        ## Type Signature
        `(A -> B -> Fx<S, A>) -> B -> Fx<{acc: A, state: S}, {}>`

        ## Parameters
        - `accFn`: Accumulator function
        - `item`: Item to add to accumulator

        ## Example
        ```nix
        runFx (collectWith [] acc.list (
          flatMap (x: accumulate acc.list x *> pure x) (pure 42)
        ))  # => {acc = [42]; value = 42;}
        ```

        ## See Also
        - `collectWith` - Set up custom accumulation
        - `collect` - Standard list accumulation
      '';
      value =
        accFn: item:
        nfx.pending (
          ctx:
          let
            current = ctx.acc;
            updated = nfx.runFx (nfx.provide ctx.state (accFn current item));
          in
          nfx.immediate {
            acc = updated;
            state = ctx.state;
          } { }
        );
      tests = {
        "accumulate updates accumulator in context" = {
          expr = nfx.runFx (
            nfx.provide 10 (
              nfx.acc.collect [ ] (nfx.mapM (_: nfx.value 42) (nfx.acc.accumulate nfx.acc.list 99))
            )
          );
          expected = {
            acc = [ 99 ];
            value = 42;
          };
        };
      };
    };

    withAccumulator = mk {
      doc = ''
        Runs effect and returns only the accumulator value.

        Like `collect` but discards the effect's result value, returning
        only the final accumulator. Useful when the accumulation itself
        is the desired output.

        ## Type Signature
        `A -> Fx<{acc: A}, V> -> Fx<{}, A>`

        ## Parameters
        - `initial`: Initial accumulator value
        - `e`: Effect to execute

        ## Example
        ```nix
        runFx (withAccumulator [] (
          pending (ctx: immediate {...} 42)
        ))  # => [items...] (discards 42)
        ```

        ## See Also
        - `collect` - Returns both accumulator and value
        - `collectWith` - With custom accumulator
      '';
      value = initial: e: nfx.map (result: result.acc) (nfx.acc.collect initial e);
      tests = {
        "withAccumulator returns only accumulator" = {
          expr = nfx.runFx (
            nfx.provide 10 (
              nfx.acc.withAccumulator [ ] (
                nfx.pending (
                  ctx:
                  nfx.immediate {
                    acc = ctx.acc ++ [ 99 ];
                    state = ctx.state;
                  } 42
                )
              )
            )
          );
          expected = [ 99 ];
        };
      };
    };
  };
}
