# Cording Convention
#
# Since the chain does not continue from the following functions, 
# the parentheses should be omitted and the description should be procedural:
# * Observer[T].next val
# * Observer[T].error err
# * Observer[T].complete
# * IObservable[T].subscribe observer
#
# IObservable[T].subscribe(
#   (v: T) => doSomething(),
#   (e: Error) => (doSomething(); doOtherThing()),
#   (proc(v: T) =
#     doSomething()
#     doSomething()
#     doSomething()
#   ),
# )

{.experimental: "strictFuncs".}

import sugar
import sequtils

# rx
import core
import subjects



# SECTION Utilities

template construct_whenSubscribed*[T](mkObservable: untyped): untyped =
  Observable[T](onSubscribe: proc(ober: Observer[T]): Disposable =
    (() => mkObservable)().subscribe ober
  )

# Indicate whether operator perform a special behavior.
template next_default[T](observer: Observer[T]): (proc(v: T) {.closure.}) =
  (v: T) => observer.next(v)
template error_default[T](observer: Observer[T]): (proc(e: ref Exception) {.closure.}) =
  (e: ref Exception) => observer.error(e)
template complete_default[T](observer: Observer[T]): (proc() {.closure.}) =
  () => observer.complete

# !SECTION

# SECTION Creating

func just*[T](v: T): Observable[T] =
  ## "[Just](http://reactivex.io/documentation/operators/just.html)" from ReactiveX
  runnableExamples:
    import rx
    import sugar

    var
      res: int
      isCompleted: bool

    just(10)
      .subscribe(
        next = (x: int) => (res = x),
        complete = () => (isCompleted = true))

    assert res == 10
    assert isCompleted

  construct_whenSubscribed[T]:
    let retObservable = new Observable[T]
    retObservable.onSubscribe = proc(observer: Observer[T]): Disposable =
      observer.next v
      observer.complete
      var sbsc = newSubscription(retObservable, observer)
      sbsc.toDisposable
    return retObservable


func range*[T: Ordinal](start: T; count: Natural): Observable[T] =
  ## "[Range](http://reactivex.io/documentation/operators/range.html)" from ReactiveX
  runnableExamples:
    import rx
    import sugar

    var
      res: int
      isCompleted: bool

    range(1, 4)
      .subscribe(
        next = (x: int) => (res += x),
        complete = () => (isCompleted = true),
      )

    assert res == 10
    assert isCompleted

  construct_whenSubscribed[T]:
    let retObservable = new Observable[T]
    retObservable.onSubscribe = proc(observer: Observer[T]): Disposable =
      for i in 0..<count:
        observer.next start.succ(i)
      observer.complete
      newSubscription(retObservable, observer)
    return retObservable

func repeat*[T](upstream: Observable[T]): Observable[T] =
  ## | "[Repeat](http://reactivex.io/documentation/operators/repeat.html)" from ReactiveX
  # TODO: To write runnable examples, need to implement take** operators.
  # I thought about separating infinite and finite into different functions,
  # but in any case, the finite version changes the process depending on
  # whether times is zero or not. Then I thought it would be cleaner to combine them.
  construct_whenSubscribed[T]:
    proc mkRepeatObserver(observer: Observer[T]): Observer[T] =
      return newObserver[T](
        observer.next_default,
        observer.error_default,
        proc() = upstream.subscribe observer.mkRepeatObserver()
      )
    newObservable[T] proc(observer: Observer[T]): Disposable =
      return upstream.subscribe observer.mkRepeatObserver()

func repeat*[T](upstream: Observable[T]; times: Natural): Observable[T] =
  ## | "[Repeat](http://reactivex.io/documentation/operators/repeat.html)" from ReactiveX
  # TODO: To write runnable examples, need to implement take** operators.
  # I thought about separating infinite and finite into different functions,
  # but in any case, the finite version changes the process depending on
  # whether times is zero or not. Then I thought it would be cleaner to combine them.

  if times == 0:
    return construct_whenSubscribed[T]:
      newObservable[T] proc(observer: Observer[T]): Disposable =
        upstream.subscribe(
          (v: T) => observer.complete,
          (e: ref Exception) => observer.error e,
          () => observer.complete,
        )

  construct_whenSubscribed[T]:
    var stat: Natural = times
    proc mkRepeatObserver(observer: Observer[T]): Observer[T] =
      return newObserver[T](
        observer.next_default,
        observer.error_default,
        proc() =
        case stat:
          of 1: # End point.
            observer.complete
          else:
            dec stat
            upstream.subscribe observer.mkRepeatObserver()
      )
    newObservable[T] proc(observer: Observer[T]): Disposable =
      return upstream.subscribe observer.mkRepeatObserver()

