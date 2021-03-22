import sugar, sequtils
import nimRx/[core, subjects]

## *factories ===========================================================================
proc Return*[T](v: T): Observable[T] =
  newObservable[T](onSubscribe = proc(observer: Observer[T]): void =
    observer.onNext(v)
    observer.onCompleted())
proc Range*[T](s: seq[T]): Observable[T] =
  newObservable[T](proc(observer: Observer[T]) =
    for v in s:
      observer.onNext(v)
    observer.onCompleted())

## *filters =============================================================================
proc where*[T](self: Observable[T]; op: ((T)->bool)): Observable[T] =
  let subject = newSubject[T]()

  subject.observable.onSubscribe = proc(observer: Observer[T]) =
    discard self.subscribe(
      onNext = (proc(v: T): void =
      if op(v): subject.onNext(v)),
      onError = (proc(e: Error): void = subject.onError(e)),
      onCompleted = (proc(): void = subject.onCompleted()))
  return subject.observable

proc select*[T, S](self: Observable[T]; op: ((T)->S)): Observable[S] =
  let subject = newSubject[S]()

  subject.observable.onSubscribe = proc(observer: Observer[S]) =
    discard self.subscribe(
      onNext = (proc(v: T): void = subject.onNext(op v)),
      onError = (proc(e: Error): void = subject.onError(e)),
      onCompleted = (proc(): void = subject.onCompleted()))
  return subject.observable

proc buffer*[T](self: Observable[T]; count: int; skip: int = 0): Observable[seq[T]] =
  let
    skip = if skip == 0: count else: skip
    subject = newSubject[seq[T]]()
  var
    cache = newSeq[T]()

  subject.observable.onSubscribe = proc(observer: Observer[seq[T]]) =
    discard self.subscribe(
      onNext = (proc(v: T): void =
      cache.add(v)
      if cache.len == count:
        subject.onNext(cache)
        cache = cache[skip..cache.high]
      ),
      onError = (proc(e: Error): void = subject.onError(e)),
      onCompleted = (proc(): void = subject.onCompleted()))
  return subject.observable

## *onError handlings =====================================================================
proc retry*[T](self: Observable[T]): Observable[T] =
  let
    subject = newSubject[T]()
    self = self
  proc newRetryOsr[T](): Observer[T] =
    newObserver[T](
      onNext = proc(v: T): void = subject.onNext(v),
      onError = proc(e: Error): void = discard self.subscribe(newRetryOsr[T]()),
      onCompleted = proc(): void = subject.onCompleted())

  subject.observable.onSubscribe = proc(observer: Observer[T]) =
    discard self.subscribe(newRetryOsr[T]())
  return subject.observable

## *onCompleted handlings ===============================================================
proc concat*[T](self: Observable[T]; ts: varargs[Observable[T]]):
                                                                  Observable[T] =
  let
    subject = newSubject[T]()
  var
    count = 0
    targets = newSeq[Observable[T]](ts.len)
  for i, v in ts: targets[i] = v

  proc nextTarget(): Observable[T] =
    result = targets[count]
    inc count

  proc newConcatOsr[T](): Observer[T] =
    newObserver[T](
      onNext = proc(v: T): void = subject.onNext(v),
      onError = proc(e: Error): void = subject.onError(e),
      onCompleted = proc(): void =
      if count < targets.len:
        discard nextTarget().subscribe(newConcatOsr[T]())
      else:
        subject.onCompleted())

  subject.observable.onSubscribe = proc(observer: Observer[T]) =
    discard self.subscribe(newConcatOsr[T]())
  return subject.observable

proc repeat*[T](self: Observable[T]): Observable[T] =
  let subject = newSubject[T]()
  proc newRepeatOsr[T](): Observer[T] =
    newObserver[T](
      onNext = proc(v: T): void = subject.onNext(v),
      onError = proc(e: Error): void = subject.onError(e),
      onCompleted = proc(): void = self.subscribe(newRepeatOsr[T]())
    )
  subject.observable.onSubscribe = proc(observer: Observer[T]) =
    discard self.subscribe(newRepeatOsr[T]())
  return subject.observable
proc repeat*[T](self: Observable[T]; times: Natural): Observable[T] =
  self.concat(sequtils.repeat(self, times - 1))
proc repeat*[T](v: T; times: Natural): Observable[T] =
  Return(v).repeat(times)
