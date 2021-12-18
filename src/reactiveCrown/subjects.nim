{.deadCodeElim.}
{.experimental: "strictFuncs".}
{.experimental: "strictEffects".}

import subjects/subject_concept
import subjects/subject_publish

export subject_concept
export subject_publish

# Replay Subject -------------------------------------------------------------------------------- #

# import std/deques

# type ReplaySubject*[T] {.byref.} = object
#   sbj: Subject[T]
#   bufferSize: Natural
#   cache: Deque[T]

# func asSubject*[T](this: ReplaySubject[T]): lent Subject[T] = this.sbj
# func asSubject*[T](this: var ReplaySubject[T]): var Subject[T] = this.sbj

# proc trim[T](this: var ReplaySubject[T]) =
#   while this.cache.len > this.bufferSize:
#     this.cache.popFirst()


# proc newReplaySubject*[T](bufferSize: Natural = Natural.high): ReplaySubject[T] =
#   var subject = ReplaySubject[T](
#     bufferSize: bufferSize,
#   )

#   subject.sbj.asObservable.onSubscribe = proc(ober: Observer[T]): Disposable =
#     for x in subject.cache.items: ober.next x
#     if subject.sbj.isCompleted:
#       ober.complete
#     elif subject.sbj.getLastError != nil:
#       ober.error subject.sbj.getLastError
#     else:
#       subject.sbj.addobserver ober
#     newSubscription(subject.sbj.asObservable, ober)

#   subject.sbj.asObserver.onNext = some proc(v: T) =
#     subject.cache.addLast v
#     if subject.sbj.hasAnyObservers:
#       for observer in subject.sbj.observers.mitems: observer.next v
#     subject.trim

#   subject.sbj.asObserver.onError = some proc(e: ref Exception) =
#     subject.sbj.stat.error = e
#     if subject.sbj.hasAnyObservers:
#       for observer in subject.sbj.observers.mitems: observer.error e
#     subject.asSubject.observers.setLen(0)
#     reset subject.sbj.ober

#   subject.sbj.asObserver.onComplete = some proc() =
#     subject.sbj.stat.isCompleted = true
#     if subject.sbj.hasAnyObservers:
#       for observer in subject.sbj.observers.mitems: observer.complete
#     subject.sbj.observers.setLen(0)
#     reset subject.sbj.ober

#   return subject

# # Operator Subject --------------------------------------------------------------------- #

# type OperatorSubject*[T] {.byref.} = object
#   sbj: Subject[T]

# func asSubject*[T](this: OperatorSubject[T]): lent Subject[T] = this.sbj
# func asSubject*[T](this: var OperatorSubject[T]): var Subject[T] = this.sbj

# proc newOperatorSubject*[T](): OperatorSubject[T] =
#   var subject = OperatorSubject[T]()

#   subject.asObservable.onSubscribe = proc(ober: Observer[T]): Disposable =
#     if subject.isCompleted:
#       ober.complete
#     else:
#       subject.addobserver ober
#     newSubscription(subject, ober)

#   subject.asObserver.onNext = some proc(v: T) =
#     subject.execOnNext(v)

#   subject.asObserver.onError = some proc(e: ref Exception) =
#     if not subject.asObservable.hasAnyObservers(): return
#     var s = subject.asSubject.observers
#     subject.asSubject.observers.setLen(0)
#     for observer in s: observer.error(e)

#   subject.asObserver.onComplete = some proc() =
#     subject.asSubject.stat.isCompleted = true
#     subject.execOnComplete()
#     subject.asSubject.observers.setLen(0)
#     reset subject.asSubject.ober[]

#   return subject

# # ------------------------------------------------------------------------------- Operator Subject #