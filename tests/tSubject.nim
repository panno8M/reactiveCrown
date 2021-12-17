import sugar
import reactiveCrown
import unittest

type TestStat = object
  next: seq[int]
  exception: seq[ref Exception]
  cntComplete: int

suite "Subject":
  
  test "onComplete pattern":
    var subject = PublishSubject[int]()
    var ts: TestStat
    subject.subscribe(
      onnext= ((x: int) => ts.next.add x),
      onerror= ((x: ref Exception) => ts.exception.add x),
      oncomplete= (() => inc ts.cntComplete),
    )

    subject.next 1, 10, 100, 1000
    check ts.next == [1, 10, 100, 1000]

    subject.complete
    check ts.cntComplete == 1

    subject.next 1, 10, 100
    check ts.next.len == 4

    subject.complete
    subject.error Exception.newException("test Error")
    check ts.exception.len == 0
    check ts.cntComplete == 1

    # ++subscription
    reset ts
    subject.subscribe(
      ((x: int) => ts.next.add x),
      ((x: ref Exception) => ts.exception.add x),
      (() => inc ts.cntComplete),
    )
    check ts.next.len == 0
    check ts.exception.len == 0
    check ts.cntComplete == 1

  test "onError pattern":
    var subject = PublishSubject[int]()
    var ts: TestStat
    subject.subscribe(
      ((x: int) => ts.next.add x),
      ((x: ref Exception) => ts.exception.add x),
      (() => inc ts.cntComplete),
    )

    subject.next 1, 10, 100, 1000
    check ts.next == [1, 10, 100, 1000]

    subject.error Exception.newException("test Error")
    check ts.exception.len == 1

    subject.next 1, 10, 100
    check ts.next.len == 4

    subject.complete
    subject.error Exception.newException("test Error")
    check ts.exception.len == 1
    check ts.cntComplete == 0

    # ++subscription
    reset ts
    subject.subscribe(
      ((x: int) => ts.next.add x),
      ((x: ref Exception) => ts.exception.add x),
      (() => inc ts.cntComplete),
    )
    check ts.next.len == 0
    check ts.exception.len == 1
    check ts.cntComplete == 0

  test "subject subscribe":
    var
      subject = PublishSubject[int]()
      listA, listB, listC: seq[int]
    check not subject.addr.hasAnyObservers

    var listASubscription = subject.subscribe (x: int) => listA.add x
    check subject.addr.hasAnyObservers
    subject.next 1
    check listA[0] == 1

    var listBSubscription = subject.subscribe (x: int) => listB.add x
    check subject.addr.hasAnyObservers
    subject.next 2
    check listA[1] == 2
    check listB[0] == 2

    var listCSubscription = subject.subscribe (x: int) => listC.add x
    check subject.addr.hasAnyObservers
    subject.next 3
    check listA[2] == 3
    check listB[1] == 3
    check listC[0] == 3

    consume listASubscription
    check subject.addr.hasAnyObservers
    subject.next 4
    check listA.len == 3
    check listB[2] == 4
    check listC[1] == 4

    consume listCSubscription
    check subject.addr.hasAnyObservers
    subject.next 5
    check listC.len == 2
    check listB[3] == 5

    consume listBSubscription
    check not subject.addr.hasAnyObservers
    subject.next 6
    check listB.len == 4

    var listD, listE: seq[int]

    subject.subscribe (x: int) => listD.add x
    check subject.addr.hasAnyObservers
    subject.next 1
    check listD[0] == 1

    subject.subscribe (x: int) => listE.add x
    check subject.addr.hasAnyObservers
    subject.next 2
    check listD[1] == 2
    check listE[0] == 2

    # subject.Dispose();

    # Assert.Throws<ObjectDisposedException>(() => subject.OnNext(0));
    # Assert.Throws<ObjectDisposedException>(() => subject.OnError(new Exception()));
    # Assert.Throws<ObjectDisposedException>(() => subject.OnCompleted());

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

suite "ReplaySubject":
  test "onComplete pattern":
    var subject = newReplaySubject[int]().asSubject
    var ts: TestStat
    var disp = subject.asObservable.subscribe(
      ((x: int) => ts.next.add x),
      ((x: ref Exception) => ts.exception.add x),
      (() => inc ts.cntComplete),
    )

    subject.next 1, 10, 100, 1000
    check ts.next == [1, 10, 100, 1000]

    # replay subscription
    reset ts
    consume disp
    subject.asObservable.subscribe(
      ((x: int) => ts.next.add x),
      ((x: ref Exception) => ts.exception.add x),
      (() => inc ts.cntComplete),
    )
    check ts.next == [1, 10, 100, 1000]

    subject.complete
    check ts.cntComplete == 1

    subject.next 1, 10, 100
    check ts.next.len == 4

    subject.complete
    subject.error Exception.newException("test Error")
    check ts.exception.len == 0
    check ts.cntComplete == 1

    # ++subscription
    reset ts
    subject.asObservable.subscribe(
      ((x: int) => ts.next.add x),
      ((x: ref Exception) => ts.exception.add x),
      (() => inc ts.cntComplete),
    )
    check ts.next == [1, 10, 100, 1000]
    check ts.exception.len == 0
    check ts.cntComplete == 1

  test "onError pattern":
    var subject = newReplaySubject[int]().asSubject
    var ts: TestStat

    subject.asObservable.subscribe(
      ((x: int) => ts.next.add x),
      ((x: ref Exception) => ts.exception.add x),
      (() => inc ts.cntComplete),
    )

    subject.next 1, 10, 100, 1000
    check ts.next == [1, 10, 100, 1000]

    subject.error Exception.newException("test Error")
    check ts.exception.len == 1

    subject.next 1, 10, 100
    check ts.next.len == 4

    subject.complete
    subject.error Exception.newException("test Error")
    check ts.exception.len == 1
    check ts.cntComplete == 0

    # ++subscription
    reset ts
    subject.asObservable.subscribe(
      ((x: int) => ts.next.add x),
      ((x: ref Exception) => ts.exception.add x),
      (() => inc ts.cntComplete),
    )
    check ts.next == [1, 10, 100, 1000]
    check ts.exception.len == 1
    check ts.cntComplete == 0

  test "buffer replay":
    var subject = newReplaySubject[int](bufferSize= 3).asSubject
    var ts: TestStat
    var disp = subject.asObservable.subscribe(
      ((x: int) => ts.next.add x),
      ((x: ref Exception) => ts.exception.add x),
      (() => inc ts.cntComplete),
    )

    subject.next 1, 10, 100, 1000, 10000
    check ts.next == [1, 10, 100, 1000, 10000]  # cut 1, 10

    # replay subscription
    reset ts
    consume disp
    disp = subject.asObservable.subscribe(
      ((x: int) => ts.next.add x),
      ((x: ref Exception) => ts.exception.add x),
      (() => inc ts.cntComplete)
    )
    check ts.next == [100, 1000, 10000]

    subject.next 20000
    check ts.next == [100, 1000, 10000, 20000]

    reset ts
    consume disp
    subject.asObservable.subscribe(
      ((x: int) => ts.next.add x),
      ((x: ref Exception) => ts.exception.add x),
      (() => inc ts.cntComplete)
    )

    check ts.next == [1000, 10000, 20000]

    subject.complete
    check ts.cntComplete == 1

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