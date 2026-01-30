{ nfx, api, ... }:
let
  inherit (api) mk;
  inherit (api.types) fn any fx;
in
mk {
  doc = ''
    Common Lisp style condition system for resumable error handling.

    The condition system provides signaling, handling, and restart mechanisms
    that go beyond simple exceptions. Key features:

    - **Conditions** - Signals that can be handled without unwinding
    - **Handlers** - Dynamic scoped responders to conditions
    - **Restarts** - Named recovery strategies available at signal site
    - **Resumption** - Continue execution after handling (not just unwind)

    ## Condition System Flow

    1. Code signals a condition with available restarts
    2. Handler examines condition and chooses a restart
    3. Restart continues execution from signal point (or unwinds)

    ## Example
    ```nix
    # Define function with restarts
    parseConfig = file:
      withRestart "use-default" (dflt: pure dflt)
        (withRestart "retry" (_: parseConfig file)
          (map (_: throw "Parse failed")
            (signal { type = "parse-error"; file = file; })));

    # Handle with restart selection
    parsed = runFx (
      handle "parse-error" (cond:
        if canRecover cond.file
        then invokeRestart "use-default" defaultConfig
        else invokeRestart "retry" {})
      (parseConfig "config.json")
    );
    ```

    ## Comparison to Exceptions

    | Feature | Exceptions | Conditions |
    |---------|------------|------------|
    | Signaling | throw | signal |
    | Handling | catch (unwinds) | handle (can resume) |
    | Recovery | return value | invoke restart |
    | Stack | Unwound | Preserved (if resuming) |

    ## See Also
    - Common Lisp: CLHS 9 (Conditions)
    - Kent Pitman's "Condition System" paper
  '';
  value = {
    signal = mk {
      doc = ''
        Signals a condition, requesting handler from context.

        Unlike exceptions that unwind the stack, signaling a condition
        requests a handler without unwinding. The handler can:
        - Invoke a restart to resume
        - Return a value
        - Signal another condition
        - Decline (no match), bubbling to outer handlers

        ## Type Signature
        `Condition -> Fx<{handlers: [Handler], restarts: [Restart]}, {}>`

        ## Parameters
        - `condition`: Attrset describing the condition
          - `type`: String identifying condition type (required)
          - Other fields provide context

        ## Example
        ```nix
        # Signal parse error
        signal { 
          type = "parse-error"; 
          file = "config.json";
          line = 42;
        }

        # Handler will be invoked without unwinding
        ```

        ## Notes
        - Signal itself returns unit after handler completes
        - To abort with error, handler must invoke abort restart
        - Multiple handlers can be established (innermost first)

        ## See Also
        - `handle` - Establish handler
        - `withRestart` - Define recovery options
        - `error` - Signal non-resumable error
      '';
      type = fn fx;
      value = condition:
        nfx.pending (ctx:
          let
            handlers = ctx.handlers or [];
            restarts = ctx.restarts or [];
            
            # Find matching handler
            matchingHandler = builtins.foldl'
              (found: handler:
                if found != null then found
                else if handler.pattern == condition.type || handler.pattern == "*"
                     then handler
                     else null)
              null
              handlers;
            
            # Context with condition info for handler
            handlerCtx = ctx // {
              _condition = condition;
              _restarts = restarts;
            };
          in
            if matchingHandler != null
            then
              # Invoke handler with condition
              let handlerResult = matchingHandler.action condition;
              in nfx.contraMap (_: handlerCtx) (_: _: ctx) handlerResult
            else
              # No handler found - return unit (resumable)
              nfx.immediate ctx {}
        );
      tests = {
        "signal without handler returns unit" = {
          expr = nfx.runFx (
            nfx.provide { } (
              nfx.signal { type = "test"; }
            )
          );
          expected = { };
        };
        "signal with handler invokes handler" = {
          expr = nfx.runFx (
            nfx.provide {
              handlers = [{
                pattern = "test";
                action = cond: nfx.pure cond.value;
              }];
            } (
              nfx.signal { type = "test"; value = 42; }
            )
          );
          expected = { };
        };
      };
    };

    handle = mk {
      doc = ''
        Establishes a handler for conditions of given type.

        Handlers are dynamically scoped - they apply to all conditions
        signaled during the effect's execution. Handlers are checked
        from innermost to outermost.

        ## Type Signature
        `String -> (Condition -> Fx<S, V>) -> Fx<S, V> -> Fx<S, V>`

        ## Parameters
        - `conditionType`: Type of condition to handle ("*" matches all)
        - `handler`: Function receiving condition, returns effect
        - `effect`: Effect to protect with handler

        ## Example
        ```nix
        handle "parse-error" (cond:
          # Can invoke restart, return value, or signal
          invokeRestart "use-default" defaultConfig
        ) (
          parseFile "config.json"
        )
        ```

        ## Handler Actions
        The handler can:
        1. `invokeRestart name value` - Resume at signal point
        2. `pure value` - Provide value (if condition resumable)
        3. `signal otherCondition` - Chain handling
        4. Decline by signaling `{ type = "decline"; }`

        ## See Also
        - `signal` - Signal conditions
        - `withRestart` - Define restarts
        - `handleBind` - Multiple handlers
      '';
      type = fn (fn (fn fx));
      value = conditionType: handler: effect:
        nfx.contraMap
          (ctx: ctx // {
            handlers = [{
              pattern = conditionType;
              action = handler;
            }] ++ (ctx.handlers or []);
          })
          (ctx: inner: 
            # Remove handler from context after effect completes
            ctx // {
              handlers = ctx.handlers or [];
            })
          effect;
      tests = {
        "handle catches matching condition" = {
          expr = nfx.runFx (
            nfx.handle "error" (cond: nfx.pure cond.value) (
              nfx.then' (nfx.pure 99)
                (nfx.signal { type = "error"; value = 42; })
            )
          );
          expected = 99;
        };
        "handle ignores non-matching" = {
          expr = nfx.runFx (
            nfx.handle "other" (cond: nfx.pure 1) (
              nfx.then' (nfx.pure 99)
                (nfx.signal { type = "error"; value = 42; })
            )
          );
          expected = 99;
        };
        "innermost handler wins" = {
          expr = nfx.runFx (
            nfx.handle "error" (_: nfx.pure 1) (
              nfx.handle "error" (_: nfx.pure 2) (

                nfx.then' (nfx.pure 3)
                  (nfx.signal { type = "error"; })
              )
            )
          );
          expected = 3;
        };
      };
    };

    withRestart = mk {
      doc = ''
        Defines a named restart available at this scope.

        Restarts are recovery strategies offered by the code that signals.
        Handlers can invoke restarts to resume or recover from conditions.
        Multiple restarts can be defined, creating a menu of options.

        ## Type Signature
        `String -> (Value -> Fx<S, V>) -> Fx<S, V> -> Fx<S, V>`

        ## Parameters
        - `name`: Restart name (e.g., "retry", "use-default", "abort")
        - `action`: Function invoked when restart chosen
        - `effect`: Effect protected by this restart

        ## Example
        ```nix
        withRestart "use-default" (dflt: pure dflt)
          (withRestart "retry" (_: tryAgain)
            (parseFile "config.json"))
        ```

        ## Common Restart Names
        - `abort` - Abandon operation, return error
        - `retry` - Try operation again
        - `use-value` - Use provided value instead
        - `use-default` - Use default value
        - `skip` - Skip problematic operation
        - `continue` - Proceed despite warning

        ## See Also
        - `invokeRestart` - Invoke by name
        - `restart` - Direct restart invocation
        - `signal` - Signals that trigger restarts
      '';
      type = fn (fn (fn fx));
      value = name: action: effect:
        nfx.contraMap
          (ctx: ctx // {
            restarts = [{
              name = name;
              action = action;
            }] ++ (ctx.restarts or []);
          })
          (ctx: inner:
            # Remove restart from context after effect completes
            ctx // {
              restarts = ctx.restarts or [];
            })
          effect;
      tests = {
        "withRestart defines restart" = {
          expr = nfx.runFx (
            nfx.withRestart "use-default" (v: nfx.pure v) (
              nfx.pure 42
            )
          );
          expected = 42;
        };
        "nested restarts available" = {
          expr = nfx.runFx (
            nfx.withRestart "outer" (_: nfx.pure 1) (
              nfx.withRestart "inner" (_: nfx.pure 2) (
                nfx.pure 3
              )
            )
          );
          expected = 3;
        };
      };
    };

    invokeRestart = mk {
      doc = ''
        Finds and invokes a restart by name.

        Searches the dynamic restart stack for a restart with the given name
        and invokes it with the provided value. This is how handlers resume
        or recover from conditions.

        ## Type Signature
        `String -> Value -> Fx<{restarts: [Restart]}, V>`

        ## Parameters
        - `name`: Name of restart to invoke
        - `value`: Value to pass to restart action

        ## Example
        ```nix
        handle "parse-error" (cond:
          if recoverable cond
          then invokeRestart "use-default" defaultConfig
          else invokeRestart "abort" { error = cond; }
        ) protectedCode
        ```

        ## Behavior
        - Searches restarts innermost to outermost
        - Throws if restart not found
        - Invokes restart action with value
        - Control transfers to restart point

        ## See Also
        - `withRestart` - Define restarts
        - `restart` - Direct invocation
        - `findRestart` - Check restart availability
      '';
      type = fn (fn fx);
      value = name: value:
        nfx.pending (ctx:
          let
            restarts = ctx._restarts or ctx.restarts or [];
            
            # Find restart by name
            matchingRestart = builtins.foldl'
              (found: restart:
                if found != null then found
                else if restart.name == name then restart
                else null)
              null
              restarts;
          in
            if matchingRestart != null
            then
              # Invoke restart action
              let restartResult = matchingRestart.action value;
              in nfx.contraMap (_: ctx) (_: _: ctx) restartResult
            else
              # Restart not found - signal error
              nfx.immediate ctx (throw "Restart not found: ${name}")
        );
      tests = {
        "invokeRestart calls action" = {
          expr = nfx.runFx (
            nfx.withRestart "test" (v: nfx.pure (v * 2)) (
              nfx.handle "trigger" (_: nfx.invokeRestart "test" 21) (
                nfx.then' (nfx.pure 99)
                  (nfx.signal { type = "trigger"; })
              )
            )
          );
          expected = 42;
        };
      };
    };

    restart = mk {
      doc = ''
        Direct restart invocation (for use within signal context).

        Lower-level primitive for invoking restarts. Typically used
        within handler code when the restart is known to be available.

        ## Type Signature
        `String -> Value -> Fx<S, V>`

        ## Parameters
        - `name`: Restart name
        - `value`: Value for restart

        ## Example
        ```nix
        handle "error" (cond:
          restart "abort" { error = cond; }
        ) code
        ```

        ## See Also
        - `invokeRestart` - Recommended for general use
        - `withRestart` - Define restarts
      '';
      type = fn (fn fx);
      value = name: value: nfx.invokeRestart name value;
    };

    error = mk {
      doc = ''
        Signals a non-resumable error condition.

        Convenience function for signaling errors. Unlike general conditions,
        errors are not meant to be resumed from. Handlers should invoke a
        restart (typically "abort") rather than returning a value.

        ## Type Signature
        `String -> Attrset -> Fx<S, V>`

        ## Parameters
        - `message`: Error message
        - `details`: Additional error details

        ## Example
        ```nix
        error "File not found" { file = "config.json"; }

        # Handler must invoke restart:
        handle "error" (cond:
          invokeRestart "abort" cond
        ) code
        ```

        ## See Also
        - `signal` - General condition signaling
        - `cerror` - Continuable error
        - `warn` - Non-error condition
      '';
      type = fn (fn fx);
      value = message: details:
        nfx.signal (details // {
          type = "error";
          message = message;
        });
      tests = {
        "error signals error condition" = {
          expr = nfx.runFx (
            nfx.handle "error" (cond: nfx.pure cond.message) (
              nfx.then' (nfx.pure "unreachable")
                (nfx.error "test error" { code = 42; })
            )
          );
          expected = "unreachable";
        };
      };
    };

    cerror = mk {
      doc = ''
        Signals a continuable error with a default restart.

        Convenience for errors that have a sensible way to continue.
        Automatically defines a "continue" restart that returns the
        provided default value.

        ## Type Signature
        `String -> V -> String -> Attrset -> Fx<S, V>`

        ## Parameters
        - `continueMessage`: Message shown for continue option
        - `defaultValue`: Value if continue chosen
        - `errorMessage`: Error description
        - `details`: Error details

        ## Example
        ```nix
        cerror "Use default config" defaultConfig
          "Config parse failed" { file = "config.json"; }

        # Handler can:
        # - invokeRestart "continue" {} -> returns defaultConfig
        # - invokeRestart "abort" cond -> aborts
        ```

        ## See Also
        - `error` - Non-continuable error
        - `withRestart` - Manual restart definition
      '';
      type = fn (fn (fn (fn fx)));
      value = continueMessage: defaultValue: errorMessage: details:
        nfx.withRestart "continue" (_: nfx.pure defaultValue) (
          nfx.then' (nfx.pure defaultValue)
            (nfx.signal (details // {
              type = "error";
              message = errorMessage;
              continuable = true;
              continueMessage = continueMessage;
            }))
        );
      tests = {
        "cerror provides continue restart" = {
          expr = nfx.runFx (
            nfx.handle "error" (cond:
              if cond.continuable or false
              then nfx.invokeRestart "continue" {}
              else nfx.pure "abort"
            ) (
              nfx.cerror "Use default" 42 "Failed" { }
            )
          );
          expected = 42;
        };
      };
    };

    warn = mk {
      doc = ''
        Signals a warning condition.

        Warnings are informational conditions that don't require recovery.
        By default, they are ignored (resumable), but handlers can log,
        collect, or promote them to errors.

        ## Type Signature
        `String -> Attrset -> Fx<S, {}>`

        ## Parameters
        - `message`: Warning message
        - `details`: Additional context

        ## Example
        ```nix
        warn "Deprecated option" { option = "oldName"; }

        # Handler can log or collect:
        handle "warning" (cond:
          trace cond.message (pure {})
        ) code
        ```

        ## See Also
        - `signal` - General signaling
        - `error` - Error conditions
      '';
      type = fn (fn fx);
      value = message: details:
        nfx.signal (details // {
          type = "warning";
          message = message;
        });
      tests = {
        "warn is resumable" = {
          expr = nfx.runFx (
            nfx.then' (nfx.pure 42)
              (nfx.warn "test warning" { })
          );
          expected = 42;
        };
      };
    };

    handleBind = mk {
      doc = ''
        Establishes multiple handlers at once.

        Convenience for binding several handlers in one scope.
        Equivalent to nested `handle` calls but more concise.

        ## Type Signature
        `[{pattern: String, action: Handler}] -> Fx<S, V> -> Fx<S, V>`

        ## Parameters
        - `bindings`: List of {pattern, action} handlers
        - `effect`: Protected effect

        ## Example
        ```nix
        handleBind [
          { pattern = "error"; action = cond: invokeRestart "abort" cond; }
          { pattern = "warning"; action = cond: logWarning cond; }
        ] code
        ```

        ## See Also
        - `handle` - Single handler
        - `signal` - Condition signaling
      '';
      type = fn (fn fx);
      value = bindings: effect:
        builtins.foldl'
          (eff: binding: nfx.handle binding.pattern binding.action eff)
          effect
          bindings;
      tests = {
        "handleBind establishes multiple handlers" = {
          expr = nfx.runFx (
            nfx.handleBind [
              { pattern = "error"; action = _: nfx.pure 1; }
              { pattern = "warning"; action = _: nfx.pure 2; }
            ] (
              nfx.then' (nfx.pure 42)
                (nfx.signal { type = "warning"; })
            )
          );
          expected = 42;
        };
      };
    };

    findRestart = mk {
      doc = ''
        Checks if a restart is available.

        Searches the restart stack without invoking. Useful for
        handlers that want to check available recovery options.

        ## Type Signature
        `String -> Fx<{restarts: [Restart]}, Bool>`

        ## Parameters
        - `name`: Restart name to find

        ## Example
        ```nix
        func (ctx:
          if findRestart "retry" ctx
          then invokeRestart "retry" {}
          else invokeRestart "abort" {}
        )
        ```

        ## See Also
        - `invokeRestart` - Invoke restart
        - `listRestarts` - List all available
      '';
      type = fn fx;
      value = name:
        nfx.func (ctx:
          let
            restarts = ctx._restarts or ctx.restarts or [];
            found = builtins.any (r: r.name == name) restarts;
          in found
        );
      tests = {
        "findRestart detects available restart" = {
          expr = nfx.runFx (
            nfx.withRestart "test" (nfx.pure) (
              nfx.findRestart "test"
            )
          );
          expected = true;
        };
        "findRestart returns false when absent" = {
          expr = nfx.runFx (
            nfx.findRestart "missing"
          );
          expected = false;
        };
      };
    };

    ignoreErrors = mk {
      doc = ''
        Ignores all error conditions, returning default value.

        Convenience handler that catches all errors and provides
        a fallback value. Useful for optional operations.

        ## Type Signature
        `V -> Fx<S, V> -> Fx<S, V>`

        ## Parameters
        - `default`: Value to return on any error
        - `effect`: Effect that might error

        ## Example
        ```nix
        ignoreErrors {} (
          parseConfig "optional.json"
        )  # Returns {} if parse fails
        ```

        ## See Also
        - `handle` - Conditional handling
        - `cerror` - Continuable errors
      '';
      type = fn (fn fx);
      value = default: effect:
        nfx.handle "error" (_: nfx.pure default) effect;
      tests = {
        "ignoreErrors returns default on error" = {
          expr = nfx.runFx (
            nfx.ignoreErrors 99 (
              nfx.then' (nfx.pure 42)
                (nfx.error "test" { })
            )
          );
          expected = 99;
        };
      };
    };
  };
}
