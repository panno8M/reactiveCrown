import std/sugar
import std/unittest
import std/options

import reactiveCrown/core
import reactiveCrown/subjects/subject_publish {.all.}

subject_publish.test


# [Test]
# public void AsyncSubjectTest()
#     // OnCompletedPattern
#         var subject = new AsyncSubject<int>();

#         var onNext = new List<int>();
#         var exception = new List<Exception>();
#         int onCompletedCallCount = 0;
#         subject.Subscribe(x => onNext.Add(x), x => exception.Add(x), () => onCompletedCallCount++);

#         subject.OnNext(1);
#         subject.OnNext(10);
#         subject.OnNext(100);
#         subject.OnNext(1000);
#         onNext.Count.Is(0);

#         subject.OnCompleted();
#         onNext.Is(1000);
#         onCompletedCallCount.Is(1);

#         subject.OnNext(1);
#         subject.OnNext(10);
#         subject.OnNext(100);
#         onNext.Count.Is(1);

#         subject.OnCompleted();
#         subject.OnError(new Exception());
#         exception.Count.Is(0);
#         onCompletedCallCount.Is(1);

#         // ++subscription
#         subject.Subscribe(x => onNext.Add(x), x => exception.Add(x), () => onCompletedCallCount++);
#         onNext.Is(1000, 1000);
#         exception.Count.Is(0);
#         onCompletedCallCount.Is(2);

#     // OnErrorPattern
#         var subject = new AsyncSubject<int>();

#         var onNext = new List<int>();
#         var exception = new List<Exception>();
#         int onCompletedCallCount = 0;
#         subject.Subscribe(x => onNext.Add(x), x => exception.Add(x), () => onCompletedCallCount++);

#         subject.OnNext(1);
#         subject.OnNext(10);
#         subject.OnNext(100);
#         subject.OnNext(1000);
#         onNext.Count.Is(0);

#         subject.OnError(new Exception());
#         exception.Count.Is(1);

#         subject.OnNext(1);
#         subject.OnNext(10);
#         subject.OnNext(100);
#         onNext.Count.Is(0);

#         subject.OnCompleted();
#         subject.OnError(new Exception());
#         exception.Count.Is(1);
#         onCompletedCallCount.Is(0);

#         // ++subscription
#         subject.Subscribe(x => onNext.Add(x), x => exception.Add(x), () => onCompletedCallCount++);
#         onNext.Count.Is(0);
#         exception.Count.Is(2);
#         onCompletedCallCount.Is(0);

# [Test]
# public void BehaviorSubject()
#     // OnCompletedPattern
#         var subject = new BehaviorSubject<int>(3333);

#         var onNext = new List<int>();
#         var exception = new List<Exception>();
#         int onCompletedCallCount = 0;
#         var _ = subject.Subscribe(x => onNext.Add(x), x => exception.Add(x), () => onCompletedCallCount++);

#         onNext.Is(3333);

#         subject.OnNext(1);
#         subject.OnNext(10);
#         subject.OnNext(100);
#         subject.OnNext(1000);

#         onNext.Is(3333, 1, 10, 100, 1000);

#         // re subscription
#         onNext.Clear();
#         _.Dispose();
#         subject.Subscribe(x => onNext.Add(x), x => exception.Add(x), () => onCompletedCallCount++);
#         onNext.Is(1000);

#         subject.OnCompleted();
#         onCompletedCallCount.Is(1);

#         subject.OnNext(1);
#         subject.OnNext(10);
#         subject.OnNext(100);
#         onNext.Count.Is(1);

#         subject.OnCompleted();
#         subject.OnError(new Exception());
#         exception.Count.Is(0);
#         onCompletedCallCount.Is(1);

#         // ++subscription
#         onNext.Clear();
#         onCompletedCallCount = 0;
#         subject.Subscribe(x => onNext.Add(x), x => exception.Add(x), () => onCompletedCallCount++);
#         onNext.Count.Is(0);
#         exception.Count.Is(0);
#         onCompletedCallCount.Is(1);

#     // OnErrorPattern
#         var subject = new BehaviorSubject<int>(3333);

#         var onNext = new List<int>();
#         var exception = new List<Exception>();
#         int onCompletedCallCount = 0;
#         subject.Subscribe(x => onNext.Add(x), x => exception.Add(x), () => onCompletedCallCount++);

#         subject.OnNext(1);
#         subject.OnNext(10);
#         subject.OnNext(100);
#         subject.OnNext(1000);
#         onNext.Is(3333, 1, 10, 100, 1000);

#         subject.OnError(new Exception());
#         exception.Count.Is(1);

#         subject.OnNext(1);
#         subject.OnNext(10);
#         subject.OnNext(100);
#         onNext.Count.Is(5);

#         subject.OnCompleted();
#         subject.OnError(new Exception());
#         exception.Count.Is(1);
#         onCompletedCallCount.Is(0);

#         // ++subscription
#         onNext.Clear();
#         exception.Clear();
#         onCompletedCallCount = 0;
#         subject.Subscribe(x => onNext.Add(x), x => exception.Add(x), () => onCompletedCallCount++);
#         onNext.Count.Is(0);
#         exception.Count.Is(1);
#         onCompletedCallCount.Is(0);

