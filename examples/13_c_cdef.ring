/*
 * Example 13: C Definition Parser (C API)
 * API: cffi_cdef
 */
load "../lib.ring"

pLib = cffi_load("libc.so.6")

cDef = "
    struct Point {
        int x;
        int y;
    };
"

nParsed = cffi_cdef(pLib, cDef)
? "Parsed " + nParsed + " definitions"
