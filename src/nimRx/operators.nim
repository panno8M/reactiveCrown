# Cording Convention
#
# Since the chain does not continue from the following functions, 
# the parentheses should be omitted and the description should be procedural:
# * Observer[T].onNext val
# * Observer[T].onError err
# * Observer[T].onCompleted()
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

import sugar
import sequtils

# nimRx
import core
import subjects



# Utilities SECTION

template blueprint*[T](mkObservable: untyped): untyped =
  ## | It is published in order to be enable to implement your operator by yourself.
  ## | Therefore, it is **NOT** necessary for statements that use the library normally.
  ## | For example, where operator is implemented as follows:
  ##
  ## .. code-block:: Nim
  ##    proc where*[T](upstream: IObservable[T]; op: (T)->bool): IObservable[T] =
  ##      blueprint[T]:
  ##        newIObservable[T] proc(observer: Observer[T]): IDisposable =
  ##          upstream.subscribe(
  ##            (v: T) => (if op(v): observer.onNext v),
  ##            (e: Error) => observer.onError e,
  ##            () => observer.onCompleted(),
  ##          )
  ##
  ## It may seem that this can be written as follows
  ## by excluding the blueprint[T] statement:
  ##
  ## .. code-block:: Nim
  ##    proc where*[T](upstream: IObservable[T]; op: (T)->bool): IObservable[T] =
  ##      newIObservable[T] proc(observer: Observer[T]): IDisposable =
  ##        upstream.subscribe(
  ##          (v: T) => (if op(v): observer.onNext v),
  ##          (e: Error) => observer.onError e,
  ##          () => observer.onCompleted(),
  ##        )
  ##
  ## The difference between the two is when you assign to a variable once
  ## and try to subscribe multiple times, i.e.
  ##
  ## .. code-block:: Nim
  ##    let
  ##      sbj = newSubject[int]()
  ##      obsEven = sbj.asObservable().where(v => v mod 2 == 0)
  ##    discard obsEven.subscribe((v: int) => echo "sbsc #1: " & $v)
  ##    discard obsEven.subscribe((v: int) => echo "sbsc #2: " & $v)
  ##
  ## | In this case, if blueprint is not used, the IObservable will be created when it is assigned to the variable, and the two subsequent subscriptions will be done to the same IObservable.
  ## | In contrast, when blueprint is used, the IObservable is created for the first time when subscribing. In other words, the first subscribe creates an IObservable that is the entity of the where observable, and the next subscribe creates a new IObservable.
  ## | This behavior is exactly like a cold observable. This behavior is also the reason for the name blueprint. In other words, when implementing a cold observable, it works well to use blueprint to implement it. On the other hand, it is not necessary when implementing a hot observable.
  IObservable[T](onSubscribe: proc(ober: Observer[T]): IDisposable =
    (() => mkObservable)().subscribe ober
  )

template combineDisposables(disps: varargs[IDisposable]): IDisposable =
  IDisposable(dispose: () => @disps.apply((it: IDisposable) => it.dispose()))



# Factories SECTION

proc returnThat*[T](v: T): IObservable[T] =
  ## The moment it is subscribed(), it issues onNext() once
  ## with the passed arguments, and immediately issues onCompleted() to finish.
  runnableExamples:
    import nimRx
    import sugar

    var
      res: int
      isCompleted: bool

    discard returnThat(10)
      .subscribe(
        (v: int) => (res = v),
        onCompleted = () => (isCompleted = true))

    assert res == 10
    assert isCompleted
  blueprint[T]:
    let retObservable = new IObservable[T]
    retObservable.onSubscribe = proc(observer: Observer[T]): IDisposable =
      observer.onNext v
      observer.onCompleted()
      newSubscription(retObservable, observer)
    return retObservable

proc range*[T: Ordinal](start: T; count: Natural): IObservable[T] =
  runnableExamples:
    import nimRx
    import sugar

    var
      res: int
      isCompleted: bool

    discard range(1, 10)
      .subscribe(
        onNext = (v: int) => (res += v),
        onCompleted = () => (isCompleted = true),
      )

    assert res == 55
    assert isCompleted
  blueprint[T]:
    let retObservable = new IObservable[T]
    retObservable.onSubscribe = proc(observer: Observer[T]): IDisposable =
      for i in 0..<count:
        observer.onNext start.succ(i)
      observer.onCompleted()
      newSubscription(retObservable, observer)
    return retObservable

proc repeat*[T](v: T; times: Natural): IObservable[T] =
  returnThat(v).repeat(times)



# Cold -> Hot converter SECTION

