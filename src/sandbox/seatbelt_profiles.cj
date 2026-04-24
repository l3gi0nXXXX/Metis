package metis.sandbox

import std.collection.HashMap

private const PERMISSIVE_OPEN_PROFILE = """
(version 1)

;; allow everything by default
(allow default)

;; deny all writes EXCEPT under specific paths
(deny file-write*)
(allow file-write*
    (subpath (param "WORK_DIR"))
    (subpath (param "TMP_DIR"))
    (literal "/dev/stdout")
    (literal "/dev/stderr")
    (literal "/dev/null")
    (literal "/dev/ptmx")
    (regex #"^/dev/ttys[0-9]*$")
)
"""

let SEATBELT_PROFILES = HashMap<String, String>([
    ("permissive-open", PERMISSIVE_OPEN_PROFILE)
])