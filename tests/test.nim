import unittest
import sugar, strformat, sequtils
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

  test "complex dispose":
    let subject = newSubject[int]()
    var results = newSeq[string]()
    let where = subject.asObservable.where(i => i mod 2 == 1)
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
    discard subject.asObservable.subscribe testObserver[int](results, prefix = "1:")
    let disposable = subject.asObservable.subscribe testObserver[int](results, prefix = "2:")

    subject.onNext 10
    disposable.dispose()
    subject.onNext 20
    subject.onCompleted()
    subject.onNext 30

    check results == @["1:10", "2:10", "1:20", "1:#"]

suite "observable/operator":
  test "where  [T](upstream:Observable[T]; op: (T)->bool): Observable[T]":
    var results = newSeq[string]()
    let
      subject = newSubject[int]()
      where = subject.asObservable.where(v => v mod 2 == 1)
      disposable1 = where.subscribe testObserver[int](results)

    subject.onNext 1
    let disposable2 = where.subscribe testObserver[int](results)
    subject.onNext 2
    subject.onNext 3
    disposable1.dispose()
    subject.onNext 4
    subject.onNext 5
    disposable2.dispose()
    subject.onNext 6
    subject.onNext 7

    check results == @[$1, $3, $3, $5]

  test "select  [T, S](upstream: Observable[T]; op: (T)->S): Observable[S]":
    var results1 = newSeq[string]()
    var results2 = newSeq[string]()
    let
      subject = newSubject[int]()
      select1 = subject.asObservable.select(v => toFloat(v))
      select2 = subject.asObservable.select(v => toFloat(v))

    let disposable11 = select1.subscribe testObserver[float](results1)
    subject.onNext 1
    let disposable21 = select2.subscribe testObserver[float](results2)
    subject.onNext 2
    let disposable12 = select1.subscribe testObserver[float](results1)
    subject.onNext 3
    let disposable22 = select2.subscribe testObserver[float](results2)
    subject.onNext 4
    disposable11.dispose()
    subject.onNext 5
    disposable21.dispose()
    subject.onNext 6
    disposable12.dispose()
    subject.onNext 7
    disposable22.dispose()
    subject.onNext 8

    check results1 == @[1, 2, 3, 3, 4, 4, 5, 6].mapIt it.float.`$`
    check results2 == @[2, 3, 4, 4, 5, 5, 6, 7].mapIt it.float.`$`

  test "buffer  [T](upstream: Observable[T]; count: Natural; skip: Natural = 0): Observable[seq[T]]":
    var
      results1 = newSeq[string]()
      results2 = newSeq[string]()
    let subject = newSubject[int]()
    discard subject.asObservable
      .buffer(3, 1)
      .subscribe testObserver[seq[int]](results1)
    discard subject.asObservable
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
        subject1.asObservable,
        subject2.asObservable,
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
        subject1.asObservable,
        subject2.asObservable,
        subject3.asObservable,
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
    block:
      var results = newSeq[string]()
      let
        subject1 = newSubject[int]()
        subject2 = newSubject[int]()
        subject3 = newSubject[int]()
        subject4 = newSubject[int]()
      discard concat(
          subject1.asObservable,
          subject2.asObservable,
          subject3.asObservable,
          subject4.asObservable,
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
    block:
      var results = newSeq[string]()
      let
        sbj1 = newSubject[int]()
        sbj2 = newSubject[int]()
        concat = concat(
          sbj1.asObservable,
          sbj2.asObservable,
        )
        disp1 = concat.subscribe testObserver[int](results)
        disp2 = concat.subscribe testObserver[int](results)
      discard concat.subscribe testObserver[int](results)

      sbj1.onNext 1
      sbj2.onNext 2
      disp1.dispose()
      sbj1.onNext 3
      sbj2.onNext 4
      sbj1.onCompleted()
      sbj1.onNext 5
      sbj2.onNext 6
      disp2.dispose()
      sbj1.onNext 7
      sbj2.onNext 8
      sbj2.onCompleted()
      sbj1.onNext 9
      sbj2.onNext 10

      check results == @[$1, $1, $1, $3, $3, $6, $6, $8, "#"]

  test "retry  [T](upstream: Observable[T]): Observable[T]":
    var results = newSeq[string]()
    let subject = newSubject[int]()
    discard subject.asObservable
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
    discard nimRx.repeat(5, 3).subscribe testObserver[int](results)

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
    discard r.asObservable.subscribe testObserver[int](results, prefix = "1:")
    discard r.asObservable.subscribe testObserver[int](results, prefix = "2:")
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
    let observable = subject.asObservable
      .select(v => toFloat(v))
      .publish()
    discard observable.asObservable.subscribe testObserver[float](results)
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

  test "refCount":
    var results1 = newSeq[string]()
    var results2 = newSeq[string]()
    let subject = newSubject[int]()
    let select = subject.asObservable
      .select(v => toFloat(v))
      .publish()
    let observable1 = select
      .refCount()
    let observable2 = select
      .refCount()

    let disposable11 = observable1.subscribe testObserver[float](results1)
    subject.onNext 1
    let disposable21 = observable2.subscribe testObserver[float](results2)
    subject.onNext 2
    let disposable12 = observable1.subscribe testObserver[float](results1)
    subject.onNext 3
    let disposable22 = observable2.subscribe testObserver[float](results2)
    subject.onNext 4
    disposable11.dispose()
    subject.onNext 5
    disposable21.dispose()
    subject.onNext 6
    disposable12.dispose()
    subject.onNext 7
    disposable22.dispose()
    subject.onNext 8
    discard observable1.subscribe testObserver[float](results1)
    subject.onNext 9

    check results1 == @[1, 2, 3, 3, 4, 4, 5, 6, 9].mapIt it.float.`$`
    check results2 == @[2, 3, 4, 4, 5, 5, 6].mapIt it.float.`$`