type ConnectableObservable[T] = ref object
  subject: Subject[T]
  upstream: IObservable[T]
  disposable_isItAlreadyConnected: IDisposable
template asObservable*[T](self: ConnectableObservable[T]): IObservable[T] =
  self.subject.asObservable()
proc publish*[T](upstream: IObservable[T]): ConnectableObservable[T] =
  runnableExamples:
    import nimRx
    import nimRx/unitUtils
    import sugar

    var cntCalled: int
    let
      sbj = newSubject[Unit]()
      published = sbj.asObservable
        .doThat((_: Unit) => (inc cntCalled))
        .publish()

    sbj.onNext()
    assert cntCalled == 0

    discard published.asObservable
      .subscribeBlock:
        discard

    sbj.onNext()
    assert cntCalled == 0

    let disconnectable = published.connect()

    sbj.onNext()
    assert cntCalled == 1

    discard published.asObservable
      .subscribeBlock:
        discard

    sbj.onNext()
    assert cntCalled == 2

    disconnectable.dispose()

    sbj.onNext()
    assert cntCalled == 2

  ConnectableObservable[T](
    subject: newSubject[T](),
    upstream: upstream,
  )

proc connect*[T](self: ConnectableObservable[T]): IDisposable =
  ## See `publish proc<#publish,IObservable[T]>`_ for examples.
  # Do nothing when already connected between "publish subject" to its upstream
  if self.disposable_isItAlreadyConnected == nil:
    var dispSbsc = self.upstream.subscribe(
      (v: T) => self.subject.onNext v,
      (e: Error) => self.subject.onError e,
      () => self.subject.onCompleted(),
    )
    self.disposable_isItAlreadyConnected = IDisposable(dispose: proc() =
      dispSbsc.dispose()
      self.disposable_isItAlreadyConnected = nil
    )
  return self.disposable_isItAlreadyConnected

proc refCount*[T](upstream: ConnectableObservable[T]): IObservable[T] =
  ## NOTE: There is something wrong with this behavior.
  ## Be careful when use it.
  var
    cntSubscribed = 0
    dispConnect: IDisposable
  newIObservable[T] proc(observer: Observer[T]): IDisposable =
    let dispSubscribe = upstream.asObservable().subscribe observer
    inc cntSubscribed
    if cntSubscribed == 1:
      dispConnect = upstream.connect()
    return IDisposable(dispose: proc() =
      dec cntSubscribed
      if cntSubscribed == 0:
        dispConnect.dispose()
      dispSubscribe.dispose()
    )

proc share*[T](upstream: IObservable[T]): IObservable[T] =
  upstream.publish().refCount()



# Filters SECTION

proc where*[T](upstream: IObservable[T]; op: (T)->bool): IObservable[T] =
  blueprint[T]:
    newIObservable[T] proc(observer: Observer[T]): IDisposable =
      upstream.subscribe(
        (v: T) => (if op(v): observer.onNext v),
        (e: Error) => observer.onError e,
        () => observer.onCompleted(),
      )

proc select*[T, S](upstream: IObservable[T]; op: (T)->S): IObservable[S] =
  blueprint[S]:
    newIObservable[S] proc(observer: Observer[S]): IDisposable =
      upstream.subscribe(
        (v: T) => observer.onNext op(v),
        (e: Error) => observer.onError e,
        () => observer.onCompleted(),
      )

proc buffer*[T](upstream: IObservable[T]; timeSpan: Natural; skip: Natural = 0):
                                                                IObservable[seq[T]] =
  let skip = if skip == 0: timeSpan else: skip
  type S = seq[T]
  blueprint[S]:
    var cache = newSeq[T]()
    newIObservable[S] proc(observer: Observer[S]): IDisposable =
      upstream.subscribe(
        (proc(v: T) =
          cache.add v
          if cache.len == timeSpan:
            observer.onNext cache
            cache = cache[skip..cache.high]
        ),
        (e: Error) => observer.onError e,
        (proc() =
          if cache.len != 0: observer.onNext cache
          observer.onCompleted()
        ),
      )

proc zip*[Tl, Tr](tl: IObservable[Tl]; tr: IObservable[Tr]):
                                                  IObservable[tuple[l: Tl; r: Tr]] =
  type S = tuple[l: Tl; r: Tr]
  blueprint[S]:
    var cache: tuple[l: seq[Tl]; r: seq[Tr]] = (newSeq[Tl](), newSeq[Tr]())
    proc tryOnNext(observer: Observer[S]) =
      if cache.l.len != 0 and cache.r.len != 0:
        observer.onNext (cache.l[0], cache.r[0])
        cache.l = cache.l[1..cache.l.high]
        cache.r = cache.r[1..cache.r.high]
    newIObservable[S] proc(observer: Observer[S]): IDisposable =
      let disps = @[
        tl.subscribe(
          (v: Tl) => (cache.l.add v; observer.tryOnNext()),
          (e: Error) => observer.onError e,
        ),
        tr.subscribe(
          (v: Tr) => (cache.r.add v; observer.tryOnNext()),
          (e: Error) => observer.onError e,
        ),
      ]
      disps.combineDisposables()

