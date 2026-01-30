{ nfx, api, ... }:
let
  inherit (api) mk;
  inherit (api.types) fn any fx;
in
mk {
  doc = ''
    Reader and Writer effects built on existing primitives.

    This module provides clean APIs for two common effect patterns:
    - **Reader**: Read-only environment access (built on state.get + provide)
    - **Writer**: Append-only output accumulation (built on acc)

    ## Reader Pattern
    Reader provides access to immutable environment/configuration without
    explicit parameter threading. It's just `state.get` with nicer names.

    ## Writer Pattern  
    Writer accumulates output (logs, events, metadata) alongside computation.
    It's just `acc` with monoid semantics and cleaner API.

    ## Example
    ```nix
    # Reader: configuration access
    runFx (runReader { debug = true; timeout = 30; } (
      asks (cfg: cfg.debug)
    ))  # => true

    # Writer: logging
    runFx (runWriter (
      then' (pure 42) (
        then' (tell "Done") (tell "Starting")
      )
    ))  # => { value = 42; output = ["Starting" "Done"]; }
    ```
  '';
  value = {
    # ============================================================================
    # READER EFFECT
    # ============================================================================
    
    ask = mk {
      doc = ''
        Reads the entire Reader environment.

        Retrieves the complete environment value that was provided via
        `runReader`. This is just `state.get` with a more semantic name
        for read-only environment access.

        ## Type Signature
        `Fx<Env, Env>`

        ## Example
        ```nix
        runFx (runReader { x = 1; y = 2; } (
          map (env: env.x + env.y) ask
        ))  # => 3
        ```

        ## See Also
        - `asks` - Read with projection
        - `runReader` - Provide environment
      '';
      type = fx;
      value = nfx.state.get;
      tests = {
        "ask reads environment" = {
          expr = nfx.runFx (nfx.provide { x = 42; } nfx.ask);
          expected = { x = 42; };
        };
      };
    };

    asks = mk {
      doc = ''
        Reads environment with a projection function.

        Retrieves a computed value from the environment by applying
        a function. Useful for extracting specific fields or deriving
        values from the environment.

        ## Type Signature
        `(Env -> A) -> Fx<Env, A>`

        ## Parameters
        - `f`: Projection function from environment to desired value

        ## Example
        ```nix
        runFx (runReader { port = 8080; host = "localhost"; } (
          asks (env: env.host + ":" + toString env.port)
        ))  # => "localhost:8080"
        ```

        ## See Also
        - `ask` - Read entire environment
        - `local` - Modify environment locally
      '';
      type = fn fx;
      value = f: nfx.map f nfx.ask;
      tests = {
        "asks projects environment" = {
          expr = nfx.runFx (nfx.provide { x = 10; y = 20; } (nfx.asks (env: env.x * 2)));
          expected = 20;
        };
      };
    };

    local = mk {
      doc = ''
        Runs an effect with a modified environment.

        Executes an effect with a locally transformed environment,
        without affecting the outer environment. The transformation
        only applies to the inner effect.

        ## Type Signature
        `(Env -> Env) -> Fx<Env, V> -> Fx<Env, V>`

        ## Parameters
        - `f`: Function to transform the environment
        - `e`: Effect to run with modified environment

        ## Example
        ```nix
        runFx (runReader { debug = false; } (
          local (env: env // { debug = true; }) (
            asks (env: env.debug)
          )
        ))  # => true (outer remains false)
        ```

        ## See Also
        - `ask` - Read environment
        - `runReader` - Provide initial environment
      '';
      type = fn (fn fx);
      value = f: e:
        nfx.mapM (ctx: nfx.provide (f ctx) e) nfx.state.get;
      tests = {
        "local modifies environment temporarily" = {
          expr = nfx.runFx (
            nfx.provide { x = 10; } (
              nfx.zip 
                (nfx.local (env: env // { x = 20; }) (nfx.asks (env: env.x)))
                (nfx.asks (env: env.x))
            )
          );
          expected = { fst = 10; snd = 20; };
        };
      };
    };

    runReader = mk {
      doc = ''
        Provides an environment for Reader effects.

        Supplies the environment that `ask` and `asks` will read.
        This is just `provide` with a semantic name for Reader pattern.

        ## Type Signature
        `Env -> Fx<Env, V> -> Fx<{}, V>`

        ## Parameters
        - `env`: Environment value to provide
        - `e`: Effect requiring environment

        ## Example
        ```nix
        runFx (runReader { apiKey = "secret"; baseUrl = "api.example.com"; } (
          asks (env: fetchUrl env.baseUrl env.apiKey)
        ))
        ```

        ## See Also
        - `ask` - Read environment
        - `asks` - Read with projection
      '';
      type = fn (fn fx);
      value = env: e: nfx.provide env e;
      tests = {
        "runReader provides environment" = {
          expr = nfx.runFx (nfx.runReader { value = 99; } (nfx.asks (e: e.value)));
          expected = 99;
        };
      };
    };

    # ============================================================================
    # WRITER EFFECT
    # ============================================================================

    tell = mk {
      doc = ''
        Appends a value to the Writer output.

        Accumulates a value in the Writer's output list. The value is
        appended to the current accumulated output without affecting
        the computation's result.

        ## Type Signature
        `A -> Fx<{acc: [A], state: S}, {}>`

        ## Parameters
        - `value`: Value to append to output

        ## Example
        ```nix
        runFx (runWriter (
          then' (pure 42) (
            then' (tell "step2") (tell "step1")
          )
        ))  # => { value = 42; output = ["step1" "step2"]; }
        ```

        ## See Also
        - `listen` - Capture output
        - `runWriter` - Execute and extract output
      '';
      type = fn fx;
      value = value: nfx.acc.accumulate nfx.acc.list value;
      tests = {
        "tell accumulates output" = {
          expr = nfx.runFx (
            nfx.provide 0 (
              nfx.acc.collect [ ] (
                nfx.tell "first"
              )
            )
          );
          expected = { acc = [ "first" ]; value = { }; };
        };
      };
    };

    listen = mk {
      doc = ''
        Runs an effect and captures its accumulated output.

        Executes an effect while collecting all `tell` calls into an
        output list. Returns both the effect's value and the accumulated
        output.

        ## Type Signature
        `Fx<{acc: [A], state: S}, V> -> Fx<S, {value: V, output: [A]}>`

        ## Parameters
        - `e`: Effect to execute with output capturing

        ## Returns
        `{value: V, output: [A]}` where output contains all `tell` values

        ## Example
        ```nix
        runFx (listen (
          then' (pure 42) (
            then' (tell "log2") (tell "log1")
          )
        ))  # => { value = 42; output = ["log1" "log2"]; }
        ```

        ## See Also
        - `tell` - Write to output
        - `censor` - Transform output
      '';
      type = fn fx;
      value = e:
        nfx.map (result: {
          value = result.value;
          output = result.acc;
        }) (nfx.acc.collect [ ] e);
      tests = {
        "listen captures output" = {
          expr = nfx.runFx (
            nfx.provide 0 (
              nfx.listen (
                nfx.then' (nfx.pure 42) (nfx.tell "msg")
              )
            )
          );
          expected = {
            value = 42;
            output = [ "msg" ];
          };
        };
      };
    };

    censor = mk {
      doc = ''
        Transforms the accumulated output of an effect.

        Runs an effect with output accumulation, then applies a
        transformation to the collected output before returning.
        The effect's value is unchanged.

        ## Type Signature
        `([A] -> [B]) -> Fx<{acc: [A]}, V> -> Fx<{}, {value: V, output: [B]}>`

        ## Parameters
        - `f`: Function to transform the accumulated output
        - `e`: Effect to execute

        ## Example
        ```nix
        runFx (censor (output: map toUpper output) (
          then' (pure 42) (
            then' (tell "world") (tell "hello")
          )
        ))  # => { value = 42; output = ["HELLO" "WORLD"]; }
        ```

        ## See Also
        - `tell` - Write to output
        - `listen` - Capture output
      '';
      type = fn (fn fx);
      value = f: e:
        nfx.map (result: {
          value = result.value;
          output = f result.output;
        }) (nfx.listen e);
      tests = {
        "censor transforms output" = {
          expr = nfx.runFx (
            nfx.provide 0 (
              nfx.censor (output: output ++ [ "end" ]) (
                nfx.then' (nfx.pure 42) (nfx.tell "start")
              )
            )
          );
          expected = {
            value = 42;
            output = [ "start" "end" ];
          };
        };
      };
    };

    runWriter = mk {
      doc = ''
        Executes a Writer effect and extracts both value and output.

        Runs an effect that uses `tell` to accumulate output, returning
        both the computed value and all accumulated output.

        ## Type Signature
        `Fx<{acc: [A], state: S}, V> -> Fx<S, {value: V, output: [A]}>`

        ## Parameters
        - `e`: Writer effect to execute

        ## Returns
        `{value: V, output: [A]}` containing result and accumulated output

        ## Example
        ```nix
        runFx (runWriter (
          mapM (verbose:
            if verbose 
            then then' (pure "OK") (tell "Verbose mode")
            else pure "OK"
          ) (asks (cfg: cfg.verbose))
        ))
        ```

        ## See Also
        - `execWriter` - Extract only output
        - `tell` - Write to output
      '';
      type = fn fx;
      value = e: nfx.listen e;
      tests = {
        "runWriter extracts value and output" = {
          expr = nfx.runFx (
            nfx.provide 0 (
              nfx.runWriter (
                nfx.then' (nfx.pure 99) (
                  nfx.then' (nfx.tell "b") (nfx.tell "a")
                )
              )
            )
          );
          expected = {
            value = 99;
            output = [ "a" "b" ];
          };
        };
      };
    };

    execWriter = mk {
      doc = ''
        Executes a Writer effect and extracts only the accumulated output.

        Like `runWriter` but discards the computed value, returning only
        the accumulated output. Useful when the accumulation is the goal.

        ## Type Signature
        `Fx<{acc: [A], state: S}, V> -> Fx<S, [A]>`

        ## Parameters
        - `e`: Writer effect to execute

        ## Returns
        List of all accumulated values from `tell` calls

        ## Example
        ```nix
        runFx (execWriter (
          then' (pure "ignored") (
            then' (tell "event3") (
              then' (tell "event2") (tell "event1")
            )
          )
        ))  # => ["event1" "event2" "event3"]
        ```

        ## See Also
        - `runWriter` - Extract both value and output
        - `tell` - Write to output
      '';
      type = fn fx;
      value = e:
        nfx.map (result: result.output) (nfx.listen e);
      tests = {
        "execWriter extracts only output" = {
          expr = nfx.runFx (
            nfx.provide 0 (
              nfx.execWriter (
                nfx.then' (nfx.pure "ignored") (
                  nfx.then' (nfx.tell "y") (nfx.tell "x")
                )
              )
            )
          );
          expected = [ "x" "y" ];
        };
      };
    };

    pass = mk {
      doc = ''
        Runs an effect that returns both a value and an output transformer.

        Advanced Writer combinator that allows the effect to specify how
        its own output should be transformed. The effect returns a pair
        of (value, output-transformer-function).

        ## Type Signature
        `Fx<{acc: [A]}, (V, [A] -> [B])> -> Fx<{}, {value: V, output: [B]}>`

        ## Parameters
        - `e`: Effect returning (value, transformation-function)

        ## Example
        ```nix
        runFx (pass (
          then' (pure {
            value = 42;
            transform = output: map toUpper output;
          }) (tell "raw")
        ))  # => { value = 42; output = ["RAW"]; }
        ```

        ## See Also
        - `censor` - Simpler output transformation
        - `listen` - Capture output
      '';
      type = fn fx;
      value = e:
        nfx.mapM (result:
          nfx.pure {
            value = result.value.value;
            output = result.value.transform result.output;
          }
        ) (nfx.listen e);
      tests = {
        "pass applies returned transformer" = {
          expr = nfx.runFx (
            nfx.provide 0 (
              nfx.pass (
                nfx.then' (nfx.pure {
                  value = 42;
                  transform = output: output ++ [ "extra" ];
                }) (nfx.tell "msg")
              )
            )
          );
          expected = {
            value = 42;
            output = [ "msg" "extra" ];
          };
        };
      };
    };

    listens = mk {
      doc = ''
        Like `listen` but applies a projection to the captured output.

        Executes an effect with output capturing, applies a function to
        transform the output, and returns both the value and transformed
        output.

        ## Type Signature
        `([A] -> B) -> Fx<{acc: [A]}, V> -> Fx<{}, {value: V, output: B}>`

        ## Parameters
        - `f`: Function to transform captured output
        - `e`: Effect to execute

        ## Example
        ```nix
        runFx (listens (output: length output) (
          then' (pure 42) (
            then' (tell "b") (tell "a")
          )
        ))  # => { value = 42; output = 2; }
        ```

        ## See Also
        - `listen` - Capture output as-is
        - `censor` - Transform output before returning
      '';
      type = fn (fn fx);
      value = f: e:
        nfx.map (result: {
          value = result.value;
          output = f result.output;
        }) (nfx.listen e);
      tests = {
        "listens projects output" = {
          expr = nfx.runFx (
            nfx.provide 0 (
              nfx.listens (builtins.length) (
                nfx.then' (nfx.pure 42) (
                  nfx.then' (nfx.tell "b") (nfx.tell "a")
                )
              )
            )
          );
          expected = {
            value = 42;
            output = 2;
          };
        };
      };
    };
  };
}