# !SECTION

# SECTION Transforming

func buffer*[T](upstream: Observable[T]; timeSpan: Natural; skip: Natural = 0):
                                                                Observable[seq[T]] =
  ## "[Buffer](http://reactivex.io/documentation/operators/buffer.html)" from ReactiveX
  runnableExamples:
    import rx
    import sugar

    var res = newSeq[int]()

    range(0, 5)
      .buffer(2, 1)
      .filter(x => x.len == 2) # If "buffer" reciexed complete exent, it will flush stored xalues 
                              # whether it has enough length or not.
      .map(x => x[0]*x[1])
      .subscribe((x: int) => (res.add x))

    doAssert res == @[0*1, 1*2, 2*3, 3*4]
  runnableExamples:
    import rx
    import sugar

    var res = newSeq[int]()

    range(0, 6)
      .buffer(3)
      .filter(x => x.len == 3)
      .map(x => x[0] + x[1] + x[2])
      .subscribe((x: int) => (res.add x))

    doAssert res == @[3, 12]

  let skip = if skip == 0: timeSpan else: skip
  type S = seq[T]
  construct_whenSubscribed[S]:
    var cache = newSeq[T]()
    newObservable[S] proc(observer: Observer[S]): Disposable =
      upstream.subscribe(
        (proc(v: T) =
          cache.add v
          if cache.len == timeSpan:
            observer.next cache
            cache = cache[skip..cache.high]
        ),
        observer.error_default,
        (proc() =
          if cache.len != 0: observer.next cache
          observer.complete
        ),
      )

func map*[T, S](upstream: Observable[T]; op: (T)->S): Observable[S] =
  ## "[Map](http://reactivex.io/documentation/operators/map.html)" from ReactiveX
  runnableExamples:
    import rx
    import sugar

    var res = newSeq[int]()
    let sbj = newPublishSubject[int]()
    sbj
      .map(x => x*10)
      .subscribe((x: int) => (res.add x))
    sbj.next 1
    sbj.next 2
    sbj.next 3

    doAssert res == @[10, 20, 30]

  construct_whenSubscribed[S]:
    newObservable[S] proc(observer: Observer[S]): Disposable =
      upstream.subscribe(
        (v: T) => observer.next op(v),
        observer.error_default,
        observer.complete_default,
      )

#!SECTION

# SECTION Filtering

func filter*[T](upstream: Observable[T]; op: (T)->bool): Observable[T] =
  ## "[Filter](http://reactivex.io/documentation/operators/filter.html)" from ReactiveX
  runnableExamples:
    import rx
    import sugar

    var res = newSeq[int]()
    let sbj = newPublishSubject[int]()
    sbj
      .filter(x => x > 10)
      .subscribe((x: int) => (res.add x))
    sbj.next 2
    sbj.next 30
    sbj.next 22
    sbj.next 5
    sbj.next 60
    sbj.next 1

    doAssert res == @[30, 22, 60]

  construct_whenSubscribed[T]:
    newObservable[T] proc(observer: Observer[T]): Disposable =
      upstream.subscribe(
        (v: T) => (if op(v): observer.next v),
        observer.error_default,
        observer.complete_default,
      )

# !SECTION

# SECTION Combining

