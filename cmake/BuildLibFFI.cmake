cmake_minimum_required(VERSION 3.16)

set(FFI_ROOT "${FFI_LIBFFI_DIR}")

if(NOT CMAKE_SYSTEM_PROCESSOR)
    set(CMAKE_SYSTEM_PROCESSOR "${CMAKE_HOST_SYSTEM_PROCESSOR}")
endif()

if(NOT INSTALL_DIRECTORY)
    set(INSTALL_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/out)
endif()

if(MSVC)
    set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} /wd4996")
elseif(WIN32 OR MINGW)
    set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -Wno-deprecated-declarations -Wno-pointer-to-int-cast")
endif()

# config variables for ffi.h.in — derived from the libffi tree itself so they
# cannot drift when the submodule is bumped (libffi does the same: its
# configure.ac derives the version macros from AC_INIT). The fallback fetch
# tag in CMakeLists.txt must still be updated manually to match.
file(STRINGS "${FFI_ROOT}/configure.ac" _ffi_acinit
    REGEX "^AC_INIT\\(\\[libffi\\],\\[[0-9.]+\\]")
if(NOT _ffi_acinit)
    message(FATAL_ERROR "Cannot determine libffi version from ${FFI_ROOT}/configure.ac")
endif()
string(REGEX MATCH "\\[([0-9.]+)\\]" _ffi_ver_match "${_ffi_acinit}")
if(NOT _ffi_ver_match)
    message(FATAL_ERROR "Cannot parse libffi version from: ${_ffi_acinit}")
endif()
set(VERSION "${CMAKE_MATCH_1}")
string(REPLACE "." ";" _ffi_ver_parts "${VERSION}")
list(GET _ffi_ver_parts 0 _ffi_ver_major)
list(GET _ffi_ver_parts 1 _ffi_ver_minor)
list(LENGTH _ffi_ver_parts _ffi_ver_len)
if(_ffi_ver_len GREATER 2)
    list(GET _ffi_ver_parts 2 _ffi_ver_micro)
else()
    set(_ffi_ver_micro 0)
endif()
math(EXPR FFI_VERSION_NUMBER "${_ffi_ver_major}*10000 + ${_ffi_ver_minor}*100 + ${_ffi_ver_micro}")
set(FFI_VERSION_STRING "${VERSION}")
message(STATUS "libffi version: ${VERSION} (${FFI_VERSION_NUMBER})")

set(KNOWN_PROCESSORS x86 x86_64 amd64 arm arm64 i386 i686 armv7l armv7-a aarch64)

string(TOLOWER "${CMAKE_SYSTEM_PROCESSOR}" lower_system_processor)

if(NOT lower_system_processor IN_LIST KNOWN_PROCESSORS)
    message(FATAL_ERROR "Unknown processor: ${CMAKE_SYSTEM_PROCESSOR}")
endif()

if(MSVC)
    if(CMAKE_VS_PLATFORM_NAME STREQUAL "ARM64" OR CMAKE_SYSTEM_PROCESSOR MATCHES "arm64|aarch64")
        set(TARGET ARM_WIN64)
    elseif(CMAKE_VS_PLATFORM_NAME STREQUAL "ARM" OR CMAKE_SYSTEM_PROCESSOR STREQUAL "arm")
        set(TARGET ARM_WIN32)
    elseif(CMAKE_SIZEOF_VOID_P EQUAL 8)
        set(TARGET X86_WIN64)
    else()
        set(TARGET X86_WIN32)
    endif()
elseif(lower_system_processor MATCHES "arm64|aarch64")
    set(TARGET ARM64)
elseif(lower_system_processor MATCHES "arm")
    set(TARGET ARM)
elseif(CMAKE_SYSTEM_NAME MATCHES "BSD" AND CMAKE_SIZEOF_VOID_P EQUAL 4)
    set(TARGET X86_FREEBSD)
elseif(CMAKE_SYSTEM_NAME MATCHES "Darwin" AND CMAKE_SIZEOF_VOID_P EQUAL 4)
    set(TARGET X86_DARWIN)
elseif(CMAKE_SIZEOF_VOID_P EQUAL 8)
    set(TARGET X86_64)
