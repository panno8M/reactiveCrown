import unittest
import sugar, strformat
import nimRx

let testError = newError "Error"
template onNextMsg[T](r: var seq[string];
    prefix, suffix: string = ""): proc(v: T) =
  ((v: T) => r.add prefix & $v & suffix)
template onErrorMsg(r: var seq[string];
    prefix, suffix: string = ""): (Error->void) =
  ((e: Error) => r.add prefix & $e & suffix)
template onCompletedMsg(r: var seq[string];
    prefix, suffix: string = ""): (()->void) =
  (() => r.add prefix & "#" & suffix)
template testObserver[T](r: var seq[string];
    prefix, suffix: string = ""): Observer[T] = newObserver[T](
 onNextMsg[T](r, prefix, suffix),
 onErrorMsg(r, prefix, suffix),
 onCompletedMsg(r, prefix, suffix),
)

suite "core":
  test "observer: can create and call onNext, onError, onCompleted":
    var results = newSeq[string]()
    proc onm(v: int): string = &"onNext({v})"
    proc oem(v: Error): string = &"onError({v})"
    const ocm = "#"
    proc on(v: int): void = results.add onm(v)
    proc oe(e: Error): void = results.add oem(e)
    proc oc(): void = results.add ocm
    let
      observer1 = newObserver[int](on, oe, oc)
      observer2 = newObserver[int](on, oe)
      observer3 = newObserver[int](on)

    observer1.onNext 1
    observer1.onError newError("2")
    observer1.onCompleted()
    observer2.onNext 3
    observer2.onError newError("4")
    observer2.onCompleted()
    observer3.onNext 5
    observer3.onError newError("6")
    observer3.onCompleted()

    check results == @[
        1.onm,
        newError("2").oem,
        ocm,
        3.onm,
        newError("4").oem,
        5.onm,
      ]


  test "disposable: can create and dispose":
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

  test "complex dispose":
    let subject = newSubject[int]()
    var results = newSeq[string]()
    let where = subject.observable.where(i => i mod 2 == 1)
    let select = where.select(i => i.toFloat())
    let disposable = select.subscribe testObserver[float](results)

    subject.onNext 1
    subject.onNext 2
    subject.onNext 3
    disposable.dispose()
    subject.onNext 4
    let whereDisposable = where.subscribe testObserver[int](results)
    subject.onNext 5
    whereDisposable.dispose()
    subject.onNext 6
    discard select.subscribe testObserver[float](results)
    discard select.subscribe testObserver[float](results)
    subject.onNext 7
    subject.onNext 8
    subject.onNext 9


    check results == @[$1f, $3f, $5, $7f, $7f, $9f, $9f]


  test "complex work":
    var results = newSeq[string]()
    let subject = newSubject[int]()
    discard subject.subscribe testObserver[int](results, prefix = "1:")
    let disposable = subject.subscribe testObserver[int](results, prefix = "2:")

    subject.onNext 10
    disposable.dispose()
    subject.onNext 20
    subject.onCompleted()
    subject.onNext 30

    check results == @["1:10", "2:10", "1:20", "1:#"]

