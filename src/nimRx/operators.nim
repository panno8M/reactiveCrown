import sugar, sequtils
import nimRx/[core, subjects, utils]

## *factories ===========================================================================
proc returnThat*[T](v: T): Observable[T] =
  newObservableFactory proc(): Observable[T] =
    let oble = newObservable[T]()
    result = oble
    oble.setOnSubscribe proc(ober: Observer[T]): IDisposable =
      ober.onNext v
      ober.onCompleted()
      newSubscription(oble.asObservable, ober).asDisposable

proc range*[T: Ordinal](start: T; count: Natural): Observable[T] =
  newObservableFactory proc(): Observable[T] =
    let oble = newObservable[T]()
    result = oble
    oble.setOnSubscribe proc(ober: Observer[T]): IDisposable =
      for i in 0..<count:
        ober.onNext start.succ(i)
      ober.onCompleted()
      newSubscription(oble.asObservable, ober).asDisposable

## *Cold -> Hot converter ===============================================================
type ConnectableObservable[T] = ref object of Observable[T]
  upstream: Observable[T]
proc publish*[T](upstream: Observable[T]): ConnectableObservable[T] =
  let oble = ConnectableObservable[T](
    upstream: upstream,
  )
  oble.setOnSubscribe proc(ober: Observer[T]): IDisposable =
    newSubscription(oble.asObservable, ober).asDisposable
  return oble


proc connect*[T](self: ConnectableObservable[T]): IDisposable =
  let observable = self
  result = observable.upstream.subscribe(
    observable.mkExecOnNext,
    observable.mkExecOnError,
    observable.mkExecOnCompleted,
  )

## *filters =============================================================================
proc where*[T](upstream: Observable[T]; op: ((T)->bool)): Observable[T] =
  newObservableFactory proc(): Observable[T] =
    let observable = newObservable[T]()
    result = observable
    observable.setOnSubscribe proc(): IDisposable =
      upstream.subscribe(
        (v: T) => (if op(v): observable.execOnNext v),
        observable.mkExecOnError,
        observable.mkExecOnCompleted,
      )

proc select*[T, S](upstream: Observable[T]; op: ((T)->S)): Observable[S] =
  newObservableFactory proc(): Observable[S] =
    let observable = newObservable[S]()
    result = observable
    observable.setOnSubscribe proc(): IDisposable =
      upstream.subscribe(
        (v: T) => (observable.execOnNext(op(v))),
        observable.mkExecOnError,
        observable.mkExecOnCompleted,
      )

proc buffer*[T](upstream: Observable[T]; count: Natural; skip: Natural = 0):
                                                                Observable[seq[T]] =
  let skip = if skip == 0: count else: skip
  newObservableFactory proc(): Observable[seq[T]] =
    let observable = newObservable[seq[T]]()
    result = observable
    var cache = newSeq[T]()

    observable.setOnSubscribe proc(): IDisposable =
      upstream.subscribe(
        (proc(v: T) =
          cache.add(v)
          if cache.len == count:
            observable.execOnNext(cache)
            cache = cache[skip..cache.high]
        ),
        observable.mkExecOnError,
        observable.mkExecOnCompleted,
      )

proc zip*[Tl, Tr](tl: Observable[Tl]; tr: Observable[Tr]):
                                                  Observable[tuple[l: Tl; r: Tr]] =
  type T = tuple[l: Tl; r: Tr]
  newObservableFactory proc(): Observable[T] =
    let observable = newObservable[T]()
    result = observable
    var cache: tuple[l: seq[Tl]; r: seq[Tr]] = (newSeq[Tl](), newSeq[Tr]())
    proc tryOnNext() =
      if 1 <= cache.l.len and 1 <= cache.r.len:
        observable.execOnNext((cache.l[0], cache.r[0]))
        cache.l = cache.l[1..cache.l.high]
        cache.r = cache.r[1..cache.r.high]
    observable.setOnSubscribe proc(): IDisposable =
      var disposables = newSeq[IDisposable](2)
      disposables[0] = tl.subscribe(
        (proc(v: Tl) =
          cache.l.add(v)
          tryOnNext()
        ),
        observable.mkExecOnError,
        observable.mkExecOnCompleted,
      )
      disposables[1] = tr.subscribe(
        (proc(v: Tr) =
          cache.r.add(v)
          tryOnNext()
        ),
        observable.mkExecOnError,
        observable.mkExecOnCompleted,
      )
      combineDisposables(disposables)

