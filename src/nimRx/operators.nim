import sugar, sequtils
import nimRx/[core, subjects, utils]

type
  SingleObservable[T] = ref object
    iObservable: IObservable[T]
    observer: Observer[T]
  ObservableFactory[T] = ref object
    iObservable: IObservable[T]
    generate: ()->IObservable[T]

proc asObservable*[T](self: SingleObservable[T]): IObservable[T] =
  self.iObservable
proc asObservable*[T](self: ObservableFactory[T]): IObservable[T] =
  self.iObservable

template execOnNext[T](self: SingleObservable[T]; v: T) =
  if self.asObservable.hasAnyObservers(): self.observer.onNext(v)
template execOnError[T](self: SingleObservable[T]; e: Error) =
  if self.asObservable.hasAnyObservers(): self.observer.onError(e)
template execOnCompleted[T](self: SingleObservable[T]) =
  if self.asObservable.hasAnyObservers(): self.observer.onCompleted()
proc mkExecOnNext[T](self: SingleObservable[T]): (T)->void =
  return proc(v: T) = self.execOnNext(v)
proc mkExecOnError[T](self: SingleObservable[T]): (Error)->void =
  return proc(e: Error) = self.execOnError(e)
proc mkExecOnCompleted[T](self: SingleObservable[T]): ()->void =
  return proc() = self.execOnCompleted()

proc addObserver[T](self: SingleObservable[T]; ober: Observer[T]) =
  self.observer = ober
proc newSingleObservable[T](): SingleObservable[T] =
  let observable = new SingleObservable[T]
  observable.iObservable = IObservable[T](
    hasAnyObservers: () => observable.observer != nil,
    removeObserver: (o: Observer[T]) =>
      (if observable.observer == o: observable.observer = nil),
  )
  return observable

proc newObservableFactory[T](generate: ()->IObservable[T]): ObservableFactory[T] =
  let factory = ObservableFactory[T](generate: generate)
  factory.iObservable = IObservable[T](
    onSubscribe: proc(observer: Observer[T]): IDisposable = factory.generate().subscribe(observer)
  )
  return factory

template combineDisposables(disposables: varargs[IDisposable]): IDisposable =
  IDisposable(
    dispose: () => @disposables.apply((it: IDisposable) => it.dispose())
  )

# factories ===========================================================================
proc returnThat*[T](v: T): IObservable[T] =
  asObservable newObservableFactory proc(): IObservable[T] =
    let oble = newSingleObservable[T]()
    result = oble.asObservable
    result.setOnSubscribe proc(ober: Observer[T]): IDisposable =
      oble.addObserver ober
      ober.onNext v
      ober.onCompleted()
      newSubscription(oble.asObservable, ober).asDisposable

proc range*[T: Ordinal](start: T; count: Natural): IObservable[T] =
  asObservable newObservableFactory proc(): IObservable[T] =
    let oble = newSingleObservable[T]()
    result = oble.asObservable
    result.setOnSubscribe proc(ober: Observer[T]): IDisposable =
      oble.addObserver ober
      for i in 0..<count:
        ober.onNext start.succ(i)
      ober.onCompleted()
      newSubscription(oble.asObservable, ober).asDisposable

# Cold -> Hot converter ===============================================================
type ConnectableObservable[T] = ref object
  subject: Subject[T]
  upstream: IObservable[T]
proc asObservable*[T](self: ConnectableObservable[T]): IObservable[T] =
  self.subject.asObservable
proc publish*[T](upstream: IObservable[T]): ConnectableObservable[T] =
  let oble = ConnectableObservable[T](
    subject: newSubject[T](),
    upstream: upstream,
  )
  return oble

proc connect*[T](self: ConnectableObservable[T]): IDisposable =
  self.upstream.subscribe(
    (v: T) => self.subject.onNext(v),
    (e: Error) => self.subject.onError(e),
    () => self.subject.onCompleted(),
  )