func zip*[Tl, Tr](tl: Observable[Tl]; tr: Observable[Tr]):
                                                  Observable[(Tl, Tr)] =
  ## "[Zip](http://reactivex.io/documentation/operators/zip.html)" from ReactiveX
  runnableExamples:
    import rx
    import sugar, strformat

    var res = newSeq[string]()
    let sbj1 = newPublishSubject[int]()
    let sbj2 = newPublishSubject[char]()
    sbj1.zip( <>sbj2 )
      .subscribe((v: (int, char)) => res.add &"{v[0]}{v[1]}")
    sbj1.next 1
    sbj2.next 'A'
    sbj1.next 2
    sbj2.next 'B'
    sbj2.next 'C'
    sbj2.next 'D'
    sbj1.next 3
    sbj1.next 4
    sbj1.next 5

    doAssert res == @["1A", "2B", "3C", "4D"]

  type S = (Tl, Tr)
  construct_whenSubscribed[S]:
    var cache: tuple[l: seq[Tl]; r: seq[Tr]] = (newSeq[Tl](), newSeq[Tr]())
    proc tryOnNext(observer: Observer[S]) =
      if cache.l.len != 0 and cache.r.len != 0:
        observer.next (cache.l[0], cache.r[0])
        cache.l = cache.l[1..cache.l.high]
        cache.r = cache.r[1..cache.r.high]
    newObservable[S] proc(observer: Observer[S]): Disposable =
      var disp1 = tl.subscribe(
        (v: Tl) => (cache.l.add v; observer.tryOnNext()),
        observer.error_default,
      )
      var disp2 = tr.subscribe(
        (v: Tr) => (cache.r.add v; observer.tryOnNext()),
        observer.error_default,
      )
      bandle @[disp1.addr, disp2.addr]

proc zip*[T](upstream: Observable[T]; targets: varargs[Observable[T]]):
                                                              Observable[seq[T]] =
  ## "[Zip](http://reactivex.io/documentation/operators/zip.html)" from ReactiveX
  runnableExamples:
    import rx
    import sugar, strformat

    var res = newSeq[string]()
    let
      sbj1 = newPublishSubject[char]()
      sbj2 = newPublishSubject[char]()
      sbj3 = newPublishSubject[char]()
    sbj1.zip( <>sbj2, <>sbj3 )
      .subscribe((x: seq[char]) => res.add &"{x[0]}{x[1]}{x[2]}")
    sbj1.next '1'
    sbj2.next 'a'
    sbj1.next '2'
    sbj3.next 'A'
    sbj2.next 'b'
    sbj1.next '3'
    sbj3.next 'B'
    sbj3.next 'C'

    doAssert res == @["1aA", "2bB"]

  let targets = concat(@[upstream], @targets)
  type S = seq[T]
  construct_whenSubscribed[S]:
    var cache = newSeqWith(targets.len, newSeq[T]())
    # Is this statement put directly in the for statement on onSubscribe,
    # the values from all obles will go into cache[seq.high].
    proc trySubscribe(target: tuple[oble: Observable[T]; i: int];
        observer: Observer[S]): Disposable =
      target.oble.subscribe(
        (proc(v: T) =
          cache[target.i].add(v)
          if cache.filterIt(it.len == 0).len == 0:
            observer.next cache.mapIt(it[0])
            cache = cache.mapIt(it[1..it.high])
        ),
        observer.error_default,
      )
    newObservable[S] proc(observer: Observer[S]): Disposable =
      var disps = newSeq[ptr Disposable](targets.len)
      for i, target in targets:
        var x = (target, i).trySubscribe(observer)
        disps[i] = x.addr
      disps.bandle

# !SECTION

# SECTION Error handling

func retry*[T](upstream: Observable[T]): Observable[T] =
  ## "[Retry](http://reactivex.io/documentation/operators/retry.html)" from ReactiveX
  # TODO: To write runnable examples, needs to implement replaySubject.
  construct_whenSubscribed[T]:
    var disposable: Disposable
    func mkRetryObserver(observer: Observer[T]): Observer[T] =
      return newObserver[T](
        observer.next_default,
        (proc(e: ref Exception) =
          disposable.tryConsume()
          disposable = upstream.subscribe observer.mkRetryObserver()
        ),
        observer.complete_default,
      )
    newObservable[T] proc(observer: Observer[T]): Disposable =
      disposable = upstream.subscribe observer.mkRetryObserver()

# !SECTION

