import sugar, sequtils
import nimRx/[core, subjects, utils]

template blueprint[T](action: untyped): untyped =
  proc generate(): IObservable[T] =
    action
  IObservable[T](onSubscribe: proc(ober: Observer[T]): IDisposable =
    generate().subscribe ober
  )

template combineDisposables(disposables: varargs[IDisposable]): IDisposable =
  IDisposable(
    dispose: () => @disposables.apply((it: IDisposable) => it.dispose())
  )

# factories ===========================================================================
proc returnThat*[T](v: T): IObservable[T] =
  blueprint[T]:
    let retval = new IObservable[T]
    retval.onSubscribe = proc(ober: Observer[T]): IDisposable =
      ober.onNext v
      ober.onCompleted()
      newSubscription(retval, ober).asDisposable
    return retval

proc range*[T: Ordinal](start: T; count: Natural): IObservable[T] =
  blueprint[T]:
    let retval = new IObservable[T]
    retval.onSubscribe = proc(ober: Observer[T]): IDisposable =
      for i in 0..<count:
        ober.onNext start.succ(i)
      ober.onCompleted()
      newSubscription(retval, ober).asDisposable
    return retval

# Cold -> Hot converter ===============================================================
type ConnectableObservable[T] = ref object
  subject: Subject[T]
  upstream: IObservable[T]
  disposable_isItAlreadyConnected: IDisposable
proc asObservable*[T](self: ConnectableObservable[T]): IObservable[T] =
  self.subject.asObservable
proc publish*[T](upstream: IObservable[T]): ConnectableObservable[T] =
  let oble = ConnectableObservable[T](
    subject: newSubject[T](),
    upstream: upstream,
  )
  return oble

proc connect*[T](self: ConnectableObservable[T]): IDisposable =
  if self.disposable_isItAlreadyConnected == nil:
    var dispSbsc = self.upstream.subscribe(
      (v: T) => self.subject.onNext(v),
      (e: Error) => self.subject.onError(e),
      () => self.subject.onCompleted(),
    )
    self.disposable_isItAlreadyConnected = IDisposable(dispose: proc() =
      dispSbsc.dispose()
      self.disposable_isItAlreadyConnected = nil
    )
  return self.disposable_isItAlreadyConnected

proc refCount*[T](upstream: ConnectableObservable[T]): IObservable[T] =
  let
    oble = upstream.asObservable
    oble_retval = new IObservable[T]
  var
    cnt = 0
    dispConnect: IDisposable
  oble_retval.setOnSubscribe proc(ober: Observer[T]): IDisposable =
    let dispSubscribe = oble.subscribe(ober)
    inc cnt
    if cnt == 1:
      dispConnect = upstream.connect()
    return IDisposable(dispose: proc() =
      dec cnt
      if cnt == 0:
        dispConnect.dispose()
      dispSubscribe.dispose()
    )
  return oble_retval

template share*[T](upstream: IObservable[T]): IObservable[T] =
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
    IObservable[T](onSubscribe: proc(ober: Observer[T]): IDisposable =
      upstream.subscribe(
        (v: T) => (if op(v): ober.onNext v),
        (e: Error) => ober.onError e,
        () => ober.onCompleted(),
      )
    )

proc select*[T, S](upstream: IObservable[T]; op: (T)->S): IObservable[S] =
  blueprint[S]:
    IObservable[S](onSubscribe: proc(ober: Observer[S]): IDisposable =
      upstream.subscribe(
        (v: T) => ober.onNext op(v),
        (e: Error) => ober.onError e,
        () => ober.onCompleted(),
      )
    )

proc buffer*[T](upstream: IObservable[T]; count: Natural; skip: Natural = 0):
                                                                IObservable[seq[T]] =
  let skip = if skip == 0: count else: skip
  blueprint[seq[T]]:
    var cache = newSeq[T]()
    IObservable[seq[T]](onSubscribe: proc(ober: Observer[seq[T]]): IDisposable =
      upstream.subscribe(
        (proc(v: T) =
          cache.add(v)
          if cache.len == count:
            ober.onNext(cache)
            cache = cache[skip..cache.high]
        ),
        (e: Error) => ober.onError e,
        () => ober.onCompleted(),
      )
    )