elseif(CMAKE_SIZEOF_VOID_P EQUAL 4)
    set(TARGET X86)
else()
    message(FATAL_ERROR "Cannot determine target. Please consult ${FFI_ROOT}/configure.ac and add your platform to this CMake file.")
endif()

# Detect platform-specific values for fficonfig.h

# sizeof checks
include(CheckTypeSize)
check_type_size("double" SIZEOF_DOUBLE BUILTIN_TYPES_ONLY LANGUAGE C)
check_type_size("long double" SIZEOF_LONG_DOUBLE BUILTIN_TYPES_ONLY LANGUAGE C)
check_type_size("size_t" SIZEOF_SIZE_T LANGUAGE C)

# header checks
include(CheckIncludeFile)
check_include_file("alloca.h" HAVE_ALLOCA_H)
check_include_file("dlfcn.h" HAVE_DLFCN_H)
check_include_file("strings.h" HAVE_STRINGS_H)
check_include_file("unistd.h" HAVE_UNISTD_H)
check_include_file("sys/mman.h" HAVE_SYS_MMAN_H)
check_include_file("sys/memfd.h" HAVE_SYS_MEMFD_H)

# function checks
include(CheckSymbolExists)
check_symbol_exists(mmap "sys/mman.h" HAVE_MMAP)
check_symbol_exists(mkostemp "stdlib.h" HAVE_MKOSTEMP)
check_symbol_exists(memfd_create "sys/mman.h" HAVE_MEMFD_CREATE)

# long double bigger than double?
if(SIZEOF_LONG_DOUBLE GREATER SIZEOF_DOUBLE)
    set(HAVE_LONG_DOUBLE 1)
else()
    set(HAVE_LONG_DOUBLE 0)
endif()

# hidden visibility
if(MSVC)
    set(HAVE_HIDDEN_VISIBILITY_ATTRIBUTE 0)
else()
    set(HAVE_HIDDEN_VISIBILITY_ATTRIBUTE 1)
endif()

# symbol underscore (macOS prefixes symbols with _)
if(CMAKE_SYSTEM_NAME MATCHES "Darwin")
    set(SYMBOL_UNDERSCORE 1)
endif()

# trampoline table — mirrors configure.ac: *arm*-apple-* | aarch64-apple-*
if(CMAKE_SYSTEM_NAME MATCHES "Darwin" AND lower_system_processor MATCHES "arm|aarch64")
    set(FFI_EXEC_TRAMPOLINE_TABLE 1)
else()
    set(FFI_EXEC_TRAMPOLINE_TABLE 0)
endif()

# static trampolines — mirrors configure.ac's default-on case list:
# cygwin/msys (GNU toolchain) and *-linux-* (incl. Android)
if(CMAKE_SYSTEM_NAME MATCHES "Linux|Android")
    set(FFI_EXEC_STATIC_TRAMP 1)
elseif(CMAKE_SYSTEM_NAME MATCHES "Cygwin|MSYS" AND NOT MSVC)
    set(FFI_EXEC_STATIC_TRAMP 1)
endif()

# Cannot use malloc on this target, so revert to alternative means — mirrors
# configure.ac: *-apple-* | *-*-dragonfly* | *-*-freebsd* | *-*-kfreebsd* |
# *-*-openbsd* | *-pc-solaris* | *-linux-android*. Deliberately NOT defined on
# plain Linux/Cygwin/Windows: closures.c self-defines it there when needed
# (#if !FFI_MMAP_EXEC_WRIT && !FFI_EXEC_TRAMPOLINE_TABLE ... __linux__ / _WIN32).
if(CMAKE_SYSTEM_NAME MATCHES "Darwin|DragonFly|FreeBSD|OpenBSD|Solaris|Android")
    set(FFI_MMAP_EXEC_WRIT 1)
endif()

# MSVC-specific: stdlib.h quirk
if(MSVC)
    set(LACKS_STDLIB_H 1)
endif()

# Autotools-parity probes (mirror configure.ac / acinclude.m4)

# __int128_t type existence -> HAVE_INT128 (configure.ac AC_CHECK_TYPE)
include(CheckTypeSize)
check_type_size("__int128_t" SIZEOF_INT128_TYPE LANGUAGE C)
if(SIZEOF_INT128_TYPE)
    set(HAVE_INT128 1)
