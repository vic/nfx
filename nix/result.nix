{ nfx, api, ... }:
let
  inherit (api) mk;
  inherit (api.types) fn any fx;
in
mk {
  doc = ''
    Simple Result-based error handling built on condition system.

    Provides familiar throw/catch semantics as a convenience layer over
    the more powerful condition system. Unlike conditions, Results always
    unwind the stack on error.

    ## Comparison

    | Result | Conditions |
    |--------|------------|
    | throw'/catch' | signal/handle |
    | Always unwinds | Can resume |
    | Simple | Powerful |
    | One handler wins | Multiple handlers |

    ## Example
    ```nix
    result = catch' (
      divide = x: y:
        if y == 0
        then throw' "DivideByZero" { dividend = x; }
        else pure (x / y);
      
      divide 10 2
    );
    # => Ok 5

    result2 = catch' (divide 10 0);
    # => Err { type = "DivideByZero"; dividend = 10; }
    ```

    ## When to Use

    - Use **Result** for simple error propagation
    - Use **Conditions** when you need resumption or multiple handlers
  '';
  value = {
    throw' = mk {
      doc = ''
        Throw an error that unwinds the stack.

        Signals an error condition that cannot be resumed. The error will
        propagate up to the nearest catch' handler.

        ## Type Signature
        `String -> Attrs -> Fx<S, never>`

        ## Parameters
        - `errorType`: Error type identifier
        - `details`: Additional error information

        ## Example
        ```nix
        validateAge = age:
          if age < 0
          then throw' "InvalidAge" { age = age; }
          else pure age;
        ```

        ## See Also
        - `catch'` - Handle thrown errors
        - `try` - Catch with default value
        - `error` - Non-resumable condition system error
      '';
      type = fn (fn fx);
      value = errorType: details: nfx.error errorType (details // { _isResult = true; });
      tests = {
        "throw' signals error" = {
          expr = nfx.runFx (nfx.catch' (nfx.throw' "TestError" { code = 42; }));
          expected = {
            success = false;
            error = {
              type = "TestError";
              code = 42;
              _isResult = true;
            };
          };
        };
      };
    };

    catch' = mk {
      doc = ''
        Catch errors thrown with throw'.

        Wraps an effect to catch any thrown errors and return them as
        Result values: { success = true; value = v; } for success or
        { success = false; error = e; } for errors.

        ## Type Signature
        `Fx<S, V> -> Fx<S, Result<V>>`

        ## Parameters
        - `effect`: Effect that may throw errors

        ## Returns
        Result with either:
        - `{ success = true; value = V; }`
        - `{ success = false; error = ErrorDetails; }`

        ## Example
        ```nix
        result = catch' (
          bind (pure 10) (x:
            if x > 5
            then throw' "TooBig" { value = x; }
            else pure x
          )
        );
        # => { success = false; error = { type = "TooBig"; value = 10; }; }
        ```

        ## See Also
        - `throw'` - Throw an error
        - `try` - Catch with default value
      '';
      type = fn fx;
      value =
        effect:
        nfx.then'
          (
            v:
            nfx.pure {
              success = true;
              value = v;
            }
          )
          (
            nfx.handle "error" (
              cond:
              nfx.pure {
                success = false;
                error = cond;
              }
            ) effect
          );
      tests = {
        "catch' wraps success" = {
          expr = nfx.runFx (nfx.catch' (nfx.pure 42));
          expected = {
            success = true;
            value = 42;
          };
        };
        "catch' wraps error" = {
          expr = nfx.runFx (nfx.catch' (nfx.throw' "Failed" { reason = "test"; }));
          expected = {
            success = false;
            error = {
              type = "Failed";
              reason = "test";
              _isResult = true;
            };
          };
        };
        "catch' allows nesting" = {
          expr = nfx.runFx (
            nfx.catch' (
              nfx.then' (
                result:
                if result.success then nfx.pure result.value else nfx.throw' "Propagated" { inner = result.error; }
              ) (nfx.catch' (nfx.throw' "Inner" { level = 1; }))
            )
          );
          expected = {
            success = false;
            error = {
              type = "Propagated";
              inner = {
                type = "Inner";
                level = 1;
                _isResult = true;
              };
              _isResult = true;
            };
          };
        };
      };
    };

    try = mk {
      doc = ''
        Try an effect, returning a default value on error.

        Convenience wrapper around catch' that extracts the value or
        returns the default on error.

        ## Type Signature
        `V -> Fx<S, V> -> Fx<S, V>`

        ## Parameters
        - `default`: Value to return if effect throws
        - `effect`: Effect to try

        ## Example
        ```nix
        result = try 0 (
          if somethingWrong
          then throw' "Failed" {}
          else pure 42
        );
        # => 42 on success, 0 on error
        ```

        ## See Also
        - `catch'` - Catch and inspect error
        - `throw'` - Throw an error
      '';
      type = fn (fn fx);
      value =
        default: effect:
        nfx.then' (result: if result.success then nfx.pure result.value else nfx.pure default) (
          nfx.catch' effect
        );
      tests = {
        "try returns value on success" = {
          expr = nfx.runFx (nfx.try 0 (nfx.pure 42));
          expected = 42;
        };
        "try returns default on error" = {
          expr = nfx.runFx (nfx.try 99 (nfx.throw' "Failed" { }));
          expected = 99;
        };
      };
    };

    mapResult = mk {
      doc = ''
        Transform the value inside a successful Result.

        Applies a function to the value if the Result is successful,
        otherwise passes the error through unchanged.

        ## Type Signature
        `(A -> B) -> Result<A> -> Result<B>`

        ## Parameters
        - `f`: Function to apply to successful value
        - `result`: Result to transform

        ## Example
        ```nix
        mapResult (x: x * 2) { success = true; value = 21; }
        # => { success = true; value = 42; }

        mapResult (x: x * 2) { success = false; error = {...}; }
        # => { success = false; error = {...}; }
        ```
      '';
      type = fn (fn any);
      value =
        f: result:
        if result.success then
          {
            success = true;
            value = f result.value;
          }
        else
          result;
      tests = {
        "mapResult transforms success" = {
          expr = nfx.mapResult (x: x * 2) {
            success = true;
            value = 21;
          };
          expected = {
            success = true;
            value = 42;
          };
        };
        "mapResult passes error" = {
          expr = nfx.mapResult (x: x * 2) {
            success = false;
            error = {
              type = "Err";
            };
          };
          expected = {
            success = false;
            error = {
              type = "Err";
            };
          };
        };
      };
    };

    bindResult = mk {
      doc = ''
        Chain Result-producing operations.

        If the Result is successful, applies the function to the value.
        Otherwise passes the error through.

        ## Type Signature
        `(A -> Result<B>) -> Result<A> -> Result<B>`

        ## Parameters
        - `f`: Function returning a Result
        - `result`: Input Result

        ## Example
        ```nix
        validateAge = age:
          if age < 0 then { success = false; error = "negative"; }
          else { success = true; value = age; };

        bindResult validateAge { success = true; value = 25; }
        # => { success = true; value = 25; }
        ```
      '';
      type = fn (fn any);
      value = f: result: if result.success then f result.value else result;
      tests = {
        "bindResult chains success" = {
          expr =
            nfx.bindResult
              (x: {
                success = true;
                value = x * 2;
              })
              {
                success = true;
                value = 21;
              };
          expected = {
            success = true;
            value = 42;
          };
        };
        "bindResult passes error" = {
          expr =
            nfx.bindResult
              (x: {
                success = true;
                value = x * 2;
              })
              {
                success = false;
                error = {
                  type = "Err";
                };
              };
          expected = {
            success = false;
            error = {
              type = "Err";
            };
          };
        };
        "bindResult propagates inner error" = {
          expr =
            nfx.bindResult
              (x: {
                success = false;
                error = {
                  inner = true;
                };
              })
              {
                success = true;
                value = 42;
              };
          expected = {
            success = false;
            error = {
              inner = true;
            };
          };
        };
      };
    };
  };
}
