{.deadCodeElim.}
import std/sugar
import std/importutils
import std/macros
import ../core
import operator_concept {.all.}

template finallyConsume(body) =
  try: body
  finally: consume observable[].disposable

template filter_onError = 
  (e: ref Exception) => finallyConsume( observer.onError e )
template filter_onComplete = 
  () => finallyConsume( observer.onComplete )

proc filter*[T](upstream: var ConceptObservable[T]; predicate: T->bool): OperatorObservable[T] =
  privateAccess OperatorObservable
  let upstream = upstream.addr
  result.OnSubscribe = proc(observable: ptr OperatorObservable[T]; observer: Observer[T]): Disposable =
    observable[].disposable = upstream[].subscribe(
      (x : T) => (
        try:
          if predicate(x): observer.onNext x
        except: finallyConsume( observer.onError getCurrentException() )
      ),
      filter_onError,
      filter_onComplete)
    return observable[].disposable

proc filter*[T](upstream: var ConceptObservable[T]; predicate: (T, int)->bool): OperatorObservable[T] =
  privateAccess OperatorObservable
  let upstream = upstream.addr
  result.OnSubscribe = proc(observable: ptr OperatorObservable[T]; observer: Observer[T]): Disposable =
    var i: int
    observable[].disposable = upstream[].subscribe(
      (x : T) => (
        try:
          if predicate(x, ^++i): observer.onNext x
        except: finallyConsume( observer.onError getCurrentException() )
      ),
      filter_onError,
      filter_onComplete)
    return observable[].disposable


# =================== #
#      Unit Test      #
# =================== #

template test_error =
  setup:
    var
      results, expects: seq[string]
      subject: PublishSubject[string]
  teardown:
      check results == expects

  test "error":
    expects = @["0", "Error"]
    subject
      .filter( proc(x: string): bool =
        try: parseInt(x) == 0
        except: raise ReraiseDefect.newException("Error")
      ){}
      .subscribe(
        (x: string) => (results.add x),
        (x: ref Exception) => (results.add x.msg)
      )
    subject.next "0"
    subject.next "X"
    subject.next "0"
    check not subject.hasAnyObservers

template test_multiSubscribing =
  setup:
    var
      results, expects: seq[int]
      subject: PublishSubject[int]
  teardown:
    check results == expects

  test "multi-subscribe":
    expects = @[1, 1, 3, 3]
    var filtered = subject.filter((x, i) => i mod 2 == 0)
    filtered.subscribe((x: int) => results.add x)
    filtered.subscribe((x: int) => results.add x)

    subject.next 1, 2, 3

template test {.used.} =
  suite "Operator - Filter":
    setup:
      var
        results, expects: seq[int]
        subject: PublishSubject[int]

    teardown:
      check results == expects

    test "filter(T)":
      expects = @[3, 9, 300]
      subject
        .filter(x => x mod 3 == 0){}
        .subscribe((x: int) => results.add x)

      subject.next 3, 5, 7, 9, 300
      subject.complete

    test "filter(T, i)":
      expects = @[3, 5, 7, 9]
      subject
        .filter((x, i) => (x + i) mod 3 == 0){}
        .subscribe((x: int) => results.add x)

      # (3 + 0), (5 + 1), (7 + 2), (9 + 3), (300 + 4)
      subject.next 3, 5, 7, 9, 300
      subject.complete

    test "filter(T) -> filter(T)":
      expects = @[300]
      subject
        .filter(x => x mod 3 == 0){}
        .filter(x => x mod 5 == 0){}
        .subscribe((x: int) => results.add x)

      subject.next 3, 5, 7, 9, 300
      subject.complete

    test "filter(T, i) -> filter(T)":
      expects = @[5]
      subject
        .filter((x, i) => (x + i) mod 3 == 0){}
        .filter(x => x mod 5 == 0){}
        .subscribe((x: int) => results.add x)

      # (3 + 0), (5 + 1), (7 + 2), (9 + 3), (300 + 4)
      subject.next 3, 5, 7, 9, 300
      subject.complete

    block: test_error
    block: test_multiSubscribing

when isMainModule:
  import std/unittest
  import std/strutils
  import reactiveCrown/subjects
  test