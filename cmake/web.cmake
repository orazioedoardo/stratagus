# Building Stratagus for the web, with Emscripten (emcmake cmake ...; cmake --build ... --target stratagus).
#
# The libraries are Emscripten's ports, compiled and linked with -sUSE_* flags instead of found with find_package.
# Lua is the vendored one, whose bindings (tolua.cpp) are generated as the engine builds by a native tolua++: the one
# given with -DSTRATAGUS_HOST_TOLUAPP=<path>, or else one this build compiles with the system's own compiler.
# Off: OpenMP (threads), Theora (videos), stack traces. C++ exceptions are on: the engine throws them as part of normal
# play (a unit dying, for instance), and they abort without it.
#
# The result (stratagus.js and .wasm) is meant to be run by a web page, which calls callMain to start it and keeps the
# user directory ($HOME/.config/stratagus) in IndexedDB: see SyncUserFiles. The game's data is preloaded at / (the
# engine's default data path is the current directory) from the folder given with -DSTRATAGUS_WEB_DATA=<folder>,
# as stratagus.data. The build is relinked when that folder's .stamp file changes (see web_targets).

set(STRATAGUS_WEB_DATA "" CACHE PATH "Folder with the game's data, preloaded into the web build at /")
set(STRATAGUS_WEB_PORTS
	-sUSE_SDL=2 -sUSE_SDL_MIXER=2 -sUSE_SDL_IMAGE=2 -sUSE_LIBPNG=1 -sUSE_ZLIB=1 -sUSE_BZIP2=1 -sUSE_OGG=1 -sUSE_VORBIS=1)

# Called where the dependencies are found: options, compile flags and libraries
macro(web_dependencies)
	set(BUILD_VENDORED_LUA ON)
	set(BUILD_VENDORED_SDL OFF)
	set(BUILD_VENDORED_MEDIA_LIBS OFF)
	set(WITH_OPENMP OFF CACHE BOOL "Compile Stratagus with OpenMP for parallel processing")
	set(WITH_THEORA OFF CACHE BOOL "Compile Stratagus with Theroa video library")
	set(WITH_STACKTRACE OFF CACHE BOOL "Compile Stratagus with StackTrace library")

	add_compile_options(-fexceptions ${STRATAGUS_WEB_PORTS})
	add_link_options(-fexceptions ${STRATAGUS_WEB_PORTS} "-sSDL2_IMAGE_FORMATS=[\"png\"]")
	# Found: the ports put their headers where emcc finds them, and the flags above link them
	foreach(found SDL2 SDL2_MIXER SDL2_IMAGE PNG ZLIB BZIP2 OGGVORBIS)
		set(${found}_FOUND TRUE)
	endforeach()

	vendored_lua()
	if(STRATAGUS_HOST_TOLUAPP)
		set(TOLUA++_APP "${STRATAGUS_HOST_TOLUAPP}")
	else()
		# A native tolua++, built with the system's compiler (an external project doesn't get the toolchain)
		ExternalProject_Add(host_toluapp
			SOURCE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/third-party/lua-5.1.5/
			PREFIX "${CMAKE_CURRENT_BINARY_DIR}/host-lua/"
			CMAKE_ARGS -DCMAKE_BUILD_TYPE=Release -DCMAKE_POLICY_VERSION_MINIMUM=3.5
			BUILD_COMMAND ${CMAKE_COMMAND} --build <BINARY_DIR> --target toluapp
			INSTALL_COMMAND ""
		)
		set(TOLUA++_APP "${CMAKE_CURRENT_BINARY_DIR}/host-lua/src/host_toluapp-build/toluapp")
	endif()
endmacro()

# Called once the targets exist: what the game itself is linked with
macro(web_targets)
	if(NOT STRATAGUS_HOST_TOLUAPP)
		add_dependencies(stratagus_lib host_toluapp)
	endif()
	target_link_options(stratagus PRIVATE
		-sASYNCIFY                    # the engine's blocking loops wait for the browser's next frame (see sdl.cpp)
		-sASYNCIFY_STACK_SIZE=262144
		-sSTACK_SIZE=4194304
		-sALLOW_MEMORY_GROWTH
		-sMAXIMUM_MEMORY=4GB
		-sINVOKE_RUN=0                # the page starts the game, with callMain
		-sEXIT_RUNTIME                # quitting the game calls the page's onExit
		-sEXPORTED_RUNTIME_METHODS=callMain,FS,IDBFS,addRunDependency,removeRunDependency
		-lidbfs.js
	)
	if(STRATAGUS_WEB_DATA)
		target_link_options(stratagus PRIVATE "--preload-file=${STRATAGUS_WEB_DATA}@/"
			# without the .stamp (see below), which is only for the build: its content changes with the data's
			# preparation, not with the data, and would change the package
			"--exclude-file=${STRATAGUS_WEB_DATA}/.stamp")
		# Relink when the data changes. Whatever prepares the data updates a file named .stamp in it when it changes:
		# depending on every file instead isn't possible, as Make can't take names with spaces or parentheses.
		if(EXISTS "${STRATAGUS_WEB_DATA}/.stamp")
			set_property(TARGET stratagus APPEND PROPERTY LINK_DEPENDS "${STRATAGUS_WEB_DATA}/.stamp")
		endif()
	endif()
endmacro()