suite "observable/operator":
  test "where":
    var results = newSeq[string]()
    let subject = newSubject[int]()
    discard subject.observable
      .where(v => v != 2)
      .subscribe testObserver[int](results)

    subject.onNext 1
    subject.onNext 2
    subject.onNext 3

    check results == @[$1, $3]

  test "select  [T, S](upstream: Observable[T]; op: (T)->S): Observable[S]":
    var results = newSeq[string]()
    let subject = newSubject[int]()
    discard subject.observable
      .select(v => toFloat(v*v))
      .subscribe testObserver[float](results)

    subject.onNext 1
    subject.onNext 2
    subject.onNext 3

    check results == @[$1f, $4f, $9f]

  test "buffer  [T](upstream: Observable[T]; count: Natural; skip: Natural = 0): Observable[seq[T]]":
    var
      results1 = newSeq[string]()
      results2 = newSeq[string]()
    let subject = newSubject[int]()
    discard subject.observable
      .buffer(3, 1)
      .subscribe testObserver[seq[int]](results1)
    discard subject.observable
      .buffer(2)
      .subscribe testObserver[seq[int]](results2)

    subject.onNext 1
    subject.onNext 2
    subject.onNext 3
    subject.onNext 4
    subject.onNext 5
    subject.onNext 6

    check results1 == @[$(@[1, 2, 3]), $(@[2, 3, 4]), $(@[3, 4, 5]), $(@[4, 5, 6])]
    check results2 == @[$(@[1, 2]), $(@[3, 4]), $(@[5, 6])]

  test "zip  [Tl, Tr](tl: Observable[Tl]; tr: Observable[Tr]): Observable[tuple[l: Tl; r: Tr]]":
    var results = newSeq[string]()
    let
      subject1 = newSubject[int]()
      subject2 = newSubject[float]()
    discard zip(
        subject1.observable,
        subject2.observable,
      )
      .subscribe testObserver[tuple[l: int; r: float]](results)

    subject1.onNext 1
    subject1.onNext 2
    subject1.onNext 3
    subject2.onNext 1f
    subject2.onNext 2f
    subject2.onNext 3f

    check results == @[$(l: 1, r: 1f), $(l: 2, r: 2f), $(l: 3, r: 3f)]

  test "zip  [T](upstream: Observable[T]; targets: varargs[Observable[T]]): Observable[seq[T]]":
    var results = newSeq[string]()
    let
      subject1 = newSubject[int]()
      subject2 = newSubject[int]()
      subject3 = newSubject[int]()
    discard zip(
        subject1.observable,
        subject2.observable,
        subject3.observable,
      )
      .subscribe testObserver[seq[int]](results)

    subject1.onNext 1
    subject1.onNext 10
    subject2.onNext 2
    subject3.onNext 3
    subject2.onNext 20
    subject2.onCompleted()
    subject3.onNext 30
    subject1.onNext 100
    subject2.onNext 200
    subject3.onNext 300
    subject3.onError testError
    subject3.onNext 3000

    check results == @[$(@[1, 2, 3]), $(@[10, 20, 30]), $testError]

  test "concat  [T](upstream: Observable[T]; targets: varargs[Observable[T]]): Observable[T]":
    var results = newSeq[string]()
    let
      subject1 = newSubject[int]()
      subject2 = newSubject[int]()
      subject3 = newSubject[int]()
      subject4 = newSubject[int]()
    discard concat(
        subject1.observable,
        subject2.observable,
        subject3.observable,
        subject4.observable,
      )
      .subscribe testObserver[int](results)

    subject1.onNext 1
    subject2.onNext 10
    subject1.onNext 2
    subject1.onCompleted()

    subject2.onNext 3
    subject3.onCompleted()
    subject2.onNext 4
    subject2.onCompleted()

    subject4.onNext 5
    subject4.onNext 6
    subject4.onCompleted()

    check results == @[$1, $2, $3, $4, $5, $6, "#"]

  test "retry  [T](upstream: Observable[T]): Observable[T]":
    var results = newSeq[string]()
    let subject = newSubject[int]()
    discard subject.observable
      .retry()
      .subscribe testObserver[int](results)

    subject.onNext 10
    subject.onError newError("Error")
    subject.onNext 20

    check results == @[$10, $20]

suite "observable/factory":

  test "returnThat  [T](v: T): Observable[T]":
    var results = newSeq[string]()
    discard returnThat(100).subscribe testObserver[int](results)

    check results == @[$100, "#"]

  test "repeat  [T](v: T; times: Natural): Observable[T]":
    var results = newSeq[string]()
    discard repeat(5, 3).subscribe testObserver[int](results)

    check results == @[$5, $5, $5, "#"]

  test "range  [T: Ordinal](start: T; count: Natural): Observable[T]":
    type Tempenum = enum
      alpha, beta, gamma
    var results = newSeq[string]()
    discard range(alpha, 3).subscribe testObserver[Tempenum](results)
    discard range('a', 3).subscribe testObserver[char](results)

    check results == @[$alpha, $beta, $gamma, "#", "a", "b", "c", "#"]

suite "Cold->Hot Conversion":
  test "can publish & connect":
    var results = newSeq[string]()
    let r = range(0, 3)
      .select(i => i*2)
      .doThat((v: int) => results.add &"upstream:{v}")
      .publish()
    discard r.subscribe testObserver[int](results, prefix = "1:")
    discard r.subscribe testObserver[int](results, prefix = "2:")
    discard r.connect()

    check results == @[
      "upstream:0", "1:0", "2:0",
      "upstream:2", "1:2", "2:2",
      "upstream:4", "1:4", "2:4",
      "1:#", "2:#",
    ]
  test "can dispose and reconnect the connection":
    var results = newSeq[string]()
    let subject = newSubject[int]()
    let observable = subject.observable
      .select(v => toFloat(v))
      .publish()
    discard observable.subscribe testObserver[float](results)
    subject.onNext 1
    subject.onNext 2
    let disposable = observable.connect()
    subject.onNext 3
    subject.onNext 4
    disposable.dispose()
    subject.onNext 5
    subject.onNext 6
    discard observable.connect()
    subject.onNext 7
    subject.onNext 8

    check results == @[$3f, $4f, $7f, $8f]
