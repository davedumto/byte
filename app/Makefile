# Byte: native shell (rootless, iOS 15, arm64). Build with: make package
TARGET := iphone:clang:16.5:15.0
ARCHS := arm64
THEOS_PACKAGE_SCHEME := rootless
INSTALL_TARGET_PROCESSES := Byte

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME := Byte
Byte_FILES := $(wildcard Sources/*.swift)
Byte_FRAMEWORKS := UIKit WebKit Network
Byte_SWIFTFLAGS := -swift-version 5
Byte_CODESIGN_FLAGS := -Sentitlements.plist

include $(THEOS_MAKE_PATH)/application.mk

# The 3D world is built from ../byte-world and copied into the app bundle as Resources/world/.
# Only the shipped files go in: index.html and the fonts with their licences (no ?fps tooling needed).
WORLD_SRC := ../byte-world
WORLD_DST := Resources/world

before-all::
	$(ECHO_NOTHING)$(WORLD_SRC)/build.sh$(ECHO_END)
	$(ECHO_NOTHING)rm -rf $(WORLD_DST) && mkdir -p $(WORLD_DST)/fonts$(ECHO_END)
	$(ECHO_NOTHING)cp $(WORLD_SRC)/index.html $(WORLD_DST)/$(ECHO_END)
	$(ECHO_NOTHING)cp $(WORLD_SRC)/fonts/*.woff2 $(WORLD_SRC)/fonts/*-OFL.txt $(WORLD_DST)/fonts/$(ECHO_END)

test::
	./test.sh
