{ nfx, api, ... }:
let
  inherit (api) mk;
  inherit (api.types) fn any fx;
in
mk {
  doc = ''
    Logic programming and non-deterministic choice combinators.

    Built on streams (interleave/done/flatMap), this module provides
    miniKanren-style combinators for logic programming, backtracking,
    and exploring multiple solution paths fairly.

    ## Core Concepts
    
    - **mzero**: Empty/failure (no solutions) = stream.done
    - **mplus**: Fair choice/OR = stream.interleave  
    - **mprod**: Conjunction/AND = stream.flatMap
    
    Choice effects return streams of solutions. Use `observe` to extract
    the first solution, or `observeAll` to collect all solutions.

    ## Example
    ```nix
    # Try multiple options, first success wins
    runFx (observe (
      orElse
        (if false then pure 1 else mzero)
        (pure 2)
    ))  # => 2

    # Generate multiple solutions
    runFx (observeAll (
      choice [
        (pure 1)
        (pure 2)
        (pure 3)
      ]
    ))  # => [1 2 3]

    # Conditional choice with guard
    numberBetween = n:
      flatMap (x:
        mapM (_: guard (x >= 1 && x <= n)) (pure x)
      ) (choice (map pure (range 1 10)));
    ```

    ## Namespace Contents
    
    - `mzero` - Failure/no solutions
    - `mplus` - Fair binary choice (try both)
    - `orElse` - Try first, fallback to second on failure
    - `choice` - First successful from list
    - `guard` - Conditional continuation
    - `observe` - Extract first solution
    - `observeAll` - Collect all solutions
    - `ifte` - If-then-else for logic
    - `once` - At most one solution
  '';
  value = {
    mzero = mk {
      doc = ''
        Empty choice / failure - yields no solutions.

        Represents a computation that fails or has no valid results.
        Identity element for mplus (choice).

        ## Type Signature
        `Stream<{}, V>` (for any V)

        ## Example
        ```nix
        runFx (observe mzero)  # => null (no solution)
        runFx (observe (mplus mzero (pure 42)))  # => 42
        ```

        ## See Also
        - `mplus` - Combine alternatives
        - `guard` - Conditional failure
      '';
      type = fx;
      value = nfx.stream.done;
      tests = {
        "mzero produces no solutions" = {
          expr = nfx.runFx (nfx.stream.toList nfx.mzero);
          expected = [];
        };
      };
    };

    mplus = mk {
      doc = ''
        Fair binary choice - combines two alternatives.

        miniKanren-style mplus that fairly interleaves solutions
        from both branches. Essential for complete search over
        infinite solution spaces.

        ## Type Signature
        `Stream<S, V> -> Stream<S, V> -> Stream<S, V>`

        ## Parameters
        - `s1`: First alternative
        - `s2`: Second alternative

        ## Example
        ```nix
        runFx (observeAll (
          mplus
            (pure 1)
            (pure 2)
        ))  # => [1 2]
        ```

        ## See Also
        - `orElse` - For non-stream effects
        - `choice` - N-ary choice
        - Logic programming: fair disjunction (OR)
      '';
      type = fn (fn fx);
      value = nfx.stream.interleave;
      tests = {
        "mplus interleaves fairly" = {
          expr = nfx.runFx (
            nfx.stream.toList (
              nfx.mplus
                (nfx.stream.fromList [ 1 2 ])
                (nfx.stream.fromList [ 10 20 ])
            )
          );
          expected = [ 1 10 2 20 ];
        };
      };
    };

    orElse = mk {
      doc = ''
        Try first effect, fallback to second on failure.

        Attempts the first computation. If it produces no solutions
        (empty stream), tries the second. More efficient than mplus
        when you only need the first success.

        ## Type Signature
        `Fx<S, Stream<S, V>> -> Fx<S, Stream<S, V>> -> Fx<S, Stream<S, V>>`

        ## Parameters
        - `e1`: Primary effect
        - `e2`: Fallback effect

        ## Example
        ```nix
        divide = x: y:
          orElse
            (if y != 0 then pure (x / y) else mzero)
            (pure 0);  # fallback value
        ```

        ## See Also
        - `mplus` - Fair interleaving
        - `choice` - Multiple alternatives
      '';
      type = fn (fn fx);
      value = e1: e2:
        nfx.mapM (s1:
          nfx.mapM (step:
            if step.more
            then nfx.stream.interleave s1 e2
            else e2
          ) s1
        ) e1;
      tests = {
        "orElse tries second on empty first" = {
          expr = nfx.runFx (
            nfx.observe (
              nfx.orElse nfx.mzero (nfx.pure 42)
            )
          );
          expected = 42;
        };
        "orElse uses first when non-empty" = {
          expr = nfx.runFx (
            nfx.observe (
              nfx.orElse (nfx.pure 1) (nfx.pure 2)
            )
          );
          expected = 1;
        };
      };
    };

    choice = mk {
      doc = ''
        N-ary choice - select from list of alternatives.

        Tries each alternative in order (fairly interleaved).
        Returns stream of all solutions from all branches.
        Empty list produces mzero.

        ## Type Signature
        `[Fx<S, Stream<S, V>>] -> Fx<S, Stream<S, V>>`

        ## Parameters
        - `alternatives`: List of effects to try

        ## Example
        ```nix
        runFx (observeAll (
          choice [
            (pure 1)
            (pure 2)
            (pure 3)
          ]
        ))  # => [1 2 3]

        # Empty choice = failure
        runFx (observe (choice []))  # => null
        ```

        ## See Also
        - `orElse` - Binary choice
        - `mplus` - Fair binary combination
      '';
      type = fn fx;
      value = alternatives:
        builtins.foldl' 
          (acc: e: nfx.mplus acc e)
          nfx.mzero
          alternatives;
      tests = {
        "choice combines alternatives" = {
          expr = nfx.runFx (
            nfx.stream.toList (
              nfx.choice [
                (nfx.pure 1)
                (nfx.pure 2)
                (nfx.pure 3)
              ]
            )
          );
          expected = [ 1 2 3 ];
        };
        "choice of empty list is mzero" = {
          expr = nfx.runFx (
            nfx.stream.toList (nfx.choice [])
          );
          expected = [];
        };
      };
    };

    guard = mk {
      doc = ''
        Conditional continuation - succeed if condition holds.

        If the predicate is true, continue with computation.
        Otherwise, fail (produce mzero). Common in logic programming
        for pruning invalid solution paths.

        ## Type Signature
        `Bool -> Fx<{}, Stream<{}, {}>>`

        ## Parameters
        - `cond`: Boolean condition

        ## Example
        ```nix
        # Filter solutions
        validNumbers = flatMap (n:
          mapM (_: pure n) (guard (n > 0 && n < 10))
        ) allNumbers;
        ```

        ## See Also
        - `mzero` - Unconditional failure
        - Logic programming: constraint satisfaction
      '';
      type = fn fx;
      value = cond:
        if cond 
        then nfx.pure {}
        else nfx.mzero;
      tests = {
        "guard succeeds when true" = {
          expr = nfx.runFx (
            nfx.observe (
              nfx.mapM (_: nfx.pure 42) (nfx.guard true)
            )
          );
          expected = 42;
        };
        "guard fails when false" = {
          expr = nfx.runFx (
            nfx.stream.toList (
              nfx.mapM (_: nfx.pure 42) (nfx.guard false)
            )
          );
          expected = [];
        };
      };
    };

    observe = mk {
      doc = ''
        Extract the first solution from a choice computation.

        Runs the effect and returns the first value from the result
        stream, or null if no solutions exist. Use this to "commit"
        to the first successful branch.

        ## Type Signature
        `Fx<S, Stream<S, V>> -> Fx<S, V | null>`

        ## Parameters
        - `e`: Choice effect

        ## Example
        ```nix
        runFx (observe (
          choice [
            mzero
            (pure 42)
            (pure 99)
          ]
        ))  # => 42 (first success)
        ```

        ## See Also
        - `observeAll` - Collect all solutions
        - `once` - At most one solution
      '';
      type = fn fx;
      value = e:
        nfx.mapM (step:
          if step.more
          then nfx.pure step.value
          else nfx.pure null
        ) e;
      tests = {
        "observe extracts first solution" = {
          expr = nfx.runFx (
            nfx.observe (
              nfx.stream.fromList [ 1 2 3 ]
            )
          );
          expected = 1;
        };
        "observe returns null on empty" = {
          expr = nfx.runFx (
            nfx.observe nfx.mzero
          );
          expected = null;
        };
      };
    };

    observeAll = mk {
      doc = ''
        Collect all solutions from a choice computation.

        Runs the effect and collects all values from the result stream
        into a list. Use this to explore the complete solution space.

        ## Type Signature
        `Fx<S, Stream<S, V>> -> Fx<S, [V]>`

        ## Parameters
        - `e`: Choice effect

        ## Example
        ```nix
        runFx (observeAll (
          choice [
            (pure 1)
            (pure 2)
            (pure 3)
          ]
        ))  # => [1 2 3]
        ```

        ## See Also
        - `observe` - Just first solution
        - Logic programming: solution enumeration
      '';
      type = fn fx;
      value = e:
        nfx.stream.toList e;
      tests = {
        "observeAll collects solutions" = {
          expr = nfx.runFx (
            nfx.observeAll (
              nfx.stream.fromList [ 1 2 3 ]
            )
          );
          expected = [ 1 2 3 ];
        };
        "observeAll returns empty on mzero" = {
          expr = nfx.runFx (
            nfx.observeAll nfx.mzero
          );
          expected = [];
        };
      };
    };

    ifte = mk {
      doc = ''
        If-then-else for logic programming.

        Tests a condition effect. If it produces at least one solution,
        runs the 'then' branch with that solution. Otherwise runs the
        'else' branch.

        ## Type Signature
        `Fx<S, Stream<S, V>> -> (V -> Fx<S, Stream<S, U>>) -> Fx<S, Stream<S, U>> -> Fx<S, Stream<S, U>>`

        ## Parameters
        - `cond`: Condition to test
        - `thenBranch`: Function applied to first solution if condition succeeds
        - `elseBranch`: Executed if condition produces no solutions

        ## Example
        ```nix
        ifte
          (guard (x > 0))
          (_: pure "positive")
          (pure "non-positive")
        ```

        ## See Also
        - `orElse` - Simpler fallback pattern
        - `once` - Take first solution
      '';
      type = fn (fn (fn fx));
      value = cond: thenBranch: elseBranch:
        nfx.mapM (step:
          if step.more
          then thenBranch step.value
          else elseBranch
        ) cond;
      tests = {
        "ifte executes then on success" = {
          expr = nfx.runFx (
            nfx.observe (
              nfx.ifte
                (nfx.pure 42)
                (v: nfx.pure (v * 2))
                (nfx.pure 0)
            )
          );
          expected = 84;
        };
        "ifte executes else on failure" = {
          expr = nfx.runFx (
            nfx.observe (
              nfx.ifte
                nfx.mzero
                (v: nfx.pure v)
                (nfx.pure 99)
            )
          );
          expected = 99;
        };
      };
    };

    once = mk {
      doc = ''
        At most one solution - commits to first success.

        Runs the effect but takes only the first solution if any exists.
        Useful for pruning the search space when you don't need all
        alternatives.

        ## Type Signature
        `Fx<S, Stream<S, V>> -> Fx<S, Stream<S, V>>`

        ## Parameters
        - `e`: Effect to limit

        ## Example
        ```nix
        runFx (observeAll (
          once (
            choice [
              (pure 1)
              (pure 2)
              (pure 3)
            ]
          )
        ))  # => [1]  (only first)
        ```

        ## See Also
        - `observe` - Extract first (doesn't return stream)
        - `ifte` - Conditional based on first solution
      '';
      type = fn fx;
      value = e:
        nfx.mapM (step:
          if step.more
          then nfx.stream.more step.value nfx.mzero
          else nfx.mzero
        ) e;
      tests = {
        "once takes first solution" = {
          expr = nfx.runFx (
            nfx.stream.toList (
              nfx.once (
                nfx.stream.fromList [ 1 2 3 ]
              )
            )
          );
          expected = [ 1 ];
        };
        "once on empty is empty" = {
          expr = nfx.runFx (
            nfx.stream.toList (
              nfx.once nfx.mzero
            )
          );
          expected = [];
        };
      };
    };
  };
}
