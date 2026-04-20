/*
 * Example 05: Strings (C API)
 * API: cffi_string, cffi_tostring, cffi_string_array, cffi_wstring, cffi_wtostring
 */
load "cffi.ring"

pLib = cffi_load(getLibcPath())

pStr = cffi_string("Hello from Ring!")
? "C string: " + cffi_tostring(pStr)

oFunc = cffi_func(pLib, "strlen", "int", ["ptr"])
? "Length: " + cffi_invoke(oFunc, pStr)

pDest = cffi_new("char", 64)
oStrcpy = cffi_func(pLib, "strcpy", "ptr", ["ptr", "ptr"])
cffi_invoke(oStrcpy, pDest, pStr)
? "Copied: " + cffi_tostring(pDest)

# String array (char**)
? nl + "--- String Array (char**) ---"
ppArgs = cffi_string_array(["arg0", "arg1", "arg2"])
? "String array created (char** with NULL terminator)"

# Wide strings (wchar_t*)
? nl + "--- Wide Strings ---"
pWide = cffi_wstring("Hello UTF-16!")
? "wstring roundtrip: " + cffi_wtostring(pWide)

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