proc zip*[T](upstream: IObservable[T]; targets: varargs[IObservable[T]]):
                                                              IObservable[seq[T]] =
  let targets = concat(@[upstream], @targets)
  type S = seq[T]
  blueprint[S]:
    var cache = newSeqWith(targets.len, newSeq[T]())
    # Is this statement put directly in the for statement on onSubscribe,
    # the values from all obles will go into cache[seq.high].
    proc trySubscribe(target: tuple[oble: IObservable[T]; i: int];
        observer: Observer[S]): IDisposable =
      target.oble.subscribe(
        (proc(v: T) =
          cache[target.i].add(v)
          if cache.filterIt(it.len == 0).len == 0:
            observer.onNext cache.mapIt(it[0])
            cache = cache.mapIt(it[1..it.high])
        ),
        (e: Error) => observer.onError e,
      )
    newIObservable[S] proc(observer: Observer[S]): IDisposable =
      var disps = newSeq[IDisposable](targets.len)
      for i, target in targets:
        disps[i] = (target, i).trySubscribe(observer)
      disps.combineDisposables()



# OnError handlings SECTION

proc retry*[T](upstream: IObservable[T]): IObservable[T] =
  let upstream = upstream
  blueprint[T]:
    # NOTE without this assignment, the upstream variable in retryConnection called later is not found.
    # ...I do not know why. :-(
    proc mkRetryObserver(observer: Observer[T]): Observer[T] =
      newObserver[T](
        (v: T) => observer.onNext v,
        (e: Error) => (discard upstream.subscribe observer.mkRetryObserver()),
        () => observer.onCompleted(),
      )
    newIObservable[T] proc(observer: Observer[T]): IDisposable =
      upstream.subscribe observer.mkRetryObserver()

# onCompleted handlings ===============================================================
proc concat*[T](upstream: IObservable[T]; targets: varargs[IObservable[T]]):
                                                                IObservable[T] =
  let targets = @targets
  blueprint[T]:
    var
      i_target = 0
      retDisp: IDisposable
    proc nextTarget(): IObservable[T] =
      result = targets[i_target]
      inc i_target
    proc mkConcatObserver(observer: Observer[T]): Observer[T] =
      newObserver[T](
        (v: T) => observer.onNext v,
        (e: Error) => observer.onError e,
        (proc() =
          if i_target < targets.len:
            retDisp = nextTarget().subscribe observer.mkConcatObserver()
          else:
            observer.onCompleted()
        ),
      )
    newIObservable[T] proc(observer: Observer[T]): IDisposable =
      retDisp = upstream.subscribe observer.mkConcatObserver()
      IDisposable(dispose: () => retDisp.dispose())

proc repeat*[T](upstream: IObservable[T]): IObservable[T] =
  blueprint[T]:
    proc mkRepeatObserver[T](observer: Observer[T]): Observer[T] =
      newObserver[T](
        (v: T) => observer.onNext v,
        (e: Error) => observer.onError e,
        () => (discard upstream.subscribe observer.mkRepeatObserver()),
      )
    newIObservable[T] proc(observer: Observer[T]): IDisposable =
      return upstream.subscribe observer.mkRepeatObserver()

proc repeat*[T](upstream: IObservable[T]; times: Natural): IObservable[T] =
  upstream.concat(sequtils.repeat(upstream, times-1))



# Value dump SECTION

proc doThat*[T](upstream: IObservable[T]; op: (T)->void): IObservable[T] =
  blueprint[T]:
    newIObservable[T] proc(observer: Observer[T]): IDisposable =
      upstream.subscribe(
        (v: T) => (op(v); observer.onNext v),
        (e: Error) => observer.onError e,
        () => observer.onCompleted(),
      )

proc dump*[T](upstream: IObservable[T]): IObservable[T] =
  template log(action: untyped): untyped = debugEcho "[DUMP] ", action
  blueprint[T]:
    newIObservable[T] proc(observer: Observer[T]): IDisposable =
      upstream.subscribe(
        (v: T) => (log v; observer.onNext v),
        (e: Error) => (log e; observer.onError e),
        () => (log "complete!"; observer.onCompleted()),
      )