# suite "ReplaySubject":
#   test "onComplete pattern":
#     var subject = newReplaySubject[int]().asSubject
#     var ts: TestStat
#     var disp = subject.asObservable.subscribe(
#       ((x: int) => ts.next.add x),
#       ((x: ref Exception) => ts.exception.add x),
#       (() => inc ts.cntComplete),
#     )

#     subject.next 1, 10, 100, 1000
#     check ts.next == [1, 10, 100, 1000]

#     # replay subscription
#     reset ts
#     consume disp
#     subject.asObservable.subscribe(
#       ((x: int) => ts.next.add x),
#       ((x: ref Exception) => ts.exception.add x),
#       (() => inc ts.cntComplete),
#     )
#     check ts.next == [1, 10, 100, 1000]

#     subject.complete
#     check ts.cntComplete == 1

#     subject.next 1, 10, 100
#     check ts.next.len == 4

#     subject.complete
#     subject.error Exception.newException("test Error")
#     check ts.exception.len == 0
#     check ts.cntComplete == 1

#     # ++subscription
#     reset ts
#     subject.asObservable.subscribe(
#       ((x: int) => ts.next.add x),
#       ((x: ref Exception) => ts.exception.add x),
#       (() => inc ts.cntComplete),
#     )
#     check ts.next == [1, 10, 100, 1000]
#     check ts.exception.len == 0
#     check ts.cntComplete == 1

#   test "onError pattern":
#     var subject = newReplaySubject[int]().asSubject
#     var ts: TestStat

#     subject.asObservable.subscribe(
#       ((x: int) => ts.next.add x),
#       ((x: ref Exception) => ts.exception.add x),
#       (() => inc ts.cntComplete),
#     )

#     subject.next 1, 10, 100, 1000
#     check ts.next == [1, 10, 100, 1000]

#     subject.error Exception.newException("test Error")
#     check ts.exception.len == 1

#     subject.next 1, 10, 100
#     check ts.next.len == 4

#     subject.complete
#     subject.error Exception.newException("test Error")
#     check ts.exception.len == 1
#     check ts.cntComplete == 0

#     # ++subscription
#     reset ts
#     subject.asObservable.subscribe(
#       ((x: int) => ts.next.add x),
#       ((x: ref Exception) => ts.exception.add x),
#       (() => inc ts.cntComplete),
#     )
#     check ts.next == [1, 10, 100, 1000]
#     check ts.exception.len == 1
#     check ts.cntComplete == 0

#   test "buffer replay":
#     var subject = newReplaySubject[int](bufferSize= 3).asSubject
#     var ts: TestStat
#     var disp = subject.asObservable.subscribe(
#       ((x: int) => ts.next.add x),
#       ((x: ref Exception) => ts.exception.add x),
#       (() => inc ts.cntComplete),
#     )

#     subject.next 1, 10, 100, 1000, 10000
#     check ts.next == [1, 10, 100, 1000, 10000]  # cut 1, 10

#     # replay subscription
#     reset ts
#     consume disp
#     disp = subject.asObservable.subscribe(
#       ((x: int) => ts.next.add x),
#       ((x: ref Exception) => ts.exception.add x),
#       (() => inc ts.cntComplete)
#     )
#     check ts.next == [100, 1000, 10000]

#     subject.next 20000
#     check ts.next == [100, 1000, 10000, 20000]

#     reset ts
#     consume disp
#     subject.asObservable.subscribe(
#       ((x: int) => ts.next.add x),
#       ((x: ref Exception) => ts.exception.add x),
#       (() => inc ts.cntComplete)
#     )

#     check ts.next == [1000, 10000, 20000]

#     subject.complete
#     check ts.cntComplete == 1

# [Test]
# public void ReplaySubjectWindowReplay()
#     var subject = new ReplaySubject<int>(window: TimeSpan.FromMilliseconds(700));

#     var onNext = new List<int>();
#     var exception = new List<Exception>();
#     int onCompletedCallCount = 0;
#     var _ = subject.Subscribe(x => onNext.Add(x), x => exception.Add(x), () => onCompletedCallCount++);

#     subject.OnNext(1); // 0
#     Thread.Sleep(TimeSpan.FromMilliseconds(300));

#     subject.OnNext(10); // 300
#     Thread.Sleep(TimeSpan.FromMilliseconds(300));

#     subject.OnNext(100); // 600
#     Thread.Sleep(TimeSpan.FromMilliseconds(300));

#     _.Dispose();
#     onNext.Clear();
#     subject.Subscribe(x => onNext.Add(x), x => exception.Add(x), () => onCompletedCallCount++);
#     onNext.Is(10, 100);

#     subject.OnNext(1000); // 900
#     Thread.Sleep(TimeSpan.FromMilliseconds(300));

#     _.Dispose();
#     onNext.Clear();
#     subject.Subscribe(x => onNext.Add(x), x => exception.Add(x), () => onCompletedCallCount++);
#     onNext.Is(100, 1000);

#     subject.OnNext(10000); // 1200
#     Thread.Sleep(TimeSpan.FromMilliseconds(500));

#     subject.OnNext(2); // 1500
#     Thread.Sleep(TimeSpan.FromMilliseconds(10));

#     subject.OnNext(20); // 1800
#     Thread.Sleep(TimeSpan.FromMilliseconds(10));

#     _.Dispose();
#     onNext.Clear();
#     subject.Subscribe(x => onNext.Add(x), x => exception.Add(x), () => onCompletedCallCount++);
#     onNext.Is(10000, 2, 20);