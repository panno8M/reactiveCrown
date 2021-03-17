import strutils

proc log*(x: varargs[string, `$`]) =
  when defined nimRxLogging:
    debugEcho "[LOG] ", x.join()

template logblock*(title: string; blk: untyped): untyped =
  when defined nimRxLogging:
    let eq = "=".repeat(((30 - (title.len + 2))/2).toInt)
    log eq, "=[", title, "]=", eq
    (proc(): void = blk)()
    log eq, "[#", title, "#]", eq, "\n"
  else:
    blk
