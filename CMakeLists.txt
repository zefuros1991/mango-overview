cmake_minimum_required(VERSION 3.21)
project(mango-overview VERSION 0.1.0 LANGUAGES C CXX)

# The live window preview add-on (a small QML module for stock Quickshell).
add_subdirectory(capture)

include(GNUInstallDirs)
install(PROGRAMS bin/mango-overview DESTINATION ${CMAKE_INSTALL_BINDIR})
install(FILES overview/shell.qml overview/Mango.qml overview/WindowTile.qml overview/Backdrop.qml
	overview/Hyprland.qml
	DESTINATION ${CMAKE_INSTALL_DATADIR}/mango-overview/overview)
install(PROGRAMS overview/wallpaper.sh
	DESTINATION ${CMAKE_INSTALL_DATADIR}/mango-overview/overview)
install(FILES LICENSE DESTINATION ${CMAKE_INSTALL_DATADIR}/licenses/mango-overview)
