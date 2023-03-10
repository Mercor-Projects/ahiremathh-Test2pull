file(GLOB_RECURSE PRE_HEADERS RELATIVE ${CMAKE_CURRENT_SOURCE_DIR} pre/*.h)

# We need to add the SDK directories on OS X, and perhaps other operating
# systems.
set(gen_cflags)
foreach(gen_include ${CMAKE_C_IMPLICIT_INCLUDE_DIRECTORIES})
  list(APPEND gen_cflags ${CMAKE_INCLUDE_FLAG_C}${gen_include})
endforeach()

get_directory_property(gen_cdefs COMPILE_DEFINITIONS)
foreach(gen_cdef ${gen_cdefs})
  if(NOT ${gen_cdef} MATCHES "INCLUDE_GENERATED_DECLARATIONS")
    list(APPEND gen_cflags "-D${gen_cdef}")
  endif()
endforeach()

foreach(hfile ${PRE_HEADERS})
  string(REGEX REPLACE ^pre/ post/ post_hfile ${hfile})
  get_filename_component(hdir ${CMAKE_CURRENT_BINARY_DIR}/${post_hfile} DIRECTORY)
  file(MAKE_DIRECTORY ${hdir})
  add_custom_command(
    OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/${post_hfile}
    COMMAND ${CMAKE_C_COMPILER} -std=c99 -E -P
      ${CMAKE_CURRENT_SOURCE_DIR}/${hfile}
      ${gen_cflags}
      -o ${CMAKE_CURRENT_BINARY_DIR}/${post_hfile})
  list(APPEND POST_HEADERS ${post_hfile})
endforeach()

add_custom_target(unittest-headers DEPENDS ${POST_HEADERS})
set_target_properties(unittest-headers PROPERTIES FOLDER test)
