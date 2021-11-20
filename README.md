# RxNim
ReactiveX implemented with Nim.  
See [Documents](https://panno8m.github.io/RxNim/rx.html).

## Notes on use

This library uses compositions and "converter" to represent the interface.

For example, `toObservable` of `someSubject.toObservable.subscribe(...)` is defined as converter so you can rewrite it to `someSubject.subscribe(...)`.
However, due to a problem in the Nim specification, if you omit the conversion for the Observable type after the second argument, it will not be implicitly converted, and you will also get a very confusing compilation error.

```nim
# Bad...
sbj1.concat(sbj2, sbj3).subscribe(...)
# stdErr ->
# fatal.nim(53)            sysFatal
# Error: unhandled exception: ccgtypes.nim(198, 17) `false` mapType: tyGenericInvocation [AssertionDefect]

# Ok!
sbj1.concat(sbj2.toObservable, sbj3.toObservable).subscribe(...)
```

Be careful not to omit the conversion for the Observable type after the second argument.