endif()

# Big-endian detection -> WORDS_BIGENDIAN (AC_C_BIGENDIAN)
include(TestBigEndian)
test_big_endian(_IS_BIG_ENDIAN)
if(_IS_BIG_ENDIAN)
    set(WORDS_BIGENDIAN 1)
endif()

# Assembler .cfi_* pseudo-ops (acinclude.m4 GCC_AS_CFI_PSEUDO_OP). NOT for
# MSVC: sysv_intel.S / win64_intel.S include ffi_cfi.h, and with the macro
# defined the cfi_* calls expand to GAS .cfi_* directives, which MASM
# rejects (error A2008). Only the gas/clang toolchains probe it.
set(_asm_probe_dir "${CMAKE_CURRENT_BINARY_DIR}/asm_probes")
file(MAKE_DIRECTORY "${_asm_probe_dir}")
if(NOT MSVC)
    file(WRITE "${_asm_probe_dir}/cfi.s"
        ".text\n.globl main\nmain:\n\t.cfi_startproc\n\tret\n\t.cfi_endproc\n")
    try_compile(_ASM_CFI_OK "${_asm_probe_dir}/try_cfi" "${_asm_probe_dir}/cfi.s"
        OUTPUT_VARIABLE _cfi_probe_out)
    if(_ASM_CFI_OK)
        set(HAVE_AS_CFI_PSEUDO_OP 1)
    endif()
endif()

# assembler supports PC relative relocs -> HAVE_AS_X86_PCREL
# (configure.ac case X86*); machine-independent, so gate on the target family
if(NOT MSVC AND ("${TARGET}" MATCHES "^X86"))
    file(WRITE "${_asm_probe_dir}/pcrel.s"
        ".text\nfoo: nop\n.data\n.long foo-.\n.text\n.globl main\nmain:\n\tret\n")
    try_compile(_ASM_X86_PCREL_OK "${_asm_probe_dir}/try_pcrel" "${_asm_probe_dir}/pcrel.s"
        OUTPUT_VARIABLE _pcrel_probe_out)
    if(_ASM_X86_PCREL_OK)
        set(HAVE_AS_X86_PCREL 1)
    endif()
endif()

# toolchain supports the @unwind section type -> HAVE_AS_X86_64_UNWIND_SECTION_TYPE
# (configure.ac gates this on TARGET == X86_64 and probes with
#  -Wa,--fatal-warnings; @unwind is invalid on 32-bit x86, hence the gate)
if(NOT MSVC AND "${TARGET}" STREQUAL "X86_64")
    file(WRITE "${_asm_probe_dir}/unwind.s"
        ".section .eh_frame,\"a\",@unwind\n.text\n.globl main\nmain:\n\tret\n")
    try_compile(_ASM_UNWIND_OK "${_asm_probe_dir}/try_unwind" "${_asm_probe_dir}/unwind.s"
        CMAKE_FLAGS "-DCMAKE_ASM_FLAGS=-Wa,--fatal-warnings"
        OUTPUT_VARIABLE _unwind_probe_out)
    if(_ASM_UNWIND_OK)
        set(HAVE_AS_X86_64_UNWIND_SECTION_TYPE 1)
    endif()
endif()

# compiler supports pointer authentication -> HAVE_ARM64E_PTRAUTH
# (configure.ac AC_COMPILE_IFELSE with __has_feature(ptrauth_calls))
include(CheckCSourceCompiles)
# NB: the result variable must NOT be the macro the snippet tests — newer CMake
# compiles the check with -D<result-var>, which would satisfy the #ifndef and
# make the probe a guaranteed false positive.
check_c_source_compiles(
"#ifdef __clang__
# if __has_feature(ptrauth_calls)
#  define HAVE_ARM64E_PTRAUTH 1
# endif
#endif
#ifndef HAVE_ARM64E_PTRAUTH
# error Pointer authentication not supported
#endif
int main(void) { return 0; }"
HAVE_ARM64E_PTRAUTH_COMPILE)
unset(HAVE_ARM64E_PTRAUTH CACHE)
if(HAVE_ARM64E_PTRAUTH_COMPILE)
    set(HAVE_ARM64E_PTRAUTH 1)
