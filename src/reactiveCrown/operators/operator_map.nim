{.deadCodeElim.}
import std/sugar
import std/importutils
import std/macros
import ../core
import operator_concept {.all.}

template finallyConsume(body) =
  try: body
  finally: consume observable[].disposable

template map_onError = 
  (e: ref Exception) => finallyConsume( observer.onError e )
template map_onComplete = 
  () => finallyConsume( observer.onComplete )

proc map*[T, S](upstream: var ConceptObservable[T]; predicate: T->S): OperatorObservable[S] =
  privateAccess OperatorObservable
  let upstream = upstream.addr
  result.OnSubscribe =
    proc(observable: ptr OperatorObservable[S]; observer: Observer[S]): Disposable =
      observable[].disposable = upstream[].subscribe(
        (x: T) => (
          try: observer.onNext predicate(x)
          except: finallyConsume( observer.onError getCurrentException() )
        ),
        map_onError,
        map_onComplete)
      return observable[].disposable

proc map*[T, S](upstream: var ConceptObservable[T]; predicate: (T, int)->S): OperatorObservable[S] =
  privateAccess OperatorObservable
  let upstream = upstream.addr
  result.OnSubscribe =
    proc(observable: ptr OperatorObservable[S]; observer: Observer[S]): Disposable =
      var i: int
      observable[].disposable = upstream[].subscribe(
        (x: T) => (
          try: observer.onNext predicate(x, ^++i)
          except: finallyConsume( observer.onError getCurrentException() )
        ),
        map_onError,
        map_onComplete)
      return observable[].disposable


# =================== #
#      Unit Test      #
# =================== #

template test_dontChangeType(): untyped =
  setup:
    var
      results, expects: seq[int]
      subject: PublishSubject[int]

  teardown:
    check results == expects

  test "map(T)":
    expects = @[10000, 40000, 90000]
    subject
      .map(x => x * x){}
      .subscribe((x: int) => results.add x)

    subject.next 100, 200, 300
    subject.complete

  test "map(T) -> map(T)":
    expects = @[0, 200, 600]
    subject
      .map((x, i) => x * i){}
      .subscribe((x: int) => results.add x)

    subject.next 100, 200, 300
    subject.complete

  test "map(T, i)":
    expects = @[16, 256, 4096]
    subject
      .map(x => x * x){}
      .map(x => x * x){}
      .subscribe((x: int) => results.add x)

    subject.next 2, 4, 8
    subject.complete

  test "map(T, i) -> map(T)":
    expects = @[0, 2000, 6000]
    subject
      .map((x, i) => x * i){}
      .map(x => x * 10){}
      .subscribe((x: int) => results.add x)

    subject.next 100, 200, 300
    subject.complete


template test_changeType(): untyped =
  setup:
    var
      results, expects: seq[string]
      subject: PublishSubject[int]

  teardown:
    check results == expects

  test "map(T):S":
    expects = @[$100100, $200200, $300300]
    subject
      .map(x => $x & $x){}
      .subscribe((x: string) => results.add x)

    subject.next 100, 200, 300
    subject.complete

  test "map(T, i):S":
    expects = @[$1000, $2001, $3002]
    subject
      .map((x, i) => $x & $i){}
      .subscribe((x: string) => results.add x)

    subject.next 100, 200, 300
    subject.complete

  test "map(T):S -> map(S)":
    expects = @[$2222, $4444, $8888]
    subject
      .map(x => $x & $x){}
      .map(x => x & x){}
      .subscribe((x: string) => results.add x)

    subject.next 2, 4, 8
    subject.complete

  test "map(T, i):S -> map(S)":
    expects = @[$10001000, $20012001, $30023002]
    subject
      .map((x, i) => $x & $i){}
      .map(x => $x & $x){}
      .subscribe((x: string) => results.add x)

    subject.next 100, 200, 300
    subject.complete

template test_error(): untyped =
  setup:
    var
      results, expects: seq[int]
      subject: PublishSubject[string]
  teardown:
      check results == expects

  test "error":
    expects = @[0, -1]
    subject
      .map( proc(x: string): int =
        try: parseInt(x)
        except: raise ReraiseDefect.newException("Error")
      ){}
      .subscribe(
        (x: int) => (results.add x),
        (x: ref Exception) => (results.add -1)
      )
    subject.next "0"
    subject.next "X"
    subject.next "1"
    check not subject.hasAnyObservers

template test_multiSubscribing(): untyped =
  setup:
    var
      results, expects: seq[int]
      subject: PublishSubject[int]
  teardown:
    check results == expects

  test "multi-subscribe":
    expects = @[0, 0, 2, 2]
    var mapped = subject.map((x, i) => x * i)
    mapped.subscribe((x: int) => results.add x)
    mapped.subscribe((x: int) => results.add x)

    subject.next 1, 2


template test(): untyped {.used.} =
  suite "Operator - Map":
    block: test_dontChangeType
    block: test_changeType
    block: test_error
    block: test_multiSubscribing

when isMainModule:
  import std/unittest
  import std/strutils
  import reactiveCrown/subjects

  test
