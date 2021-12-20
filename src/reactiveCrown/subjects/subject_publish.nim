{.deadCodeElim.}
{.experimental: "strictFuncs".}
{.experimental: "strictEffects".}
import ../core
import subject_concept

type PublishSubject*[T] {.byref.} = object
  observers*: seq[Observer[T]]
  stat: tuple[
    isCompleted: bool,
    error: ref Exception ]

# == API ==
proc onNext*[T](this: var PublishSubject[T]; x: T)
proc onError*[T](this: var PublishSubject[T]; x: ref Exception)
proc onComplete*[T](this: var PublishSubject[T])
proc onSubscribe*[T](this: var PublishSubject[T]; observer: Observer[T]): Disposable

func hasAnyObservers*[T](this: var PublishSubject[T]): bool
proc removeObserver*[T](this: var PublishSubject[T]; observer: Observer[T])

func isCompleted*[T](this: var PublishSubject[T]): bool {.inline.}
func getLastError*[T](this: var PublishSubject[T]): ref Exception {.inline.}
proc addObserver[T](this: var PublishSubject[T]; observer: Observer[T])

func isInvalid*[T](this: var PublishSubject[T]): bool

proc next*[T](this: var PublishSubject[T]; x: T; xs: varargs[T])
proc error*[T](this: var PublishSubject[T]; x: ref Exception)
proc complete*[T](this: var PublishSubject[T])
# == API ==

func isCompleted*[T](this: var PublishSubject[T]): bool {.inline.} = this.stat.isCompleted
func getLastError*[T](this: var PublishSubject[T]): ref Exception {.inline.} = this.stat.error
proc addObserver[T](this: var PublishSubject[T]; observer: Observer[T]) =
  this.observers.add observer

func hasAnyObservers*[T](this: var PublishSubject[T]): bool =
  this.observers.len != 0
proc removeObserver*[T](this: var PublishSubject[T]; observer: Observer[T]) =
  for i in countdown(this.observers.high, 0):
    if this.observers[i] == observer:
      this.observers.delete i
      break
proc onSubscribe*[T](this: var PublishSubject[T]; observer: Observer[T]): Disposable =
  if this.isCompleted:
    observer.onComplete
  elif this.getLastError != nil:
    observer.onError this.getLastError
  else:
    this.addobserver observer
  let ptrthis = addr this
  Disposable.issue:
    ptrthis[].removeObserver observer

{.push, raises: [].}
func isInvalid*[T](this: var PublishSubject[T]): bool =
  this.stat.isCompleted or this.stat.error != nil
proc onNext*[T](this: var PublishSubject[T]; x: T) =
  if this.isInvalid: return
  if this.hasAnyObservers:
    try:
      for observer in this.observers.mitems: observer.onNext x
    except:
      this.onError getCurrentException()
proc onError*[T](this: var PublishSubject[T]; x: ref Exception) =
  if this.isInvalid: return
  this.stat.error = x
  if this.hasAnyObservers:
    try:
      for observer in this.observers.mitems: observer.onError x
    except:
      this.onError getCurrentException()
  this.observers.setLen(0)
proc onComplete*[T](this: var PublishSubject[T]) =
  if this.isInvalid: return
  this.stat.isCompleted = true
  if this.hasAnyObservers:
    try:
      for observer in this.observers.mitems: observer.onComplete
    except:
      this.onError getCurrentException()
  this.observers.setLen(0)
{.pop.}

{.push, raises: [].}
proc next*[T](this: var PublishSubject[T]; x: T; xs: varargs[T]) =
  this.onNext x
  for x in xs: this.onNext x
proc error*[T](this: var PublishSubject[T]; x: ref Exception) =
  this.onError x
proc complete*[T](this: var PublishSubject[T]) =
  this.onComplete
{.pop.}


# =================== #
#      Unit Test      #
# =================== #

