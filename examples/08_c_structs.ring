/*
 * Example 08: Structs (C API)
 * API: cffi_struct, cffi_struct_new, cffi_field, cffi_field_offset, cffi_struct_size
 *      Nested dot notation, Bitfield support
 */
load "cffi.ring"

pLib = cffi_load(getLibcPath())

# Basic struct
oPoint = cffi_struct("Point", [
    ["x", "int"],
    ["y", "int"]
])

? "struct size: " + cffi_struct_size(oPoint)
? "x offset: " + cffi_field_offset(oPoint, "x")
? "y offset: " + cffi_field_offset(oPoint, "y")

pPt = cffi_struct_new(oPoint)
cffi_set(cffi_field(pPt, oPoint, "x"), "int", 100)
cffi_set(cffi_field(pPt, oPoint, "y"), "int", 200)
? "Point(" + cffi_get(cffi_field(pPt, oPoint, "x"), "int") + ", " + cffi_get(cffi_field(pPt, oPoint, "y"), "int") + ")"

# Nested struct with dot notation
? nl + "--- Nested Struct (dot notation) ---"
oInner = cffi_struct("Vec2", [
    ["x", "int"],
    ["y", "int"]
])
oOuter = cffi_struct("Entity", [
    ["id", "int"],
    ["pos", "Vec2"]
])
pEnt = cffi_struct_new(oOuter)
cffi_set(cffi_field(pEnt, oOuter, "id"), "int", 1)
cffi_set(cffi_field(pEnt, oOuter, "pos.x"), "int", 50)
cffi_set(cffi_field(pEnt, oOuter, "pos.y"), "int", 75)
? "Entity " + cffi_get(cffi_field(pEnt, oOuter, "id"), "int") + " at (" + cffi_get(cffi_field(pEnt, oOuter, "pos.x"), "int") + ", " + cffi_get(cffi_field(pEnt, oOuter, "pos.y"), "int") + ")"
? "pos.x offset: " + cffi_field_offset(oOuter, "pos.x")

# Bitfield support via cdef
? nl + "--- Bitfields ---"
cffi_cdef(pLib, "
    struct Flags {
        unsigned int a : 3;
        unsigned int b : 5;
        unsigned int c : 4;
        int normal;
    };
")
fType = cffi_typeof("Flags")
pF = cffi_struct_new(fType)
cffi_set(cffi_field(pF, fType, "a"), "int", 5)
cffi_set(cffi_field(pF, fType, "b"), "int", 17)
cffi_set(cffi_field(pF, fType, "c"), "int", 9)
cffi_set(cffi_field(pF, fType, "normal"), "int", 42)
? "a=" + cffi_get(cffi_field(pF, fType, "a"), "int") + " b=" + cffi_get(cffi_field(pF, fType, "b"), "int") + " c=" + cffi_get(cffi_field(pF, fType, "c"), "int") + " normal=" + cffi_get(cffi_field(pF, fType, "normal"), "int")

func getLibcPath
    if isWindows()
        return "msvcrt.dll"
    but isFreeBSD()
        return "libc.so.7"
    but isMacOSX()
        return "libSystem.B.dylib"
    else
        return "libc.so.6"
    ok