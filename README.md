<p align="right">
  <a href="https://github.com/sponsors/vic"><img src="https://img.shields.io/badge/sponsor-vic-white?logo=githubsponsors&logoColor=white&labelColor=%23FF0000" alt="Sponsor Vic"/>
  </a>
  <a href="https://github.com/vic/nfx/releases"><img src="https://img.shields.io/github/v/release/vic/nfx?style=plastic&logo=github&color=purple"/></a>
  <a href="LICENSE"> <img src="https://img.shields.io/github/license/vic/nfx" alt="License"/> </a>
  <a href="https://github.com/vic/nfx/actions">
  <img src="https://github.com/vic/nfx/actions/workflows/test.yml/badge.svg" alt="CI Status"/> </a>
</p>

# nfx - An Algebraic Effects System with Handlers for Nix

> nfx is made for you with Love by @vic. If you like my work, consider [sponsoring](https://github.com/sponsors/vic)

***See our [Documentation](https://vic.github.io/nfx) website***

## Architecture

Built from four [kernel primitives](https://github.com/vic/nfx/blob/main/nix/kernel.nix) in ~30 lines:

1. **immediate** - Effect with resolved value
2. **pending** - Effect awaiting context  
3. **adapt** - Transform context and continuation
4. **runFx** - Evaluate effect when requirements satisfied

Everything else derives from these: map, flatMap, state, errors, streams, logic programming.

## Module Overview

### Core System

**kernel** - Foundation providing immediate/pending constructors, eval, and adapt  
**basic** - Value lifting with pure and value  
**functor** - Transform effects with map and contraMap  
**monad** - Sequence effects with mapM, flatMap, and then'  
**provide** - Satisfy context requirements and inject dependencies  
**sequence** - Do-notation for readable effect chains

### Context Management

**state** - Implicit state threading (get, set, modify)  
**context** - Attribute-based context manipulation  
**request** - Named capability requests  
**handlers** - Effect interception and transformation  
**lens** - Bidirectional focus on nested context  
**pair** - Product types for heterogeneous contexts  
**and** - Context conjunction operations  
**zip** - Parallel effect combination

### Specialized Effects

**conditions** - Common Lisp style resumable error handling with signals, handlers, and restarts  
**result** - Simple throw/catch error propagation  
**bracket** - Resource management with guaranteed cleanup  
**rw** - Reader (environment access) and Writer (output accumulation)  
**acc** - Accumulator patterns (list, attrset, sum, product)  
**choice** - Non-deterministic logic programming with backtracking  
**arrow** - Pure function composition in context

### Stream Processing

**stream-core** - Lazy stream constructors (done, more, fromList, repeat)  
**stream-transform** - Element transformation (map, filter)  
**stream-limit** - Length control (take, takeWhile)  
**stream-reduce** - Consumption (fold, toList, forEach)  
**stream-combine** - Combination (concat, interleave, flatten, flatMap, zip)
