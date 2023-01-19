cmake_minimum_required(VERSION 3.10)

set(HEX_ALPHABET "0123456789abcdef")

function(ConvertToHex dec hex)
  while(dec GREATER 0)
    math(EXPR _val "${dec} % 16")
    math(EXPR dec "${dec} / 16")
    string(SUBSTRING ${HEX_ALPHABET} ${_val} 1 _val)
    set(_res "${_val}${_res}")
  endwhile()
  # Pad the result with the number of zeros
  # specified by the optional third argument
  if(${ARGC} EQUAL 3)
    set(padding ${ARGV2})
    string(LENGTH ${_res} _resLen)
    if(_resLen LESS ${padding})
      math(EXPR _neededPadding "${padding} - ${_resLen}")
      foreach(i RANGE 1 ${_neededPadding})
        set(_res "0${_res}")
      endforeach()
    endif()
  endif()
  set(${hex} "0x${_res}" PARENT_SCOPE)
endfunction()

function(ConvertFromHex hex dec)
  string(TOLOWER ${hex} hex)
  string(LENGTH "${hex}" _strlen)
  set(_res 0)
  while(_strlen GREATER 0)
    math(EXPR _res "${_res} * 16")
    string(SUBSTRING "${hex}" 0 1 NIBBLE)
    string(SUBSTRING "${hex}" 1 -1 hex)
    string(FIND ${HEX_ALPHABET} ${NIBBLE} value)
    if(value EQUAL -1)
      message(FATAL_ERROR "Invalid hex character '${NIBBLE}'")
    endif()
    math(EXPR _res "${_res} + ${value}")
    string(LENGTH "${hex}" _strlen)
  endwhile()
  set(${dec} ${_res} PARENT_SCOPE)
endfunction()

# Based on http://www.json.org/JSON_checker/utf8_decode.c
function(DecodeUtf8 hexBytes codePoint)
  string(SUBSTRING ${hexBytes} 0 2 hexByte1)
  ConvertFromHex(${hexByte1} byte1)
  # Zero continuations (0 to 127)
  math(EXPR out "${byte1} & 128")
  if(out EQUAL 0)
    set(${codePoint} ${byte1} PARENT_SCOPE)
    return()
  endif()
  # One continuation (128 to 2047)
  math(EXPR out "${byte1} & 224")
  if(out EQUAL 192)
    string(SUBSTRING ${hexBytes} 2 2 hexByte2)
    ConvertFromHex(${hexByte2} byte2)
    math(EXPR result "((${byte1} & 31) << 6) | ${byte2}")
    if(result GREATER 127)
      set(${codePoint} ${result} PARENT_SCOPE)
      return()
    endif()
  else()
    # Two continuations (2048 to 55295 and 57344 to 65535)
    math(EXPR result "${byte1} & 240")
    if(result EQUAL 224)
      string(SUBSTRING ${hexBytes} 2 2 hexByte2)
      string(SUBSTRING ${hexBytes} 4 2 hexByte3)
      ConvertFromHex(${hexByte2} byte2)
      ConvertFromHex(${hexByte3} byte3)
      math(EXPR result "${byte2} | ${byte3}")
      if(result GREATER -1)
        math(EXPR result "((${byte1} & 15) << 12) | (${byte2} << 6) | ${byte3}")
        if((result GREATER 2047) AND (result LESS 55296 OR result GREATER 57343))
          set(${codePoint} ${result} PARENT_SCOPE)
          return()
        endif()
      endif()
    else()
      # Three continuations (65536 to 1114111)
      math(EXPR result "${byte1} & 248")
      if(result EQUAL 224)
        string(SUBSTRING ${hexBytes} 2 2 hexByte2)
        string(SUBSTRING ${hexBytes} 4 2 hexByte3)
        string(SUBSTRING ${hexBytes} 6 2 hexByte4)
        ConvertFromHex(${hexByte2} byte2)
        ConvertFromHex(${hexByte3} byte3)
        ConvertFromHex(${hexByte4} byte4)
        math(EXPR result "${byte2} | ${byte3} | ${byte4}")
        if(result GREATER -1)
          math(EXPR result "((c & 7) << 18) | (c1 << 12) | (c2 << 6) | c3")
          if((result GREATER 65535) AND (result LESS 1114112))
            set(${codePoint} ${result} PARENT_SCOPE)
            return()
          endif()
        endif()
      endif()
    endif()
  endif()
  message(FATAL_ERROR "Invalid UTF-8 encoding")
endfunction()

set(inputFile ${CMAKE_ARGV3})
set(outputFile ${CMAKE_ARGV4})
# Get the file contents in text and hex-encoded format because
# CMake doesn't provide functions for converting between the two
file(READ "${inputFile}" contents)
file(READ "${inputFile}" hexContents HEX)

# Convert the text contents into a list of lines by escaping
# the list separator ';' and then replacing new line characters
# with the list separator
string(REGEX REPLACE ";" "\\\\;" contents ${contents})
string(REGEX REPLACE "\n" ";" contents ${contents})

get_filename_component(encname ${inputFile} NAME_WE)
set(output
  "static const struct StaticTableEncoding encoding_${encname} = {\n"
  "  { .decode = &decode_table },\n"
  "  {")
set(hexIndex 0)
foreach(line ${contents})
  string(LENGTH ${line} lineLength)
  # Convert "A" to 0x41
  string(FIND ${line} "\"" beginQuote)
  if(NOT ${beginQuote} EQUAL -1)
    string(FIND ${line} "\"" endQuote REVERSE)
    if(${beginQuote} EQUAL ${endQuote})
      message(FATAL_ERROR "Line contains only one quote")
    endif()
    math(EXPR beginHexQuote "${hexIndex} + (${beginQuote} + 1)*2")
    math(EXPR endHexQuote "${hexIndex} + (${endQuote} + 1)*2")
    math(EXPR quoteLen "${endHexQuote} - ${beginHexQuote} - 1")
    string(SUBSTRING ${hexContents} ${beginHexQuote} ${quoteLen} hexQuote)
    DecodeUtf8(${hexQuote} codePoint)
    ConvertToHex(${codePoint} hexCodePoint 4)
    STRING(REGEX REPLACE "\"(.+)\"" ${hexCodePoint} line ${line})
  endif()
  # Strip comment
  string(REGEX REPLACE "[ \t\n]*#.*" "" line ${line})
  # Convert 3/1 to [0x31]
  string(REGEX REPLACE "^([0-9]+)/([0-9]+).*" "\\1;\\2" numbers ${line})
  list(GET numbers 0 upperBits)
  list(GET numbers 1 lowerBits)
  math(EXPR res "${upperBits}*16 + ${lowerBits}")
  ConvertToHex(${res} hex 2)
  string(REGEX REPLACE "^([0-9]+)/([0-9]+)" "[${hex}]" line ${line})
  # Convert U+0041 to 0x0041
  string(REPLACE "U+" "0x" line ${line})
  # Indent and append a comma
  set(line "    ${line},")
  set(output "${output}\n${line}")
  # Increment the index by the number of characters in the line,
  # plus one for the new line character then multiple by two for the hex digit index
  math(EXPR hexIndex "${hexIndex} + 2*(${lineLength} + 1)")
endforeach()
set(output "${output}\n"
  "  }\n"
  "}\;\n")

file(WRITE ${outputFile} ${output})
