type gameObject* = ref object of RootObj
  name: string
  tags: seq[string]

proc name*(self: gameObject; name: string): gameObject =
  self.name = name
  self
proc name*(self: gameObject): string = self.name
