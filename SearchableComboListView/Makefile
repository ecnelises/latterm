# Code signing: disabled by default (contributor-friendly).
# Use SIGNED=1 to build with the project's signing identity.
ifndef SIGNED
  SIGNING_FLAGS = CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
endif

# Latterm targets Apple Silicon only.
ARCH_FLAGS = ARCHS="arm64" ONLY_ACTIVE_ARCH=YES

all: force
	rm -rf SearchableComboListView.framework
	xcodebuild -target SearchableComboListView -configuration Release 'CONFIGURATION_BUILD_DIR=$$(SRCROOT)/Build/$$(CONFIGURATION)' $(SIGNING_FLAGS) $(ARCH_FLAGS)
	mv build/Release/SearchableComboListView.framework .

force:
