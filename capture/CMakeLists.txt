cmake_minimum_required(VERSION 3.21)
project(mango-overview-capture LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_SKIP_INSTALL_RPATH ON)

# Only public Qt modules: no Qt private headers, so Qt 6 minor updates need no rebuild.
find_package(Qt6 6.5 REQUIRED COMPONENTS Core Gui Quick)
qt_policy(SET QTP0001 NEW)
find_package(PkgConfig REQUIRED)
pkg_check_modules(WAYLAND REQUIRED IMPORTED_TARGET wayland-client)
pkg_get_variable(WL_PROTOCOLS_DIR wayland-protocols pkgdatadir)
pkg_get_variable(WL_SCANNER wayland-scanner wayland_scanner)

# Generate C bindings for the three staging protocols we speak.
set(PROTOCOLS
	staging/ext-foreign-toplevel-list/ext-foreign-toplevel-list-v1.xml
	staging/ext-image-capture-source/ext-image-capture-source-v1.xml
	staging/ext-image-copy-capture/ext-image-copy-capture-v1.xml
)
set(PROTO_SOURCES)
foreach(proto ${PROTOCOLS})
	get_filename_component(name ${proto} NAME_WE)
	set(xml ${WL_PROTOCOLS_DIR}/${proto})
	set(header ${CMAKE_CURRENT_BINARY_DIR}/${name}-client-protocol.h)
	set(code ${CMAKE_CURRENT_BINARY_DIR}/${name}-protocol.c)
	add_custom_command(OUTPUT ${header} COMMAND ${WL_SCANNER} client-header ${xml} ${header} DEPENDS ${xml})
	add_custom_command(OUTPUT ${code} COMMAND ${WL_SCANNER} private-code ${xml} ${code} DEPENDS ${xml})
	list(APPEND PROTO_SOURCES ${header} ${code})
endforeach()

qt_add_qml_module(mangooverviewcapture
	URI MangoOverview.Capture
	VERSION 1.0
	PLUGIN_TARGET mangooverviewcapture
	OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/qml/MangoOverview/Capture
	SOURCES
		captureclient.hpp captureclient.cpp
		windowcapture.hpp windowcapture.cpp
		swipetracker.hpp swipetracker.cpp
		${PROTO_SOURCES}
)

target_include_directories(mangooverviewcapture PRIVATE ${CMAKE_CURRENT_BINARY_DIR})
target_link_libraries(mangooverviewcapture PRIVATE Qt6::Core Qt6::Gui Qt6::Quick PkgConfig::WAYLAND)

include(GNUInstallDirs)
install(TARGETS mangooverviewcapture LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}/qt6/qml/MangoOverview/Capture)
install(FILES
	${CMAKE_BINARY_DIR}/qml/MangoOverview/Capture/qmldir
	${CMAKE_BINARY_DIR}/qml/MangoOverview/Capture/mangooverviewcapture.qmltypes
	DESTINATION ${CMAKE_INSTALL_LIBDIR}/qt6/qml/MangoOverview/Capture)