endif()

# whether .eh_frame should be read-only -> HAVE_RO_EH_FRAME + EH_FRAME_FLAGS
# (configure.ac libffi_cv_ro_eh_frame: compile -fpic -fexceptions and inspect
#  with readelf; falls back to read-only "a" when the probe cannot run)
set(HAVE_RO_EH_FRAME 1)
set(_EH_FRAME_FLAGS "a")
if(NOT MSVC)
    find_program(READELF readelf greadelf)
    set(_eh_probe_dir "${CMAKE_CURRENT_BINARY_DIR}/eh_probe")
    file(MAKE_DIRECTORY "${_eh_probe_dir}")
    file(WRITE "${_eh_probe_dir}/eh.c"
        "extern void foo (void); void bar (void) { foo (); foo (); }\n")
    execute_process(
        COMMAND ${CMAKE_C_COMPILER} -c -fpic -fexceptions -fno-lto
                "${_eh_probe_dir}/eh.c" -o "${_eh_probe_dir}/eh.o"
        RESULT_VARIABLE _eh_probe_rc OUTPUT_QUIET ERROR_QUIET
    )
    if(_eh_probe_rc EQUAL 0 AND READELF)
        execute_process(
            COMMAND "${READELF}" -WS "${_eh_probe_dir}/eh.o"
            OUTPUT_VARIABLE _eh_probe_out RESULT_VARIABLE _eh_readelf_rc ERROR_QUIET
        )
        if(_eh_readelf_rc EQUAL 0)
            string(REGEX MATCH "eh_frame[^\n]*WA" _eh_frame_writable "${_eh_probe_out}")
            if(_eh_frame_writable)
                set(HAVE_RO_EH_FRAME "")
                set(_EH_FRAME_FLAGS "aw")
            endif()
        endif()
    endif()
endif()

