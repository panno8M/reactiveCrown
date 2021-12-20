{.deadCodeElim.}
import std/sugar
import ../core

type MapObservable[T] = object
  observer: Observer[T]
  OnSubscribe: (ptr MapObservable[T]) -> Disposable

proc onSubscribe*[T](observable: var MapObservable[T]; observer: Observer[T]): Disposable =
  observable.observer = observer
  observable.OnSubscribe(observable.addr)

proc map*[T, S](upstream: var ConceptObservable[T]; predicate: T->S): MapObservable[S] =
  let upstream = upstream.addr
  proc OnSubscribe(observable: ptr MapObservable[S]): Disposable =
    upstream[].subscribe(
      ((x:             T) => observable[].observer.onNext x.predicate),
      ((x: ref Exception) => observable[].observer.onError x),
      ((                ) => observable[].observer.onComplete))
  MapObservable[S](
    OnSubscribe: OnSubscribe
    )

proc map*[T, S](upstream: var ConceptObservable[T]; predicate: (T, int)->S): MapObservable[S] =
  let upstream = upstream.addr
  var i: int
  proc OnSubscribe(observable: ptr MapObservable[S]): Disposable =
    upstream[].subscribe(
      (x:             T) => (observable[].observer.onNext x.predicate(i); inc i),
      (x: ref Exception) => (observable[].observer.onError x),
      (                ) => (observable[].observer.onComplete))
  MapObservable[S](
    OnSubscribe: OnSubscribe
    )


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

template test(): untyped {.used.} =
  suite "Operator - Map":
    test "concept conversion":
      check MapObservable[int] is ConceptObservable[int]

    block: test_dontChangeType
    block: test_changeType

when isMainModule:
  MapObservable[int] -?-> ConceptObservable[int]
  var x: MapObservable[int]
  discard x.addr.toAbstractObservable
  import std/unittest
  import reactiveCrown/subjects

  test