# filters =============================================================================
proc where*[T](upstream: IObservable[T]; op: ((T)->bool)): IObservable[T] =
  asObservable newObservableFactory proc(): IObservable[T] =
    let oble = newSingleObservable[T]()
    result = oble.asObservable
    result.setOnSubscribe proc(ober: Observer[T]): IDisposable =
      oble.addObserver ober
      upstream.subscribe(
        (v: T) => (if op(v): oble.execOnNext v),
        oble.mkExecOnError,
        oble.mkExecOnCompleted,
      )

proc select*[T, S](upstream: IObservable[T]; op: ((T)->S)): IObservable[S] =
  asObservable newObservableFactory proc(): IObservable[S] =
    let oble = newSingleObservable[S]()
    result = oble.asObservable
    result.setOnSubscribe proc(ober: Observer[S]): IDisposable =
      oble.addObserver ober
      upstream.subscribe(
        (v: T) => (oble.execOnNext op(v)),
        oble.mkExecOnError,
        oble.mkExecOnCompleted,
      )

proc buffer*[T](upstream: IObservable[T]; count: Natural; skip: Natural = 0):
                                                                IObservable[seq[T]] =
  let skip = if skip == 0: count else: skip
  asObservable newObservableFactory proc(): IObservable[seq[T]] =
    let oble = newSingleObservable[seq[T]]()
    result = oble.asObservable
    var cache = newSeq[T]()

    result.setOnSubscribe proc(ober: Observer[seq[T]]): IDisposable =
      oble.addObserver ober
      upstream.subscribe(
        (proc(v: T) =
          cache.add(v)
          if cache.len == count:
            oble.execOnNext(cache)
            cache = cache[skip..cache.high]
        ),
        oble.mkExecOnError,
        oble.mkExecOnCompleted,
      )

proc zip*[Tl, Tr](tl: IObservable[Tl]; tr: IObservable[Tr]):
                                                  IObservable[tuple[l: Tl; r: Tr]] =
  type T = tuple[l: Tl; r: Tr]
  asObservable newObservableFactory proc(): IObservable[T] =
    let oble = newSingleObservable[T]()
    result = oble.asObservable
    var cache: tuple[l: seq[Tl]; r: seq[Tr]] = (newSeq[Tl](), newSeq[Tr]())
    proc tryOnNext() =
      if 1 <= cache.l.len and 1 <= cache.r.len:
        oble.execOnNext((cache.l[0], cache.r[0]))
        cache.l = cache.l[1..cache.l.high]
        cache.r = cache.r[1..cache.r.high]
    result.setOnSubscribe proc(ober: Observer[T]): IDisposable =
      oble.addObserver ober
      let disposables = @[
        tl.subscribe(
          (proc(v: Tl) =
            cache.l.add(v)
            tryOnNext()
          ),
          oble.mkExecOnError,
          oble.mkExecOnCompleted,
        ),
        tr.subscribe(
          (proc(v: Tr) =
            cache.r.add(v)
            tryOnNext()
          ),
          oble.mkExecOnError,
          oble.mkExecOnCompleted,
        ),
      ]
      combineDisposables(disposables)

proc zip*[T](upstream: IObservable[T]; targets: varargs[IObservable[T]]):
                                                              IObservable[seq[T]] =
  let targets = concat(@[upstream], @targets)
  asObservable newObservableFactory proc(): IObservable[seq[T]] =
    let oble = newSingleObservable[seq[T]]()
    result = oble.asObservable
    var cache = newSeqWith(targets.len, newSeq[T]())

    # Is this statement put directly in the for statement on onSubscribe,
    # the values from all obles will go into cache[seq.high].
    proc tryExecute(target: IObservable[T]; i: int): IDisposable =
      target.subscribe(
        (proc(v: T) =
          cache[i].add(v)
          if cache.filterIt(it.len == 0).len == 0:
            oble.execOnNext cache.mapIt(it[0])
            cache = cache.mapIt(it[1..it.high])
        ),
        oble.mkExecOnError,
      )
    result.setOnSubscribe proc(ober: Observer[seq[T]]): IDisposable =
      oble.addObserver ober
      var disposables = newSeq[IDisposable](targets.len)
      for i, target in targets:
        disposables[i] = tryExecute(target, i)
      combineDisposables(disposables)


