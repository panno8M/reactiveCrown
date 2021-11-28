import unittest
import sugar, strformat, sequtils, strutils
import rx

let testError = Exception.newException "Error"
template nextMsg[T](r: var seq[string]; prefix, suffix: string = ""): auto =
  (v: T) => r.add prefix & $v & suffix
template errorMsg(r: var seq[string]; prefix, suffix: string = ""): auto =
  (e: ref Exception) => r.add prefix & e.msg & suffix
template completeMsg(r: var seq[string]; prefix, suffix: string = ""): auto =
  () => r.add prefix & "#" & suffix
template testObserver[T](r: var seq[string]; prefix, suffix: string = ""): Observer[T] =
  newObserver[T](
    nextMsg[T](r, prefix, suffix),
    errorMsg(r, prefix, suffix),
    completeMsg(r, prefix, suffix),
  )

suite "core":

  test "complex dispose":
    let subject = newPublishSubject[int]()
    var results = newSeq[string]()
    let filter = subject.filter(i => i mod 2 == 1)
    let map = filter.map(i => i.toFloat())
    var disposable = map.subscribe testObserver[float](results)

    subject.next 1
    subject.next 2
    subject.next 3
    consume disposable
    subject.next 4
    var filterDisposable = filter.subscribe testObserver[int](results)
    subject.next 5
    consume filterDisposable
    subject.next 6
    map.subscribe testObserver[float](results)
    map.subscribe testObserver[float](results)
    subject.next 7
    subject.next 8
    subject.next 9


    check results == @[$1f, $3f, $5, $7f, $7f, $9f, $9f]


  test "complex work":
    var results = newSeq[string]()
    let subject = newPublishSubject[int]()
    subject.subscribe testObserver[int](results, prefix = "1:")
    var disposable = subject.subscribe testObserver[int](results, prefix = "2:")

    subject.next 10
    consume disposable
    subject.next 20
    subject.complete
    subject.next 30

    check results == @["1:10", "2:10", "1:20", "1:#"]

suite "observable/operator":
  test "filter  [T](upstream:Observable[T]; op: (T)->bool): Observable[T]":
    var results = newSeq[string]()
    let
      subject = newPublishSubject[int]()
      filter = subject.filter(v => v mod 2 == 1)

    var disposable1 = filter.subscribe testObserver[int](results)

    subject.next 1
    var disposable2 = filter.subscribe testObserver[int](results)
    subject.next 2
    subject.next 3
    consume disposable1
    subject.next 4
    subject.next 5
    consume disposable2
    subject.next 6
    subject.next 7

    check results == @[$1, $3, $3, $5]

  test "map  [T, S](upstream: Observable[T]; op: (T)->S): Observable[S]":
    var results1 = newSeq[string]()
    var results2 = newSeq[string]()
    let
      subject = newPublishSubject[int]()
      map1 = subject.map(v => toFloat(v))
      map2 = subject.map(v => toFloat(v))

    var disposable11 = map1.subscribe testObserver[float](results1)
    subject.next 1
    var disposable21 = map2.subscribe testObserver[float](results2)
    subject.next 2
    var disposable12 = map1.subscribe testObserver[float](results1)
    subject.next 3
    var disposable22 = map2.subscribe testObserver[float](results2)
    subject.next 4
    consume disposable11
    subject.next 5
    consume disposable21
    subject.next 6
    consume disposable12
    subject.next 7
    consume disposable22
    subject.next 8

    check results1 == @[1, 2, 3, 3, 4, 4, 5, 6].mapIt it.float.`$`
    check results2 == @[2, 3, 4, 4, 5, 5, 6, 7].mapIt it.float.`$`

  test "buffer  [T](upstream: Observable[T]; count: Natural; skip: Natural = 0): Observable[seq[T]]":
    var
      results1 = newSeq[string]()
      results2 = newSeq[string]()
    let subject = newPublishSubject[int]()
    subject
      .buffer(3, 1)
      .subscribe testObserver[seq[int]](results1)
    subject
      .buffer(2)
      .subscribe testObserver[seq[int]](results2)

    subject.next 1
    subject.next 2
    subject.next 3
    subject.next 4
    subject.next 5
    subject.next 6

    check results1 == @[$(@[1, 2, 3]), $(@[2, 3, 4]), $(@[3, 4, 5]), $(@[4, 5, 6])]
    check results2 == @[$(@[1, 2]), $(@[3, 4]), $(@[5, 6])]

  test "zip  [Tl, Tr](tl: Observable[Tl]; tr: Observable[Tr]): Observable[(Tl, Tr)]":
    var results = newSeq[string]()
    let
      subject1 = newPublishSubject[int]()
      subject2 = newPublishSubject[float]()
    subject1.zip( <>subject2 )
      .subscribe testObserver[(int, float)](results)

    subject1.next 1
    subject1.next 2
    subject1.next 3
    subject2.next 1f
    subject2.next 2f
    subject2.next 3f

    check results == @[$(1, 1f), $(2, 2f), $(3, 3f)]

  test "zip  [T](upstream: Observable[T]; targets: varargs[Observable[T]]): Observable[seq[T]]":
    var results = newSeq[string]()
    let
      subject1 = newPublishSubject[int]()
      subject2 = newPublishSubject[int]()
      subject3 = newPublishSubject[int]()
    subject1.zip( <>subject2, <>subject3 )
      .subscribe testObserver[seq[int]](results)

    subject1.next 1
    subject1.next 10
    subject2.next 2
    subject3.next 3
    subject2.next 20
    subject2.complete
    subject3.next 30
    subject1.next 100
    subject2.next 200
    subject3.next 300
    subject3.error testError
    subject3.next 3000

    check results == @[$(@[1, 2, 3]), $(@[10, 20, 30]), testError.msg]

  test "concat  [T](upstream: Observable[T]; targets: varargs[Observable[T]]): Observable[T]":
    block:
      var results = newSeq[string]()
      let
        subject1 = newPublishSubject[int]()
        subject2 = newPublishSubject[int]()
        subject3 = newPublishSubject[int]()
        subject4 = newPublishSubject[int]()
      subject1.concat( <>subject2, <>subject3, <>subject4 )
        .subscribe testObserver[int](results)

      subject1.next 1
      subject2.next 10
      subject1.complete

      subject2.next 20
      subject3.complete
      subject2.next 30
      subject2.complete

      subject4.next 100
      subject4.complete

      check results == @[$1, $20, $30, $100, "#"]
    block:
      var results = newSeq[string]()
      let
        sbj1 = newPublishSubject[int]()
        sbj2 = newPublishSubject[int]()
        concat = sbj1.concat( <>sbj2 )
      var
        disp1 = concat.subscribe testObserver[int](results)
        disp2 = concat.subscribe testObserver[int](results)
      concat.subscribe testObserver[int](results)

      sbj1.next 1
      sbj2.next 2
      consume disp1
      sbj1.next 3
      sbj2.next 4
      sbj1.complete
      sbj1.next 5
      sbj2.next 6
      consume disp2
      sbj1.next 7
      sbj2.next 8
      sbj2.complete
      sbj1.next 9
      sbj2.next 10

      check results == @[$1, $1, $1, $3, $3, $6, $6, $8, "#"]

  test "retry  [T](upstream: Observable[T]): Observable[T]":
    echo "\e[34mTODO!\e[m"
    check false
    # var results = newSeq[string]()
    # let subject = newPublishSubject[string]()
    # subject
    #   .map(x => parseInt(x))
    #   .retry()
    #   .subscribe testObserver[int](results)

    # subject.next "10"
    # subject.next "XXX"
    # subject.next "20"

    # check results == @[$10, $20]