proc zip*[Tl, Tr](tl: IObservable[Tl]; tr: IObservable[Tr]):
                                                  IObservable[tuple[l: Tl; r: Tr]] =
  type T = tuple[l: Tl; r: Tr]
  blueprint[T]:
    var cache: tuple[l: seq[Tl]; r: seq[Tr]] = (newSeq[Tl](), newSeq[Tr]())
    template tryOnNext(ober: Observer[T]) =
      if 1 <= cache.l.len and 1 <= cache.r.len:
        ober.onNext (cache.l[0], cache.r[0])
        cache.l = cache.l[1..cache.l.high]
        cache.r = cache.r[1..cache.r.high]
    IObservable[T](onSubscribe: proc(ober: Observer[T]): IDisposable =
      let disps = @[
        tl.subscribe(
          (proc(v: Tl) =
            cache.l.add(v)
            ober.tryOnNext()
          ),
          (e: Error) => ober.onError e,
          () => ober.onCompleted(),
        ),
        tr.subscribe(
          (proc(v: Tr) =
            cache.r.add(v)
            ober.tryOnNext()
          ),
          (e: Error) => ober.onError e,
          () => ober.onCompleted(),
        ),
      ]
      disps.combineDisposables()
    )

proc zip*[T](upstream: IObservable[T]; targets: varargs[IObservable[T]]):
                                                              IObservable[seq[T]] =
  let targets = concat(@[upstream], @targets)
  blueprint[seq[T]]:
    var cache = newSeqWith(targets.len, newSeq[T]())
    # Is this statement put directly in the for statement on onSubscribe,
    # the values from all obles will go into cache[seq.high].
    proc trySubscribe(target: tuple[oble: IObservable[T]; i: int];
        ober: Observer[seq[T]]): IDisposable =
      target.oble.subscribe(
        (proc(v: T) =
          cache[target.i].add(v)
          if cache.filterIt(it.len == 0).len == 0:
            ober.onNext cache.mapIt(it[0])
            cache = cache.mapIt(it[1..it.high])
        ),
        (e: Error) => ober.onError e,
      )
    IObservable[seq[T]](onSubscribe: proc(ober: Observer[seq[T]]): IDisposable =
      var disps = newSeq[IDisposable](targets.len)
      for i, target in targets:
        disps[i] = (target, i).trySubscribe(ober)
      disps.combineDisposables()
    )

# onError handlings =====================================================================
proc retry*[T](upstream: IObservable[T]): IObservable[T] =
  let upstream = upstream
  blueprint[T]:
    # NOTE without this assignment, the upstream variable in retryConnection called later is not found.
    # ...I do not know why. :-(
    proc mkRetryObserver(ober: Observer[T]): Observer[T] =
      newObserver[T](
        (v: T) => ober.onNext v,
        (e: Error) => (discard upstream.subscribe ober.mkRetryObserver()),
        () => ober.onCompleted(),
      )
    IObservable[T](onSubscribe: proc(ober: Observer[T]): IDisposable =
      upstream.subscribe ober.mkRetryObserver()
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
    proc mkConcatObserver(ober: Observer[T]): Observer[T] =
      newObserver[T](
        (v: T) => ober.onNext v,
        (e: Error) => ober.onError e,
        (proc() =
          if i_target < targets.len:
            retDisp = nextTarget().subscribe ober.mkConcatObserver()
          else:
            ober.onCompleted()
        ),
      )
    IObservable[T](onSubscribe: proc(ober: Observer[T]): IDisposable =
      retDisp = upstream.subscribe ober.mkConcatObserver()
      IDisposable(dispose: () => retDisp.dispose())
    )

proc repeat*[T](upstream: IObservable[T]): IObservable[T] =
  blueprint[T]:
    proc mkRepeatObserver[T](ober: Observer[T]): Observer[T] =
      newObserver[T](
        ober.onNext,
        ober.onError,
        () => (discard upstream.subscribe ober.mkRepeatObserver()),
      )
    IObservable[T](onSubscribe: proc(): IDisposable =
      return upstream.subscribe ober.mkRepeatObserver()
    )
proc repeat*[T](upstream: IObservable[T]; times: Natural): IObservable[T] =
  upstream.concat(sequtils.repeat(upstream, times-1))
template repeat*[T](v: T; times: Natural): IObservable[T] =
  returnThat(v).repeat(times)


# value dump =====================================================

proc doThat*[T](upstream: IObservable[T]; op: (T)->void): IObservable[T] =
  blueprint[T]:
    IObservable[T](onSubscribe: proc(ober: Observer[T]): IDisposable =
      upstream.subscribe(
        (v: T) => (op(v); ober.onNext v),
        (e: Error) => ober.onError e,
        () => ober.onCompleted(),
      )
    )

proc dump*[T](upstream: IObservable[T]): IObservable[T] =
  blueprint[T]:
    IObservable[T](onSubscribe: proc(ober: Observer[T]): IDisposable =
      upstream.subscribe(
        (v: T) => (log v; ober.onNext v),
        (e: Error) => (log e; ober.onError e),
        () => (log "complete!"; ober.onCompleted()),
      )
    )