template test {.used.} =
  suite "Subject - PublishSubject":
    test "concept conversion":
      check PublishSubject[int] is ConceptObserver[int]
      check PublishSubject[int] is ConceptObservable[int]
      check PublishSubject[int] is ConceptSubject[int]
      var subject = PublishSubject[int]()
      discard subject.addr.toAbstractObserver()
      discard subject.addr.toAbstractObservable()

    test "onComplete pattern":
      var subject = PublishSubject[int]()
      var ts: tuple[ n: seq[int]; e: seq[ref Exception]; c: int]

      subject.subscribe(
        (x: int) => (ts.n.add x),
        (x: ref Exception) => (ts.e.add x),
        () => (inc ts.c),
      )

      subject.next 1, 10, 100, 1000
      check ts.n == [1, 10, 100, 1000]

      subject.complete
      check ts.c == 1

      subject.next 1, 10, 100
      check ts.n.len == 4

      subject.complete
      subject.error Exception.newException("test Error")
      check ts.e.len == 0
      check ts.c == 1

      # ++subscription
      reset ts
      subject.subscribe(
        (x: int) => (ts.n.add x),
        (x: ref Exception) => (ts.e.add x),
        () => (inc ts.c),
      )
      check ts.n.len == 0
      check ts.e.len == 0
      check ts.c == 1

    test "onError pattern":
      var subject = PublishSubject[int]()
      var ts: tuple[ n: seq[int]; e: seq[ref Exception]; c: int]
      subject.subscribe(
        (x: int) => (ts.n.add x),
        (x: ref Exception) => (ts.e.add x),
        () => (inc ts.c),
      )

      subject.next 1, 10, 100, 1000
      check ts.n == [1, 10, 100, 1000]

      subject.error Exception.newException("test Error")
      check ts.e.len == 1

      subject.next 1, 10, 100
      check ts.n.len == 4

      subject.complete
      subject.error Exception.newException("test Error")
      check ts.e.len == 1
      check ts.c == 0

      # ++subscription
      reset ts
      subject.subscribe(
        (x: int) => (ts.n.add x),
        (x: ref Exception) => (ts.e.add x),
        () => (inc ts.c),
      )
      check ts.n.len == 0
      check ts.e.len == 1
      check ts.c == 0

    test "subject subscribe":
      var
        subject = PublishSubject[int]()
        listA, listB, listC: seq[int]
      check not subject.hasAnyObservers

      var listASubscription = subject.subscribe (x: int) => listA.add x
      check subject.hasAnyObservers
      subject.next 1
      check (listA[0], listA.len) == (1, 1)

      var listBSubscription = subject.subscribe (x: int) => listB.add x
      check subject.hasAnyObservers
      subject.next 2
      check (listA[1], listA.len) == (2, 2)
      check (listB[0], listB.len) == (2, 1)

      var listCSubscription = subject.subscribe (x: int) => listC.add x
      check subject.hasAnyObservers
      subject.next 3
      check (listA[2], listA.len) == (3, 3)
      check (listB[1], listB.len) == (3, 2)
      check (listC[0], listC.len) == (3, 1)

      consume listASubscription
      check subject.hasAnyObservers
      subject.next 4
      check listA.len == 3
      check listB[2] == 4
      check listC[1] == 4

      consume listCSubscription
      check subject.hasAnyObservers
      subject.next 5
      check listC.len == 2
      check listB[3] == 5

      consume listBSubscription
      check not subject.hasAnyObservers
      subject.next 6
      check listB.len == 4

      var listD, listE: seq[int]

      subject.subscribe (x: int) => listD.add x
      check subject.hasAnyObservers
      subject.next 1
      check listD[0] == 1

      subject.subscribe (x: int) => listE.add x
      check subject.hasAnyObservers
      subject.next 2
      check listD[1] == 2
      check listE[0] == 2

      # TODO
      when false:
        consume subject
        doAssertRaises(Exception): subject.next 0
        doAssertRaises(Exception): subject.error Exception.newException("")
        doAssertRaises(Exception): subject.complete


when isMainModule:
  import unittest
  import sugar
  test