# Generate fficonfig.h from template
file(MAKE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/include")
configure_file(${FFI_ROOT}/include/ffi.h.in ${CMAKE_CURRENT_BINARY_DIR}/include/ffi.h)

get_filename_component(_cmake_module_dir "${CMAKE_CURRENT_LIST_FILE}" DIRECTORY)
configure_file(
    "${_cmake_module_dir}/fficonfig.h.in"
    "${CMAKE_CURRENT_BINARY_DIR}/fficonfig.h"
    @ONLY
)

if ("${TARGET}" STREQUAL "ARM_WIN64" OR "${TARGET}" STREQUAL "ARM64")
    file(COPY ${FFI_ROOT}/src/aarch64/ffitarget.h DESTINATION ${CMAKE_CURRENT_BINARY_DIR}/include)
elseif ("${TARGET}" STREQUAL "ARM_WIN32" OR "${TARGET}" STREQUAL "ARM")
    file(COPY ${FFI_ROOT}/src/arm/ffitarget.h DESTINATION ${CMAKE_CURRENT_BINARY_DIR}/include)
else()
    file(COPY ${FFI_ROOT}/src/x86/ffitarget.h DESTINATION ${CMAKE_CURRENT_BINARY_DIR}/include)
endif()

set(FFI_INCLUDE_DIRS
    ${CMAKE_CURRENT_BINARY_DIR}/include
    ${CMAKE_CURRENT_BINARY_DIR}
    ${FFI_ROOT}/include
    ${FFI_ROOT}
)

include_directories(${FFI_INCLUDE_DIRS})

if(WIN32 AND NOT MINGW)
    # For MSVC builds, define FFI_STATIC_BUILD to disable dllimport/dllexport
    # entirely since we statically link libffi into ring_cffi
    add_definitions(-DFFI_STATIC_BUILD)
endif()
if (NOT FFI_USE_SHARED_LIBS)
    add_definitions(-DFFI_BUILDING)
endif()
if((BUILD_SHARED_LIBS OR FFI_USE_SHARED_LIBS) AND WIN32)
    add_definitions(-DFFI_BUILDING_DLL)
endif()

set(FFI_SOURCES
    ${FFI_ROOT}/src/closures.c
    ${FFI_ROOT}/src/prep_cif.c
    ${FFI_ROOT}/src/types.c
    ${FFI_ROOT}/src/tramp.c)

if ("${TARGET}" STREQUAL "ARM_WIN64" OR "${TARGET}" STREQUAL "ARM64")
    set(FFI_SOURCES
        ${FFI_SOURCES}
        ${FFI_ROOT}/src/aarch64/ffi.c)
elseif("${TARGET}" STREQUAL "ARM_WIN32" OR "${TARGET}" STREQUAL "ARM")
    set(FFI_SOURCES
        ${FFI_SOURCES}
        ${FFI_ROOT}/src/arm/ffi.c)
else()
    set(FFI_SOURCES
        ${FFI_SOURCES}
        ${FFI_ROOT}/src/java_raw_api.c
        ${FFI_ROOT}/src/raw_api.c)
    if("${TARGET}" STREQUAL "X86_WIN32" OR "${TARGET}" STREQUAL "X86_DARWIN" OR "${TARGET}" STREQUAL "X86")
        set(FFI_SOURCES
            ${FFI_SOURCES}
            ${FFI_ROOT}/src/x86/ffi.c)
    elseif("${TARGET}" STREQUAL "X86_WIN64")
        set(FFI_SOURCES
            ${FFI_SOURCES}
            ${FFI_ROOT}/src/x86/ffiw64.c)
    elseif("${TARGET}" STREQUAL "X86_64")
        set(FFI_SOURCES
            ${FFI_SOURCES}
            ${FFI_ROOT}/src/x86/ffi64.c
            ${FFI_ROOT}/src/x86/ffiw64.c)
    endif()
endif()

macro(ffi_add_assembly ASMFILE)
    get_filename_component(ASMFILE_FULL "${ASMFILE}" ABSOLUTE)
    if(MSVC)
        if ("${TARGET}" STREQUAL "ARM_WIN64")
            set(ASSEMBLER_EXE armasm64)
            set(ASM_FLAGS "")
        elseif ("${TARGET}" STREQUAL "ARM_WIN32")
            set(ASSEMBLER_EXE armasm)
            set(ASM_FLAGS "")
        elseif(CMAKE_SIZEOF_VOID_P EQUAL 4)
            set(ASSEMBLER_EXE ml)
            set(ASM_FLAGS /safeseh /c /Zi)
        else()
            set(ASSEMBLER_EXE ml64)
            set(ASM_FLAGS /c /Zi)
        endif()

        # Find the actual path to the assembler
        find_program(ARCH_ASSEMBLER_PATH ${ASSEMBLER_EXE})
        if(NOT ARCH_ASSEMBLER_PATH)
            message(FATAL_ERROR "Could not find assembler: ${ASSEMBLER_EXE}. Ensure MSVC dev environment is initialized.")
        endif()

        get_filename_component(ARCH_ASM_NAME "${ASMFILE_FULL}" NAME_WE)

        # 1. Preprocess
        execute_process(
            COMMAND ${CMAKE_C_COMPILER} /nologo /EP /I. /Iinclude /I${FFI_ROOT}/include "${ASMFILE_FULL}"
            WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}
            OUTPUT_FILE ${ARCH_ASM_NAME}.asm
            RESULT_VARIABLE retcode
        )
        if(NOT ${retcode} STREQUAL "0")
            message(FATAL_ERROR "Preprocessing failed for ${ASMFILE}")
        endif()

        # 2. Assemble using full path to assembler
        execute_process(
            COMMAND ${ARCH_ASSEMBLER_PATH} ${ASM_FLAGS} ${ARCH_ASM_NAME}.asm
            WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}
            RESULT_VARIABLE retcode
        )
        if(NOT ${retcode} STREQUAL "0")
            message(FATAL_ERROR "Assembly failed for ${ARCH_ASM_NAME}.asm")
        endif()

        list(APPEND FFI_SOURCES ${CMAKE_CURRENT_BINARY_DIR}/${ARCH_ASM_NAME}.obj)
    else()
        list(APPEND FFI_SOURCES ${ASMFILE})
    endif()
endmacro()

# 32-bit x86 targets need -m32 for the assembler even when the C compiler is
# already 32-bit (sysv.S would otherwise be assembled as 64-bit object code)
if("${TARGET}" STREQUAL "X86" OR "${TARGET}" STREQUAL "X86_DARWIN"
   OR "${TARGET}" STREQUAL "X86_FREEBSD")
    set(CMAKE_ASM_FLAGS "${CMAKE_ASM_FLAGS} -m32")