# onError handlings =====================================================================
proc retry*[T](upstream: IObservable[T]): IObservable[T] =
  # NOTE without this assignment, the upstream variable in retryConnection called later is not found.
  # ...I do not know why. :-(
  let upstream = upstream
  asObservable newObservableFactory proc(): IObservable[T] =
    let oble = newSingleObservable[T]()
    result = oble.asObservable
    proc retryConnection[T](): Observer[T] =
      newObserver[T](
        oble.mkExecOnNext,
        (e: Error) => (discard upstream.subscribe retryConnection[T]()),
        oble.mkExecOnCompleted,
      )

    oble.asObservable.setOnSubscribe proc(ober: Observer[T]): IDisposable =
      oble.addObserver ober
      return upstream.subscribe retryConnection[T]()

# onCompleted handlings ===============================================================
proc concat*[T](upstream: IObservable[T]; targets: varargs[IObservable[T]]):
                                                                IObservable[T] =
  var count = 0
  let targets = @targets
  asObservable newObservableFactory proc(): IObservable[T] =
    let oble = newSingleObservable[T]()
    result = oble.asObservable
    var resultDisposable: IDisposable

    proc nextTarget(): IObservable[T] =
      result = targets[count]
      inc count
    proc concatConnection[T](): Observer[T] =
      newObserver[T](
        oble.mkExecOnNext,
        oble.mkExecOnError,
        (proc() =
          if count < targets.len:
            resultDisposable = nextTarget().subscribe concatConnection[T]()
          else:
            oble.execOnCompleted()),
      )
    oble.asObservable.setOnSubscribe proc(ober: Observer[T]): IDisposable =
      oble.addObserver ober
      resultDisposable = upstream.subscribe concatConnection[T]()
      IDisposable(dispose: () => resultDisposable.dispose())

proc repeat*[T](upstream: IObservable[T]): IObservable[T] =
  newObservableFactory proc(): IObservable[T] =
    let oble = newSingleObservable[T]()
    result = oble.asObservable
    proc repeatConnection[T](ober: Observer[T]): Observer[T] =
      newObserver[T](
        ober.onNext,
        ober.onError,
        () => (discard upstream.subscribe ober.repeatConnection()),
      )
    result.setOnSubscribe proc(ober: Observer[T]): IDisposable =
      oble.addObserver ober
      return upstream.subscribe repeatConnection(ober)
proc repeat*[T](upstream: IObservable[T]; times: Natural): IObservable[T] =
  upstream.concat(sequtils.repeat(upstream, times-1))
template repeat*[T](v: T; times: Natural): IObservable[T] =
  returnThat(v).repeat(times)


# value dump =====================================================

proc doThat*[T](upstream: IObservable[T]; op: (T)->void): IObservable[T] =
  asObservable newObservableFactory proc(): IObservable[T] =
    let oble = newSingleObservable[T]()
    result = oble.asObservable
    result.setOnSubscribe proc(ober: Observer[T]): IDisposable =
      oble.addObserver ober
      upstream.subscribe(
        (proc(v: T) =
          op(v)
          oble.execOnNext(v)
        ),
        oble.mkExecOnError,
        oble.mkExecOnCompleted,
      )

proc dump*[T](upstream: IObservable[T]): IObservable[T] =
  asObservable newObservableFactory proc(): IObservable[T] =
    let oble = newSingleObservable[T]()
    result = oble.asObservable
    result.setOnSubscribe proc(): IDisposable =
      upstream.subscribe(
        (proc(v: T) =
          log v
          oble.execOnNext(v)
        ),
        (proc(e: Error) =
          log e
          oble.execOnError(e)
        ),
        (proc() =
          log "complete!"
          oble.execOnCompleted()
        )
      )
