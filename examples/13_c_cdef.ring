/*
 * Example 13: C Definition Parser (C API)
 * API: cffi_cdef
 *
 * Demonstrates parsing C declarations for:
 *   - Structs
 *   - Unions
 *   - Enums
 *   - Functions
 *   - Typedefs
 */
load "cffi.ring"

pLib = cffi_load(getLibcPath())

? "=== C Definition Parser (cffi_cdef) ===" + nl

/*
 * Example 1: Parsing function declarations
 */
? "1. Parsing function declarations"
nFuncs = cffi_cdef(pLib, "
    int abs(int);
")
? "   Parsed " + nFuncs + " function(s)"

oAbs = cffi_func(pLib, "abs", "int", ["int"])
nResult = cffi_invoke(oAbs, [-42])
? "   abs(-42) = " + nResult

? ""

/*
 * Example 2: Parsing struct declarations
 */
? "2. Parsing struct declarations"
nStructs = cffi_cdef(pLib, "
    struct Point {
        int x;
        int y;
    };
")
? "   Parsed " + nStructs + " struct(s)"

PointType = cffi_typeof("Point")
pt = cffi_struct_new(PointType)

pX = cffi_field(pt, PointType, "x")
pY = cffi_field(pt, PointType, "y")
cffi_set(pX, "int", 100)
cffi_set(pY, "int", 200)
? "   Point.x = " + cffi_get(pX, "int")
? "   Point.y = " + cffi_get(pY, "int")
? "   sizeof(Point) = " + cffi_struct_size(PointType)

? ""

/*
 * Example 3: Parsing enum declarations
 */
? "3. Parsing enum declarations"
nEnums = cffi_cdef(pLib, "
    enum Color {
        RED = 1,
        GREEN = 2,
        BLUE = 4
    };
")
? "   Parsed " + nEnums + " enum(s)"

ColorType = cffi_typeof("Color")
? "   RED   = " + cffi_enum_value(ColorType, "RED")
? "   GREEN = " + cffi_enum_value(ColorType, "GREEN")
? "   BLUE  = " + cffi_enum_value(ColorType, "BLUE")

? ""

/*
 * Example 4: Parsing union declarations
 */
? "4. Parsing union declarations"
nUnions = cffi_cdef(pLib, "
    union Data {
        int i;
        float f;
        char c;
    };
")
? "   Parsed " + nUnions + " union(s)"

DataType = cffi_typeof("Data")
data = cffi_union_new(DataType)
pI = cffi_field(data, DataType, "i")
cffi_set(pI, "int", 42)
? "   Data.i = " + cffi_get(pI, "int")

? ""

/*
 * Example 5: Parsing struct with pointer fields
 */
? "5. Parsing struct with pointer fields"
nParsed = cffi_cdef(pLib, "
    struct Person {
        char* name;
        int age;
    };
")
? "   Parsed " + nParsed + " definition(s)"

PersonType = cffi_typeof("Person")
? "   sizeof(Person) = " + cffi_struct_size(PersonType)

person = cffi_struct_new(PersonType)
pName = cffi_field(person, PersonType, "name")
pAge = cffi_field(person, PersonType, "age")
cffi_set(pName, "ptr", cffi_string("Alice"))
cffi_set(pAge, "int", 30)
? "   Person.name = " + cffi_tostring(cffi_get(pName, "ptr"))
? "   Person.age  = " + cffi_get(pAge, "int")

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