{.deadCodeElim.}
import std/sugar
import ../core

type MapObservable[T] = object
  observer: Observer[T]
  OnSubscribe: (ptr MapObservable[T]) -> Disposable

proc onSubscribe*[T](observable: var MapObservable[T]; observer: Observer[T]): Disposable =
  observable.observer = observer
  observable.OnSubscribe(observable.addr)

proc map_immutable*[T, S](upstream: ptr ConceptObservable[T]; predicate: T->S): MapObservable[S] =
  proc OnSubscribe(observable: ptr MapObservable[S]): Disposable =
    upstream[].subscribe(
      ((x:             T) => observable[].observer.onNext x.predicate),
      ((x: ref Exception) => observable[].observer.onError x),
      ((                ) => observable[].observer.onComplete))
  MapObservable[S](
    OnSubscribe: OnSubscribe
    )
proc map_immutable*[T, S](upstream: var ConceptObservable[T]; predicate: T->S): MapObservable[S] =
  upstream.addr.map_immutable(predicate)

proc map_immutable*[T, S](upstream: ptr ConceptObservable[T]; predicate: (T, int)->S): MapObservable[S] =
  var i: int
  proc OnSubscribe(observable: ptr MapObservable[S]): Disposable =
    upstream[].subscribe(
      (x:             T) => (observable[].observer.onNext x.predicate(i); inc i),
      (x: ref Exception) => (observable[].observer.onError x),
      (                ) => (observable[].observer.onComplete))
  MapObservable[S](
    OnSubscribe: OnSubscribe
    )
proc map_immutable*[T, S](upstream: var ConceptObservable[T]; predicate: (T, int)->S): MapObservable[S] =
  upstream.addr.map_immutable(predicate)

template map*[T](upstream: var ConceptObservable[T]; predicate: proc): untyped =
  var observable {.gensym.} = upstream.map_immutable(predicate)
  observable


template test(): untyped {.used.} =
  suite "Operator - Map":
    test "concept conversion":
      check MapObservable[int] is ConceptObservable[int]

    test "map(T)":
      var results: seq[int]
      var subject: PublishSubject[int]

      subject
        .map(x => x * x)
        .subscribe((x: int) => results.add x)

      subject.next 100, 200, 300
      subject.complete

      check results.len == 3
      check results == [10000, 40000, 90000]

    test "map(T) -> map(T)":
      var results: seq[int]
      var subject: PublishSubject[int]

      subject
        .map((x, i) => x * i)
        .subscribe((x: int) => results.add x)

      subject.next 100, 200, 300
      subject.complete

      check results.len == 3
      check results == [0, 200, 600]

    test "map(T, i)":
      var results: seq[int]
      var subject: PublishSubject[int]

      subject
        .map(x => x * x)
        .map(x => x * x)
        .subscribe((x: int) => results.add x)

      subject.next 2, 4, 8
      subject.complete

      check results.len == 3
      check results == [16, 256, 4096]

    test "map(T, i) -> map(T)":
      var results: seq[int]
      var subject: PublishSubject[int]

      subject
        .map((x, i) => x * i)
        .map(x => x * 10)
        .subscribe((x: int) => results.add x)

      subject.next 100, 200, 300
      subject.complete

      check results.len == 3
      check results == [0, 2000, 6000]


when isMainModule:
  MapObservable[int] -?-> ConceptObservable[int]
  var x: MapObservable[int]
  discard x.addr.toAbstractObservable
  import std/unittest
  import reactiveCrown/subjects

  test
