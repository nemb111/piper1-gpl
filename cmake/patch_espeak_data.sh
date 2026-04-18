#!/bin/bash
# Patch espeak-ng source for WASM build:
# 1. Copy pre-built data into espeak-ng source directory
# 2. Replace cmake/data.cmake with a version that uses pre-built data
#
# Arguments: $1 = SOURCE_DIR, $2 = PREBUILT_DATA_DIR

SRC_DIR="$1"
PREBUILT="$2"

# No prebuilt data provided (native build) — no-op
if [ -z "$PREBUILT" ]; then
    exit 0
fi

if [ -z "$SRC_DIR" ]; then
    echo "Usage: $0 <SOURCE_DIR> <PREBUILT_DATA_DIR>"
    exit 1
fi

echo "Patching espeak-ng source in $SRC_DIR with pre-built data from $PREBUILT"

# Copy pre-built data files into espeak-ng-data (merged with existing src files)
# First copy compiled data files
for f in "$PREBUILT"/*; do
    bn=$(basename "$f")
    # Skip lang and voices dirs - they come from source
    if [ "$bn" = "lang" ] || [ "$bn" = "voices" ]; then
        continue
    fi
    # Copy compiled data files (non-directory files and compiled dicts)
    if [ -f "$f" ]; then
        if [ ! -f "$SRC_DIR/espeak-ng-data/$bn" ]; then
            cp "$f" "$SRC_DIR/espeak-ng-data/"
        fi
    elif [ -d "$f" ]; then
        # Copy subdirectories like transliterate
        if [ ! -d "$SRC_DIR/espeak-ng-data/$bn" ]; then
            cp -r "$f" "$SRC_DIR/espeak-ng-data/"
        fi
    fi
done

# Create replacement data.cmake that copies pre-built files instead of compiling
cat > "$SRC_DIR/cmake/_skip_data.cmake" << 'SKIPDATAEOF'
# Dummy data target so tests don't fail
add_custom_target(data)

set(DATA_DIST_ROOT ${CMAKE_CURRENT_BINARY_DIR})
set(DATA_DIST_ROOT ${CMAKE_CURRENT_BINARY_DIR})
set(DATA_DIST_DIR ${DATA_DIST_ROOT}/espeak-ng-data)

# Copy pre-built data files into build directory
file(MAKE_DIRECTORY "${DATA_DIST_DIR}")

# Copy lang/voices from source
file(COPY "${CMAKE_CURRENT_SOURCE_DIR}/espeak-ng-data/lang" DESTINATION "${DATA_DIST_DIR}/")
file(COPY "${CMAKE_CURRENT_SOURCE_DIR}/espeak-ng-data/voices/!v" DESTINATION "${DATA_DIST_DIR}/voices")

# Copy pre-built compiled data files
file(GLOB _COMPILED "${CMAKE_CURRENT_SOURCE_DIR}/espeak-ng-data/*")
foreach(_f ${_COMPILED})
  get_filename_component(_bn "${_f}" NAME)
  if(IS_DIRECTORY "${_f}")
    if(NOT "${_bn}" STREQUAL "lang" AND NOT "${_bn}" STREQUAL "voices")
      file(COPY "${_f}" DESTINATION "${DATA_DIST_DIR}/")
    endif()
  elseif(NOT "${_bn}" STREQUAL "lang" AND NOT "${_bn}" STREQUAL "voices")
    # Only copy known compiled data file patterns
    if(
      "${_bn}" STREQUAL "phondata" OR
      "${_bn}" STREQUAL "phondata-manifest" OR
      "${_bn}" STREQUAL "phonindex" OR
      "${_bn}" STREQUAL "phontab" OR
      "${_bn}" STREQUAL "intonations" OR
      "${_bn}" STREQUAL "tonevalues" OR
      "${_bn}" STREQUAL "number" OR
      "${_bn}" MATCHES "_dict" OR
      "${_bn}" MATCHES "cmn_" OR
      "${_bn}" MATCHES "extra_"
    )
      file(COPY "${_f}" DESTINATION "${DATA_DIST_DIR}/")
    endif()
  endif()
endforeach()
SKIPDATAEOF

# Replace include(cmake/data.cmake) with include(cmake/_skip_data.cmake)
sed -i 's/include(cmake\/data\.cmake)/include(cmake\/_skip_data.cmake)/' "$SRC_DIR/CMakeLists.txt"

echo "Patch applied successfully"
