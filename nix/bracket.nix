{ nfx, api, ... }:
let
  inherit (api) mk;
  inherit (api.types) fn any fx;
in
mk {
  doc = ''
    Resource management with acquire/release patterns.

    Ensures cleanup code runs even when errors occur. Essential for
    managing resources like file handles, connections, or locks that
    must be properly released.

    Built on the condition system for error handling.

    ## Core Pattern

    ```nix
    bracket
      acquire    # Fx<S, Resource>
      release    # Resource -> Fx<S, {}>
      use        # Resource -> Fx<S, Value>
    ```

    The release function ALWAYS runs, even on error.

    ## Example
    ```nix
    # Acquire file handle, ensure it closes
    withFile = path: action:
      bracket
        (openFile path)           # acquire
        (handle: closeFile handle) # release (always runs)
        action;                    # use

    result = runFx (withFile "data.txt" (handle:
      readContents handle
    ));
    ```

    ## Namespace Contents

    - `bracket` - Acquire/release/use pattern
    - `bracket_` - Ignore result, return use value
    - `finally` - Ensure action runs after effect
    - `onError` - Run action only on error
    - `onSuccess` - Run action only on success
    - `bracketOnError` - Release only on error
  '';
  value = {
    bracket = mk {
      doc = ''
        General acquire/release/use pattern.

        Acquires a resource, runs a computation with it, and ensures
        the resource is released regardless of success or failure.
        Returns both the computation result and release result.

        ## Type Signature
        `Fx<S, R> -> (R -> Fx<S, C>) -> (R -> Fx<S, V>) -> Fx<S, {value: V, cleanup: C}>`

        ## Parameters
        - `acquire`: Effect that acquires resource
        - `release`: Function to release resource (always runs)
        - `use`: Function to use resource

        ## Example
        ```nix
        bracket
          (openConnection "db.sqlite")
          (conn: closeConnection conn)
          (conn: query conn "SELECT * FROM users")
        # => { value = queryResult; cleanup = {}; }
        ```

        ## See Also
        - `bracket_` - Simpler version that discards cleanup result
        - `finally` - Ensure action runs
        - `bracketOnError` - Release only on error
      '';
      type = fn (fn (fn fx));
      value = acquire: release: use:
        nfx.do [
          (_: acquire)
          (resource:
            nfx.handle "error"
              (cond:
                # On error: release then re-signal
                nfx.do [
                  (_: release resource)
                  (_: nfx.signal cond)
                ]
              )
              (
                # On success: use then release
                nfx.do [
                  (_: use resource)
                  (value: nfx.map (cleanup: { inherit value cleanup; }) (release resource))
                ]
              )
          )
        ];
      tests = {
        "bracket releases on success" = {
          expr = nfx.runFx (
            nfx.provide { released = false; } (
              nfx.do [
                (_:
                  nfx.bracket
                    (nfx.pure "resource")
                    (_: nfx.state.modify (s: s // { released = true; }))
                    (r: nfx.pure (r + "-used"))
                )
                (result: nfx.map (s: { inherit result; released = s.released; }) nfx.state.get)
              ]
            )
          );
          expected = {
            result = { value = "resource-used"; cleanup = { released = true; }; };
            released = true;
          };
        };
        "bracket releases on error" = {
          expr = nfx.runFx (
            nfx.provide { released = false; } (
              nfx.catch' (
                nfx.then' (nfx.state.get)
                  (nfx.bracket
                    (nfx.pure "resource")
                    (_: nfx.state.modify (s: s // { released = true; }))
                    (_: nfx.error "failure" {})
                  )
              )
            )
          );
          expected = {
            success = false;
            error = { type = "error"; kind = "failure"; data = {}; };
          };
        };
      };
    };

    bracket_ = mk {
      doc = ''
        Simplified bracket that discards release result.

        Like `bracket` but only returns the use result, discarding
        the cleanup value. Most common case for resource management.

        ## Type Signature
        `Fx<S, R> -> (R -> Fx<S, {}>) -> (R -> Fx<S, V>) -> Fx<S, V>`

        ## Parameters
        - `acquire`: Effect that acquires resource
        - `release`: Function to release resource
        - `use`: Function to use resource

        ## Example
        ```nix
        withFile = path: action:
          bracket_
            (openFile path)
            (h: closeFile h)
            action;

        content = runFx (withFile "data.txt" readAll);
        ```

        ## See Also
        - `bracket` - Full version with cleanup result
        - `finally` - Simpler cleanup without resource
      '';
      type = fn (fn (fn fx));
      value = acquire: release: use:
        nfx.mapM (result: nfx.pure result.value)
          (nfx.bracket acquire release use);
      tests = {
        "bracket_ returns use value" = {
          expr = nfx.runFx (
            nfx.bracket_
              (nfx.pure "resource")
              (_: nfx.pure {})
              (r: nfx.pure (r + "-used"))
          );
          expected = "resource-used";
        };
      };
    };

    finally = mk {
      doc = ''
        Ensures an action runs after an effect, even on error.

        Simpler than bracket when you don't need to acquire/pass a resource.
        The cleanup action runs regardless of success or failure.

        ## Type Signature
        `Fx<S, V> -> Fx<S, {}> -> Fx<S, V>`

        ## Parameters
        - `effect`: Main computation
        - `cleanup`: Action to run afterwards (always)

        ## Example
        ```nix
        finally
          (riskyComputation)
          (logMetrics)
        # logMetrics runs whether riskyComputation succeeds or fails
        ```

        ## See Also
        - `bracket` - When you need acquire/release
        - `onError` - Run only on failure
        - `onSuccess` - Run only on success
      '';
      type = fn (fn fx);
      value = effect: cleanup:
        nfx.bracket_
          (nfx.pure {})
          (_: cleanup)
          (_: effect);
      tests = {
        "finally runs on success" = {
          expr = nfx.runFx (
            nfx.provide { ran = false; } (
              nfx.then' nfx.state.get
                (nfx.finally
                  (nfx.pure 42)
                  (nfx.state.modify (s: s // { ran = true; }))
                )
            )
          );
          expected = { ran = true; };
        };
        "finally runs on error" = {
          expr = nfx.runFx (
            nfx.provide { ran = false; } (
              nfx.catch' (
                nfx.then' nfx.state.get
                  (nfx.finally
                    (nfx.error "test" {})
                    (nfx.state.modify (s: s // { ran = true; }))
                  )
              )
            )
          );
          expected = {
            success = false;
            error = { type = "error"; kind = "test"; data = {}; };
          };
        };
      };
    };

    onError = mk {
      doc = ''
        Runs an action only if the effect fails.

        Error-specific cleanup or logging. The action runs before
        the error propagates. Original error is preserved.

        ## Type Signature
        `Fx<S, V> -> Fx<S, {}> -> Fx<S, V>`

        ## Parameters
        - `effect`: Computation that might fail
        - `cleanup`: Action to run on error only

        ## Example
        ```nix
        onError
          (riskyOperation)
          (rollbackTransaction)
        # rollbackTransaction only runs if riskyOperation fails
        ```

        ## See Also
        - `onSuccess` - Opposite pattern
        - `finally` - Run on both success and failure
        - `bracketOnError` - Release resource only on error
      '';
      type = fn (fn fx);
      value = effect: cleanup:
        nfx.handle "error"
          (cond:
            nfx.then' (nfx.signal cond) cleanup
          )
          effect;
      tests = {
        "onError runs on failure" = {
          expr = nfx.runFx (
            nfx.provide { cleaned = false; } (
              nfx.catch' (
                nfx.then' nfx.state.get
                  (nfx.onError
                    (nfx.error "test" {})
                    (nfx.state.modify (s: s // { cleaned = true; }))
                  )
              )
            )
          );
          expected = {
            success = false;
            error = { type = "error"; kind = "test"; data = {}; };
          };
        };
        "onError skips on success" = {
          expr = nfx.runFx (
            nfx.provide { cleaned = false; } (
              nfx.then' (nfx.onError (nfx.pure 42) (nfx.state.modify (s: s // { cleaned = true; })))
                nfx.state.get
            )
          );
          expected = { cleaned = false; };
        };
      };
    };

    onSuccess = mk {
      doc = ''
        Runs an action only if the effect succeeds.

        Success-specific actions like committing transactions or
        sending notifications. The action runs after success,
        before returning the value.

        ## Type Signature
        `Fx<S, V> -> Fx<S, {}> -> Fx<S, V>`

        ## Parameters
        - `effect`: Computation that might succeed
        - `action`: Action to run on success only

        ## Example
        ```nix
        onSuccess
          (transaction)
          (commitToDatabase)
        # commitToDatabase only runs if transaction succeeds
        ```

        ## See Also
        - `onError` - Opposite pattern
        - `finally` - Run on both success and failure
      '';
      type = fn (fn fx);
      value = effect: action:
        nfx.do [
          (_: effect)
          (value: nfx.then' (nfx.pure value) action)
        ];
      tests = {
        "onSuccess runs on success" = {
          expr = nfx.runFx (
            nfx.provide { committed = false; } (
              nfx.then' (nfx.onSuccess (nfx.pure 42) (nfx.state.modify (s: s // { committed = true; })))
                nfx.state.get
            )
          );
          expected = { committed = true; };
        };
        "onSuccess skips on failure" = {
          expr = nfx.runFx (
            nfx.provide { committed = false; } (
              nfx.catch' (
                nfx.then' nfx.state.get
                  (nfx.onSuccess
                    (nfx.error "test" {})
                    (nfx.state.modify (s: s // { committed = true; }))
                  )
              )
            )
          );
          expected = {
            success = false;
            error = { type = "error"; kind = "test"; data = {}; };
          };
        };
      };
    };

    bracketOnError = mk {
      doc = ''
        Acquire/release pattern that only releases on error.

        Like `bracket` but cleanup only happens if use fails.
        On success, the resource is left acquired (caller's responsibility).

        ## Type Signature
        `Fx<S, R> -> (R -> Fx<S, {}>) -> (R -> Fx<S, V>) -> Fx<S, V>`

        ## Parameters
        - `acquire`: Effect that acquires resource
        - `release`: Function to release on error only
        - `use`: Function to use resource

        ## Example
        ```nix
        bracketOnError
          (beginTransaction)
          (_: rollback)
          (tx: 
            do [
              (_: insertUser tx user)
              (_: insertPosts tx posts)
              (_: commit tx)  # Success: we committed
            ])
        # rollback only runs if insertUser/insertPosts fail
        ```

        ## See Also
        - `bracket` - Always releases
        - `onError` - Simpler error-only action
      '';
      type = fn (fn (fn fx));
      value = acquire: release: use:
        nfx.do [
          (_: acquire)
          (resource: nfx.onError (use resource) (release resource))
        ];
      tests = {
        "bracketOnError releases on error" = {
          expr = nfx.runFx (
            nfx.provide { released = false; } (
              nfx.catch' (
                nfx.then' nfx.state.get
                  (nfx.bracketOnError
                    (nfx.pure "resource")
                    (_: nfx.state.modify (s: s // { released = true; }))
                    (_: nfx.error "failure" {})
                  )
              )
            )
          );
          expected = {
            success = false;
            error = { type = "error"; kind = "failure"; data = {}; };
          };
        };
        "bracketOnError keeps resource on success" = {
          expr = nfx.runFx (
            nfx.provide { released = false; } (
              nfx.then' (
                nfx.bracketOnError
                  (nfx.pure "resource")
                  (_: nfx.state.modify (s: s // { released = true; }))
                  (r: nfx.pure (r + "-used"))
              ) nfx.state.get
            )
          );
          expected = { released = false; };
        };
      };
    };
  };
}