proc zip*[T](upstream: Observable[T]; targets: varargs[Observable[T]]):
                                                              Observable[seq[T]] =
  let targets = concat(@[upstream], @targets)
  newObservableFactory proc(): Observable[seq[T]] =
    let observable = newObservable[seq[T]]()
    result = observable
    var cache = newSeq[seq[T]](targets.len).mapIt(newSeq[T]())

    # Is this statement put directly in the for statement on onSubscribe,
    # the values from all observables will go into cache[seq.high].
    proc tryExecute(target: Observable[T]; i: int): IDisposable =
      target.subscribe(
        (proc(v: T) =
          cache[i].add(v)
          if cache.filterIt(it.len == 0).len == 0:
            observable.execOnNext cache.mapIt(it[0])
            cache = cache.mapIt(it[1..it.high])
        ),
        observable.mkExecOnError,
      )
    observable.setOnSubscribe proc(): IDisposable =
      var disposables = newSeq[IDisposable](targets.len)
      for i, target in targets:
        disposables[i] = tryExecute(target, i)
      combineDisposables(disposables)

## *onError handlings =====================================================================
proc retry*[T](upstream: Observable[T]): Observable[T] =
  # NOTE without this assignment, the upstream variable in retryConnection called later is not found.
  # ...I do not know why. :-(
  let upstream = upstream
  newObservableFactory proc(): Observable[T] =
    let observable = newObservable[T]()
    result = observable
    var resultDisposable: IDisposable
    proc retryConnection[T](): Observer[T] =
      newObserver[T](
        observable.mkExecOnNext,
        (e: Error) => (resultDisposable = upstream.subscribe retryConnection[T]()),
        observable.mkExecOnCompleted,
      )

    observable.setOnSubscribe proc(): IDisposable =
      resultDisposable = upstream.subscribe retryConnection[T]()
      IDisposable(dispose: () => resultDisposable.dispose())

## *onCompleted handlings ===============================================================
proc concat*[T](upstream: Observable[T]; targets: varargs[Observable[T]]):
                                                                Observable[T] =
  var count = 0
  let targets = @targets
  newObservableFactory proc(): Observable[T] =
    let observable = newObservable[T]()
    result = observable
    var resultDisposable: IDisposable

    proc nextTarget(): Observable[T] =
      result = targets[count]
      inc count
    proc concatConnection[T](): Observer[T] =
      newObserver[T](
        observable.mkExecOnNext,
        observable.mkExecOnError,
        (proc() =
          if count < targets.len:
            resultDisposable = nextTarget().subscribe concatConnection[T]()
          else:
            observable.execOnCompleted()),
      )
    observable.setOnSubscribe proc(): IDisposable =
      resultDisposable = upstream.subscribe concatConnection[T]()
      IDisposable(dispose: () => resultDisposable.dispose())

proc repeat*[T](upstream: Observable[T]): Observable[T] =
  newObservableFactory proc(): Observable[T] =
    let observable = newObservable[T]()
    result = observable
    proc repeatConnection[T](observer: Observer[T]): Observer[T] =
      newObserver[T](
        observer.onNext,
        observer.onError,
        () => (discard upstream.subscribe observer.repeatConnection()),
      )
    observable.onSubscribe = proc() =
      discard upstream.subscribe observable.observer.repeatConnection()
proc repeat*[T](upstream: Observable[T]; times: Natural): Observable[T] =
  upstream.concat(sequtils.repeat(upstream, times-1))
template repeat*[T](v: T; times: Natural): Observable[T] =
  returnThat(v).repeat(times)


## *value dump =====================================================

proc doThat*[T](upstream: Observable[T]; op: (T)->void): Observable[T] =
  newObservableFactory proc(): Observable[T] =
    let observable = newObservable[T]()
    result = observable
    observable.setOnSubscribe proc(): IDisposable =
      upstream.subscribe(
        (proc(v: T) =
          op(v)
          observable.execOnNext(v)
        ),
        observable.mkExecOnError,
        observable.mkExecOnCompleted,
      )

proc dump*[T](upstream: Observable[T]): Observable[T] =
  newObservableFactory proc(): Observable[T] =
    let observable = newObservable[T]()
    result = observable
    observable.onSubscribe = proc() =
      discard upstream.subscribe(
        (proc(v: T) =
          log v
          observable.execOnNext(v)
        ),
        (proc(e: Error) =
          log e
          observable.execOnError(e)
        ),
        (proc() =
          log "complete!"
          observable.execOnCompleted()
        )
      )
