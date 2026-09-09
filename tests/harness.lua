-- Asserts minimos compartidos por las suites de tests.

local h = { passed = 0, failed = 0 }
local current = "?"

function h.check(ok, msg)
  if ok then
    h.passed = h.passed + 1
  else
    h.failed = h.failed + 1
    print(("  FALLO [%s] %s"):format(current, msg))
  end
end

function h.eq(actual, expected, msg)
  h.check(actual == expected, ("%s: esperaba %s, obtuve %s"):format(msg, tostring(expected), tostring(actual)))
end

function h.test(name, fn)
  current = name
  print("* " .. name)
  local ok, err = pcall(fn)
  if not ok then
    h.failed = h.failed + 1
    print("  ERROR: " .. tostring(err))
  end
end

function h.summary()
  print()
  print(("%d ok, %d fallos"):format(h.passed, h.failed))
  return h.failed == 0
end

return h