endif()

if("${TARGET}" STREQUAL "X86" OR "${TARGET}" STREQUAL "X86_DARWIN")
    ffi_add_assembly(${FFI_ROOT}/src/x86/sysv.S)
elseif("${TARGET}" STREQUAL "X86_64")
    ffi_add_assembly(${FFI_ROOT}/src/x86/unix64.S)
    ffi_add_assembly(${FFI_ROOT}/src/x86/win64.S)
elseif("${TARGET}" STREQUAL "X86_WIN32")
    if(MSVC)
        ffi_add_assembly(${FFI_ROOT}/src/x86/sysv_intel.S)
    else()
        ffi_add_assembly(${FFI_ROOT}/src/x86/sysv.S)
    endif()
elseif("${TARGET}" STREQUAL "X86_WIN64")
    if(MSVC)
        ffi_add_assembly(${FFI_ROOT}/src/x86/win64_intel.S)
    else()
        ffi_add_assembly(${FFI_ROOT}/src/x86/win64.S)
    endif()
elseif("${TARGET}" STREQUAL "ARM_WIN32")
    if(MSVC)
        ffi_add_assembly(${FFI_ROOT}/src/arm/sysv_msvc_arm32.S)
    else()
        ffi_add_assembly(${FFI_ROOT}/src/arm/sysv.S)
    endif()
elseif("${TARGET}" STREQUAL "ARM")
    ffi_add_assembly(${FFI_ROOT}/src/arm/sysv.S)
elseif("${TARGET}" STREQUAL "ARM_WIN64")
    if(MSVC)
        ffi_add_assembly(${FFI_ROOT}/src/aarch64/win64_armasm.S)
    else()
        ffi_add_assembly(${FFI_ROOT}/src/aarch64/sysv.S)
    endif()
elseif("${TARGET}" STREQUAL "ARM64")
    ffi_add_assembly(${FFI_ROOT}/src/aarch64/sysv.S)
else()
    message(FATAL_ERROR "Target not implemented")
endif()

if(CMAKE_BUILD_TYPE STREQUAL "Debug")
    list(APPEND FFI_SOURCES ${FFI_ROOT}/src/debug.c)
    add_definitions(-DFFI_DEBUG)
endif()

add_library(ffi_static STATIC ${FFI_SOURCES})

# Propagate Release/RelWithDebInfo optimizations to libffi
target_compile_options(ffi_static PRIVATE
    $<$<CONFIG:Release,RelWithDebInfo,MinSizeRel>:
        $<$<C_COMPILER_ID:MSVC>:/O2>
        $<$<NOT:$<C_COMPILER_ID:MSVC>>:-O3>
        -DNDEBUG
    >
)

# Hide libffi internals from the final .so dynsym table (only ring_cffi API should be visible)
if(NOT MSVC)
    target_compile_options(ffi_static PRIVATE -fvisibility=hidden)
endif()

# Enable LTO on libffi so ring_cffi can inline across the static-link boundary
if(LTO_SUPPORTED)
    set_property(TARGET ffi_static PROPERTY INTERPROCEDURAL_OPTIMIZATION TRUE)
endif()

target_include_directories(ffi_static PRIVATE
    ${CMAKE_CURRENT_BINARY_DIR}/include
    ${CMAKE_CURRENT_BINARY_DIR}
    ${FFI_ROOT}/include
    ${FFI_ROOT}
)

if(NOT FFI_USE_SHARED_LIBS)
    target_compile_definitions(ffi_static PRIVATE FFI_BUILDING)
endif()
if((BUILD_SHARED_LIBS OR FFI_USE_SHARED_LIBS) AND WIN32)
    target_compile_definitions(ffi_static PRIVATE FFI_BUILDING_DLL)
endif()

if(CMAKE_SYSTEM_NAME STREQUAL "Windows")
    target_link_libraries(ffi_static PRIVATE ws2_32)
endif()

set_target_properties(ffi_static PROPERTIES
    POSITION_INDEPENDENT_CODE ON
)
