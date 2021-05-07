import sugar, sequtils
import nimRx/[core, subjects, utils]

## *factories ===========================================================================
proc returnThat*[T](v: T): Observable[T] =
  newObservable[T](proc(observer: Observer[T]) =
    observer.onNext v
    observer.onCompleted()
  )
proc range*[T: Ordinal](start: T; count: Natural): Observable[T] =
  newObservable[T](proc(observer: Observer[T]) =
    for i in 0..<count: observer.onNext start.succ(i)
    observer.onCompleted()
  )

## *Cold -> Hot converter ===============================================================


## *filters =============================================================================
proc where*[T](upstream: Observable[T]; op: ((T)->bool)): Observable[T] =
  let observable = newObservable[T]()
  result = observable

  observable.onSubscribe = proc() =
    discard upstream.subscribe(
      (v: T) => (if op(v): observable.execOnNext v),
      observable.mkExecOnError,
      observable.mkExecOnCompleted,
    )

proc select*[T, S](upstream: Observable[T]; op: ((T)->S)): Observable[S] =
  let observable = newObservable[S]()
  result = observable

  observable.onSubscribe = proc() =
    discard upstream.subscribe(
      (v: T) => (observable.execOnNext(op(v))),
      observable.mkExecOnError,
      observable.mkExecOnCompleted,
    )

proc buffer*[T](upstream: Observable[T]; count: Natural; skip: Natural = 0):
                                                                Observable[seq[T]] =
  let
    skip = if skip == 0: count else: skip
    observable = newObservable[seq[T]]()
  result = observable
  var cache = newSeq[T]()

  observable.onSubscribe = proc() =
    discard upstream.subscribe(
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
  let observable = newObservable[T]()
  result = observable
  var cache: tuple[l: seq[Tl]; r: seq[Tr]] = (newSeq[Tl](), newSeq[Tr]())
  proc tryOnNext() =
    if 1 <= cache.l.len and 1 <= cache.r.len:
      observable.execOnNext((cache.l[0], cache.r[0]))
      cache.l = cache.l[1..cache.l.high]
      cache.r = cache.r[1..cache.r.high]
  observable.onSubscribe = proc() =
    discard tl.subscribe(
      (proc(v: Tl) =
        cache.l.add(v)
        tryOnNext()
      ),
      observable.mkExecOnError,
      observable.mkExecOnCompleted,
    )
    discard tr.subscribe(
      (proc(v: Tr) =
        cache.r.add(v)
        tryOnNext()
      ),
      observable.mkExecOnError,
      observable.mkExecOnCompleted,
    )

proc zip*[T](upstream: Observable[T]; targets: varargs[Observable[T]]):
                                                              Observable[seq[T]] =
  let
    targets = concat(@[upstream], @targets)
    observable = newObservable[seq[T]]()
  result = observable
  var cache = newSeq[seq[T]](targets.len).mapIt(newSeq[T]())

  # Is this statement put directly in the for statement on onSubscribe,
  # the values from all observables will go into cache[seq.high].
  proc tryOnNext(target: Observable[T]; i: int) =
    discard target.subscribe(
      (proc(v: T) =
        cache[i].add(v)
        if cache.filterIt(it.len == 0).len == 0:
          observable.execOnNext cache.mapIt(it[0])
          cache = cache.mapIt(it[1..it.high])
      ),
      observable.mkExecOnError,
    )
  observable.onSubscribe = proc() =
    for i, target in targets:
      tryOnNext(target, i)

## *onError handlings =====================================================================
proc retry*[T](upstream: Observable[T]): Observable[T] =
  let
    # NOTE without this assignment, the upstream variable in retryConnection called later is not found.
    # This reason seems because a immutable argument cannot be a variable in closure.
    upstream = upstream
    observable = newObservable[T]()
  result = observable
  proc retryConnection[T](): Observer[T] =
    newObserver[T](
      observable.mkExecOnNext,
      (e: Error) => (discard upstream.subscribe retryConnection[T]()),
      observable.mkExecOnCompleted,
    )

  observable.onSubscribe = proc() =
    discard upstream.subscribe retryConnection[T]()

## *onCompleted handlings ===============================================================
proc concat*[T](upstream: Observable[T]; targets: varargs[Observable[T]]):
                                                                Observable[T] =
  let observable = newObservable[T]()
  result = observable
  var
    targets = @targets
    count = 0

  proc nextTarget(): Observable[T] =
    result = targets[count]
    inc count

  proc concatConnection[T](): Observer[T] =
    newObserver[T](
      observable.mkExecOnNext,
      observable.mkExecOnError,
      (proc() =
        if count < targets.len:
          discard nextTarget().subscribe concatConnection[T]()
        else:
          observable.execOnCompleted()),
    )
  observable.onSubscribe = proc() =
    discard upstream.subscribe concatConnection[T]()

proc repeat*[T](upstream: Observable[T]): Observable[T] =
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
proc repeat*[T](v: T; times: Natural): Observable[T] =
  returnThat(v).repeat(times)


## *value dump =====================================================

proc doThat*[T](upstream: Observable[T]; op: (T)->void): Observable[T] =
  let observable = newObservable[T]()
  result = observable
  observable.onSubscribe = proc() =
    discard upstream.subscribe(
      (proc(v: T) =
        op(v)
        observable.execOnNext(v)
      ),
      observable.mkExecOnError,
      observable.mkExecOnCompleted,
    )

proc dump*[T](upstream: Observable[T]): Observable[T] =
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
