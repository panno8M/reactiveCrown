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

template blueprint[T](mkObservable: untyped): untyped =
  IObservable[T](onSubscribe: proc(ober: Observer[T]): IDisposable =
    (() => mkObservable)().subscribe ober
  )

template combineDisposables(disps: varargs[IDisposable]): IDisposable =
  IDisposable(dispose: () => @disps.apply((it: IDisposable) => it.dispose()))

# factories ===========================================================================
proc returnThat*[T](v: T): IObservable[T] =
  blueprint[T]:
    let retObservable = new IObservable[T]
    retObservable.onSubscribe = proc(observer: Observer[T]): IDisposable =
      observer.onNext v
      observer.onCompleted()
      newSubscription(retObservable, observer)
    return retObservable

proc range*[T: Ordinal](start: T; count: Natural): IObservable[T] =
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

# Cold -> Hot converter ===============================================================
type ConnectableObservable[T] = ref object
  subject: Subject[T]
  upstream: IObservable[T]
  disposable_isItAlreadyConnected: IDisposable
template asObservable*[T](self: ConnectableObservable[T]): IObservable[T] =
  self.subject.asObservable()
proc publish*[T](upstream: IObservable[T]): ConnectableObservable[T] =
  ConnectableObservable[T](
    subject: newSubject[T](),
    upstream: upstream,
  )

proc connect*[T](self: ConnectableObservable[T]): IDisposable =
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
  ## TODO: I guess there are something wrong.
  ## Need to research the original specifications in details.
  var
    cntSubscribed = 0
    dispConnect: IDisposable
  IObservable[T](onSubscribe: proc(observer: Observer[T]): IDisposable =
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
  )

proc share*[T](upstream: IObservable[T]): IObservable[T] =
  upstream.publish().refCount()

# filters =============================================================================
# proc where*[T](upstream: IObservable[T]; op: ((T)->bool)): IObservable[T] =
#   asObservable newObservableFactory proc(): IObservable[T] =
#     let oble = newSingleObservable[T]()
#     result = oble.asObservable
#     result.setOnSubscribe proc(ober: Observer[T]): IDisposable =
#       oble.addObserver ober
#       upstream.subscribe(
#         (v: T) => (if op(v): oble.execOnNext v),
#         oble.mkExecOnError,
#         oble.mkExecOnCompleted,
#       )
proc where*[T](upstream: IObservable[T]; op: (T)->bool): IObservable[T] =
  blueprint[T]:
    IObservable[T](onSubscribe: proc(observer: Observer[T]): IDisposable =
      upstream.subscribe(
        (v: T) => (if op(v): observer.onNext v),
        (e: Error) => observer.onError e,
        () => observer.onCompleted(),
      )
    )

proc select*[T, S](upstream: IObservable[T]; op: (T)->S): IObservable[S] =
  blueprint[S]:
    IObservable[S](onSubscribe: proc(observer: Observer[S]): IDisposable =
      upstream.subscribe(
        (v: T) => observer.onNext op(v),
        (e: Error) => observer.onError e,
        () => observer.onCompleted(),
      )
    )

proc buffer*[T](upstream: IObservable[T]; timeSpan: Natural; skip: Natural = 0):
                                                                IObservable[seq[T]] =
  let skip = if skip == 0: timeSpan else: skip
  type S = seq[T]
  blueprint[S]:
    var cache = newSeq[T]()
    IObservable[seq[T]](onSubscribe: proc(observer: Observer[S]): IDisposable =
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
    IObservable[S](onSubscribe: proc(observer: Observer[S]): IDisposable =
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
    )

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
    IObservable[S](onSubscribe: proc(observer: Observer[S]): IDisposable =
      var disps = newSeq[IDisposable](targets.len)
      for i, target in targets:
        disps[i] = (target, i).trySubscribe(observer)
      disps.combineDisposables()
    )

# onError handlings =====================================================================
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
    IObservable[T](onSubscribe: proc(observer: Observer[T]): IDisposable =
      upstream.subscribe observer.mkRetryObserver()
    )

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
    IObservable[T](onSubscribe: proc(observer: Observer[T]): IDisposable =
      retDisp = upstream.subscribe observer.mkConcatObserver()
      IDisposable(dispose: () => retDisp.dispose())
    )

proc repeat*[T](upstream: IObservable[T]): IObservable[T] =
  blueprint[T]:
    proc mkRepeatObserver[T](observer: Observer[T]): Observer[T] =
      newObserver[T](
        (v: T) => observer.onNext v,
        (e: Error) => observer.onError e,
        () => (discard upstream.subscribe observer.mkRepeatObserver()),
      )
    IObservable[T](onSubscribe: proc(observer: Observer[T]): IDisposable =
      return upstream.subscribe observer.mkRepeatObserver()
    )

proc repeat*[T](upstream: IObservable[T]; times: Natural): IObservable[T] =
  upstream.concat(sequtils.repeat(upstream, times-1))


# value dump =====================================================

proc doThat*[T](upstream: IObservable[T]; op: (T)->void): IObservable[T] =
  blueprint[T]:
    IObservable[T](onSubscribe: proc(observer: Observer[T]): IDisposable =
      upstream.subscribe(
        (v: T) => (op(v); observer.onNext v),
        (e: Error) => observer.onError e,
        () => observer.onCompleted(),
      )
    )

proc dump*[T](upstream: IObservable[T]): IObservable[T] =
  template log(action: untyped): untyped = debugEcho "[DUMP] ", action
  blueprint[T]:
    IObservable[T](onSubscribe: proc(observer: Observer[T]): IDisposable =
      upstream.subscribe(
        (v: T) => (log v; observer.onNext v),
        (e: Error) => (log e; observer.onError e),
        () => (log "complete!"; observer.onCompleted()),
      )
    )
