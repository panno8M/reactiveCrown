##[
  ReactiveX implemented with Nim.

  Simple Usage
  ============
]##

runnableExamples:
  # It is the same as: import nimRx/[core, operators, subjects]

  import nimRx/unitUtils
  import sugar
  import times

  # procs for example
  proc focus() = return
  proc jumpTo() = return
  var onButtonClicked: proc()
  # =================

  const doubleClickBorder_s = 0.01'f

  let
    sbjOnBtnClicked = newSubject[Unit]()

    dspOnBtnClicked =
      sbjOnBtnClicked.asObservable
        .doThat((_: Unit) => echo "\"Button\" has clicked!")
        .subscribeBlock:
          focus()

    obsOnBtnDoubleClicked =
      sbjOnBtnClicked.asObservable
        .select(_ => cpuTime())
        .buffer(2, 1)
        .where(seqt => seqt.len == 2)
        .select(seqt => seqt[1]-seqt[0])
        .where(dt => dt <= doubleClickBorder_s)
        .doThat((dt: float) => echo "\"Button\" has double clicked!")

    dspOnBtnDoubleClicked =
      obsOnBtnDoubleClicked
        .subscribe(
          (proc(dt: float) =

            # some processing...

            jumpTo()
          ),
        )

  onButtonClicked = proc() =
    sbjOnBtnClicked.onNext()

##[
  Modules
  =======

  [core](nimRx/core.html)
  -----------------------

  | It is the core of this library. 
  | It is useless by itself basically but, it is necessary to use nimRx.
  | It will be implicitly imported by written "import nimRx" . 

  [subjects](nimRx/subjects.html)
  -------------------------------

  It will be implicitly imported by written "import nimRx" . 

  [operators](nimRx/operators.html)
  ---------------------------------

  It will be implicitly imported by written "import nimRx" . 

  [unitUtils](nimRx/unitUtils.html)
  ---------------------------------

  To use this module, you need to explicitly import it by writing "import nimRx/unitUtils".

]##
import nimRx/[core, subjects, operators, unitUtils]
export core, subjects, operators
