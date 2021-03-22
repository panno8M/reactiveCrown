import unittest
import nimRx

suite "core":
  suite "observer":
    test "can create and call onNext, onError, onCompleted":
      var results = newSeq[string]()
      proc onm(v: int): string = "onNext(" & $v & ")"
      proc oem(v: Error): string = "onError(" & $v & ")"
      const ocm = "onCompleted()"
      proc on(v: int): void = results.add(onm v)
      proc oe(e: Error): void = results.add(oem e)
      proc oc(): void = results.add(ocm)
      let
        observer1 = newObserver[int](on, oe, oc)
        observer2 = newObserver[int](on, oe)
        observer3 = newObserver[int](on)

      observer1.onNext(1)
      observer1.onError(newError("2"))
      observer1.onCompleted()
      observer2.onNext(3)
      observer2.onError(newError("4"))
      observer2.onCompleted()
      observer3.onNext(5)
      observer3.onError(newError("6"))
      observer3.onCompleted()

      check results == @[
          1.onm,
          "2".newError.oem,
          ocm,
          3.onm,
          "4".newError.oem,
          5.onm]
  suite "observable":
    test "can create and call onSubscribe":
      var results = newSeq[string]()
      const osm = "onSubscribe()"
      proc os[T](v: Observer[T]): void = results.add(osm)
      proc doNothing[T](v: T): void = discard
      let
        observable1 = newObservable[int](os)
        observable2 = newObservable[int]()

      observable1.onSubscribe(newObserver[int](doNothing))
      observable2.onSubscribe(newObserver[int](doNothing))
      check results == @[osm]

  suite "disposable":
    test "can create and dispose":
      proc doNothing[T](v: T): void = discard
      let
        observable = newObservable[int]()
        target = newObserver[int](doNothing)
      observable.observers.add target
      let
        disposable = newDisposable[int](observable, target)
      check observable.observers.len == 1
      disposable.dispose()
      check observable.observers.len == 0

  test "complex work":
    var results = newSeq[string]()
    let subject = newSubject[int]()
    discard subject.subscribe(
      onNext = (proc(v: int): void = results.add "1:" & $v),
      onError = (proc(e: Error): void = results.add "1:" & $e),
      onCompleted = (proc(): void = results.add "1:" & $true)
    )
    let disposable = subject.subscribe(
      onNext = (proc(v: int): void = results.add "2:" & $v),
      onError = (proc(e: Error): void = results.add "2:" & $e),
      onCompleted = (proc(): void = results.add "2:" & $true)
    )

    subject.onNext(10)
    disposable.dispose()
    subject.onNext(20)
    subject.onCompleted()
    subject.onNext(30)

    check results ==
        @["1:10", "2:10", "1:20", "1:true"]

  suite "operators":
    test "retry":
      var results = newSeq[string]()
      let subject = newSubject[int]()
      discard subject.observable.retry().subscribe(
        onNext = proc(v: int): void = results.add($v),
        onError = proc(e: Error): void = results.add($e),
        onCompleted = proc(): void = results.add($true))

      subject.onNext(10)
      subject.onError(newError("Error"))
      subject.onNext(20)

      check results == @["10", "20"]

    test "select":
      var results = newSeq[string]()
      let subject = newSubject[int]()
      discard subject.observable
        .select(proc(v: int): float = toFloat(v * v))
        .subscribe(
          onNext = proc(v: float): void = results.add($v),
          onError = proc(e: Error): void = results.add($e),
          onCompleted = proc(): void = results.add($true))

      subject.onNext(1)
      subject.onNext(2)
      subject.onNext(3)

      check results == @[$1.0f, $4.0f, $9.0f]

    test "buffer":
      var results1 = newSeq[string]()
      var results2 = newSeq[string]()
      let subject = newSubject[int]()
      discard subject.observable
        .buffer(3, 1)
        .subscribe(
          onNext = proc(v: seq[int]): void = results1.add($v),
          onError = proc(e: Error): void = results1.add($e),
          onCompleted = proc(): void = results1.add($true))
      discard subject.observable
        .buffer(2)
        .subscribe(
          onNext = proc(v: seq[int]): void = results2.add($v),
          onError = proc(e: Error): void = results2.add($e),
          onCompleted = proc(): void = results2.add($true))

      subject.onNext(1)
      subject.onNext(2)
      subject.onNext(3)
      subject.onNext(4)
      subject.onNext(5)
      subject.onNext(6)

      check results1 == @[$(@[1, 2, 3]), $(@[2, 3, 4]), $(@[3, 4, 5]), $(@[4, 5, 6])]
      check results2 == @[$(@[1, 2]), $(@[3, 4]), $(@[5, 6])]

    test "zip":
      var results = newSeq[string]()
      let
        subject1 = newSubject[int]()
        subject2 = newSubject[float]()
      discard zip(subject1.observable, subject2.observable).subscribe(
        onNext = (proc(v: tuple[l: int; r: float]) = results.add($v)),
        onError = proc(e: Error): void = results.add($e),
        onCompleted = proc(): void = results.add($true))

      subject1.onNext(1)
      subject1.onNext(2)
      subject1.onNext(3)
      subject2.onNext(1f)
      subject2.onNext(2f)
      subject2.onNext(3f)

      check results == @[$(l: 1, r: 1f), $(l: 2, r: 2f), $(l: 3, r: 3f)]

    test "concat":
      var results = newSeq[string]()
      let
        subject1 = newSubject[int]()
        subject2 = newSubject[int]()
        subject3 = newSubject[int]()
        subject4 = newSubject[int]()
      discard subject1.observable
        .concat(subject2.observable, subject3.observable, subject4.observable)
        .subscribe(
          onNext = proc(v: int): void = results.add($v),
          onError = proc(e: Error): void = results.add($e),
          onCompleted = proc(): void = results.add($true))

      subject1.onNext(1)
      subject2.onNext(10)
      subject1.onNext(2)
      subject1.onCompleted()

      subject2.onNext(3)
      subject3.onCompleted()
      subject2.onNext(4)
      subject2.onCompleted()

      subject4.onNext(5)
      subject4.onNext(6)
      subject4.onCompleted()

      check results == @["1", "2", "3", "4", "5", "6", "true"]
    test "repeat":
      var results = newSeq[string]()
      discard repeat(5, 3).subscribe(
        onNext = proc(v: int): void = results.add($v),
        onError = proc(e: Error): void = results.add($e),
        onCompleted = proc(): void = results.add($true))

      check results == @["5", "5", "5", "true"]