# SECTION Mathematical and Aggregate
proc concat*[T](upstream: Observable[T]; targets: varargs[Observable[T]]):
                                                                Observable[T] =
  ## "[Concat](http://reactivex.io/documentation/operators/concat.html)" from ReactiveX
  runnableExamples:
    import rx
    import sugar

    var res = newSeq[int]()
    let
      sbj1 = newPublishSubject[int]()
      sbj2 = newPublishSubject[int]()
    sbj1.concat( <>sbj2 )
      .subscribe(
        next = (x: int) => res.add x,
        complete = () => res.add 0)
    sbj1.next 1
    sbj2.next 2
    sbj1.next 1
    sbj1.complete
    sbj2.next 2
    sbj2.complete

    doAssert res == @[1, 1, 2, 0]

  let targets = @targets
  construct_whenSubscribed[T]:
    var
      i_target = 0
      retDisp: Disposable
    proc nextTarget(): Observable[T] =
      result = targets[i_target]
      inc i_target
    proc mkConcatObserver(observer: Observer[T]): Observer[T] =
      newObserver[T](
        observer.next_default,
        observer.error_default,
        if i_target < targets.len:
          (proc() = retDisp = nextTarget().subscribe observer.mkConcatObserver())
        else:
          observer.complete_default
      )
    newObservable[T] proc(observer: Observer[T]): Disposable =
      retDisp = upstream.subscribe observer.mkConcatObserver()
      Disposable.issue:
        consume retDisp

# !SECTION

# SECTION Cold -> Hot converter

type ConnectableObservable[T] = ref object
  subject: Subject[T]
  upstream: Observable[T]
  cacheDisp: Disposable
converter toObservable*[T](self: ConnectableObservable[T]): Observable[T] = self.subject
template `<>`*[T](self: ConnectableObservable[T]): Observable[T] = self.toObservable
func publish*[T](upstream: Observable[T]): ConnectableObservable[T] =
  runnableExamples:
    import rx
    import rx/unitUtils
    import sugar

    var cntCalled: int
    let
      sbj = newPublishSubject[Unit]()
      published = sbj
        .doThat((_: Unit) => (inc cntCalled))
        .publish()

    sbj.next()
    assert cntCalled == 0

    published
      .subscribeBlock:
        discard

    sbj.next()
    assert cntCalled == 0

    let disconnectable = published.connect()

    sbj.next()
    assert cntCalled == 1

    published
      .subscribeBlock:
        discard

    sbj.next()
    assert cntCalled == 2

    disconnectable.dispose()

    sbj.next()
    assert cntCalled == 2

  ConnectableObservable[T](
    subject: newPublishSubject[T](),
    upstream: upstream,
  )

proc connect*[T](self: ConnectableObservable[T]): Disposable {.discardable.} =
  ## See `publish proc<#publish,IObservable[T]>`_ for examples.
  # Do nothing when already connected between "publish subject" to its upstream
  if self.cacheDisp.isInvalid:
    var dispSbsc = self.upstream.subscribe(
      (v: T) => self.subject.next v,
      (e: ref Exception) => self.subject.error e,
      () => self.subject.complete,
    )
    self.cacheDisp = Disposable.issue:
      consume dispSbsc
  return self.cacheDisp

func refCount*[T](upstream: ConnectableObservable[T]): Observable[T] =
  ## NOTE: There is something wrong with this behavior.
  ## Be careful when use it.
  var
    cntSubscribed = 0
    dispConnect: Disposable
  newObservable[T] proc(observer: Observer[T]): Disposable =
    var dispSubscribe = upstream.subscribe observer
    inc cntSubscribed
    if cntSubscribed == 1:
      dispConnect = upstream.connect()
    return Disposable.issue:
      if cntSubscribed > 0:
        dec cntSubscribed
        if cntSubscribed == 0:
          tryConsume dispConnect
      consume dispSubscribe

func share*[T](upstream: Observable[T]): Observable[T] =
  upstream.publish().refCount()

# !SECTION

# SECTION Value dump

func doThat*[T](upstream: Observable[T]; op: (T)->void): Observable[T] =
  construct_whenSubscribed[T]:
    newObservable[T] proc(observer: Observer[T]): Disposable =
      upstream.subscribe(
        (v: T) => (op(v); observer.next v),
        observer.error_default,
        observer.complete_default,
      )

func dump*[T](upstream: Observable[T]): Observable[T] =
  template log(action: untyped): untyped = debugEcho "[DUMP] ", action
  construct_whenSubscribed[T]:
    newObservable[T] proc(observer: Observer[T]): Disposable =
      upstream.subscribe(
        (v: T) => (log v; observer.next v),
        (e: ref Exception) => (log e; observer.error e),
        () => (log "complete!"; observer.complete),
      )

# !SECTION
