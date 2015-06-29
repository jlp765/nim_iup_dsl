# nim_iup_dsl
Nim Domain Specific Language for building a GUI in the NIM programing language using the IUP GUI library

# Requirements

Requires V3.0 of IUP library  (iup30.dll for win or libiup3.0.so for Linux).
It probably works with lower versions, but uses some V3.0 or higher functionality.

Unfortunately, the current IUP wrapper for Nim is IUP V3.0 or older, 
so DO NOT use newer version of IUP until the wrapper in Nim is updated.

# Limitations

This is the first draft, so has had limited testing.  

Only tested on win7 64 bit, so far.

It does not include the canvas which requires the iupcd library.

It covers a fair proportion of widgets, but not all (yet).\
Menu and menu items yet to be added.

# Example code  

the iup_dsl.nim is INCLUDED rather than imported.
See the iup_dsl_test.nim file.

