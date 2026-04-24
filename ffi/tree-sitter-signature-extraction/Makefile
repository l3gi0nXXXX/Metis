# Makefile for building static and dynamic libraries

# Detect OS
ifeq ($(OS),Windows_NT)
    OS_NAME := Windows
    STATIC_LIB := libsignature_extractor.lib
    DYNAMIC_LIB := libsignature_extractor.dll
else
    OS_NAME := $(shell uname -s)
    ifeq ($(OS_NAME),Linux)
        STATIC_LIB := libsignature_extractor.a
        DYNAMIC_LIB := libsignature_extractor.so
    else
        STATIC_LIB := libsignature_extractor.a
        DYNAMIC_LIB := libsignature_extractor.dylib
    endif
endif

# Directories
SRC_DIR = src
OBJ_DIR = obj
TS_DIR = tree-sitter
TS_PYTHON_DIR = tree-sitter-python
TS_JAVA_DIR = tree-sitter-java

# Source files
SOURCES = $(SRC_DIR)/signature_extractor.c \
          $(SRC_DIR)/signature_extractor_python.c \
          $(SRC_DIR)/signature_extractor_java.c \
          $(SRC_DIR)/utils.c \
          $(SRC_DIR)/signature_node.c \
          $(TS_DIR)/lib/src/lib.c \
          $(TS_PYTHON_DIR)/src/parser.c \
          $(TS_PYTHON_DIR)/src/scanner.c \
          $(TS_JAVA_DIR)/src/parser.c

# Object files
OBJECTS = $(SOURCES:$(SRC_DIR)/%.c=$(OBJ_DIR)/$(SRC_DIR)/%.o)
OBJECTS := $(OBJECTS:$(TS_DIR)/lib/src/%.c=$(OBJ_DIR)/$(TS_DIR)/lib/src/%.o)
OBJECTS := $(OBJECTS:$(TS_PYTHON_DIR)/src/%.c=$(OBJ_DIR)/$(TS_PYTHON_DIR)/src/%.o)
OBJECTS := $(OBJECTS:$(TS_JAVA_DIR)/src/%.c=$(OBJ_DIR)/$(TS_JAVA_DIR)/src/%.o)

# Include directories
INCLUDES = -I$(TS_DIR)/lib/include -I$(TS_DIR)/lib/src \
           -I$(TS_PYTHON_DIR)/src -I$(TS_JAVA_DIR)/src

# Default target
all: static dynamic

# Create directories
$(shell mkdir -p $(OBJ_DIR)/$(SRC_DIR) \
                 $(OBJ_DIR)/$(TS_DIR)/lib/src \
                 $(OBJ_DIR)/$(TS_PYTHON_DIR)/src \
                 $(OBJ_DIR)/$(TS_JAVA_DIR)/src)

# Compile source files to object files
$(OBJ_DIR)/%.o: %.c
	gcc -c -DBUILDING_STATIC $(INCLUDES) $< -o $@

# Create static library
static: $(STATIC_LIB)
$(STATIC_LIB): $(OBJECTS)
	ar rcs $(STATIC_LIB) $(OBJECTS)

# Create dynamic library
dynamic: $(DYNAMIC_LIB)
$(DYNAMIC_LIB):
ifeq ($(OS_NAME),Windows)
	gcc -shared -DBUILDING_DLL $(INCLUDES) $(SOURCES) -o $(DYNAMIC_LIB)
else ifeq ($(OS_NAME),Linux)
	gcc -shared -fPIC -DBUILDING_DLL $(INCLUDES) $(SOURCES) -o $(DYNAMIC_LIB)
else
	gcc -shared -fPIC -DBUILDING_DLL $(INCLUDES) $(SOURCES) -o $(DYNAMIC_LIB)
endif

# Clean build artifacts
clean:
	rm -rf $(OBJ_DIR) $(STATIC_LIB) $(DYNAMIC_LIB)

.PHONY: all static dynamic clean