suite "observable/factory":

  test "just  [T](v: T): Observable[T]":
    var results = newSeq[string]()
    just(100).subscribe testObserver[int](results)

    check results == @[$100, "#"]


  test "range  [T: Ordinal](start: T; count: Natural): Observable[T]":
    type Tempenum = enum
      alpha, beta, gamma
    var results = newSeq[string]()
    range(alpha, 3).subscribe testObserver[Tempenum](results)
    range('a', 3).subscribe testObserver[char](results)

    check results == @[$alpha, $beta, $gamma, "#", "a", "b", "c", "#"]

  test "repeat  [T](v: T; times: Natural): Observable[T]":
    var results = newSeq[string]()
    rx.just(5).concat(just(10)).repeat(3).subscribe testObserver[int](results)

    check results == [$5, $10, $5, $10, $5, $10, "#"]

suite "Cold->Hot Conversion":
  test "can publish & connect":
    var results = newSeq[string]()
    let r = range(0, 3)
      .map(i => i*2)
      .doThat((v: int) => results.add &"upstream:{v}")
      .publish()
    r.subscribe testObserver[int](results, prefix = "1:")
    r.subscribe testObserver[int](results, prefix = "2:")
    r.connect()

    check results == @[
      "upstream:0", "1:0", "2:0",
      "upstream:2", "1:2", "2:2",
      "upstream:4", "1:4", "2:4",
      "1:#", "2:#",
    ]
  test "can dispose and reconnect the connection":
    var results = newSeq[string]()
    let subject = newPublishSubject[int]()
    let observable = subject
      .map(v => toFloat(v))
      .publish()
    observable.subscribe testObserver[float](results)
    subject.next 1
    subject.next 2
    var disposable = observable.connect()
    subject.next 3
    subject.next 4
    consume disposable
    subject.next 5
    subject.next 6
    observable.connect()
    subject.next 7
    subject.next 8

    check results == @[$3f, $4f, $7f, $8f]

  test "refCount":
    var results1 = newSeq[string]()
    var results2 = newSeq[string]()
    let subject = newPublishSubject[int]()
    let map = subject
      .map(v => toFloat(v))
      .publish()
    let observable1 = map.refCount()
    let observable2 = map.refCount()

    var disposable11 = observable1.subscribe testObserver[float](results1)
    subject.next 1
    var disposable21 = observable2.subscribe testObserver[float](results2)
    subject.next 2
    var disposable12 = observable1.subscribe testObserver[float](results1)
    subject.next 3
    var disposable22 = observable2.subscribe testObserver[float](results2)
    subject.next 4
    consume disposable11
    subject.next 5
    consume disposable21
    subject.next 6
    consume disposable12
    subject.next 7
    consume disposable22
    subject.next 8
    observable1.subscribe testObserver[float](results1)
    subject.next 9

    check results1 == @[1, 2, 3, 3, 4, 4, 5, 6, 9].mapIt it.float.`$`
    check results2 == @[2, 3, 4, 4, 5, 5, 6].mapIt it.float.`$`
