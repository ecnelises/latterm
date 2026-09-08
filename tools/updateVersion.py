#!/opt/homebrew/bin/python3
# Get it from:
# https://www.python.org/ftp/python/3.9.13/python-3.9.13-macos11.pkg
# Install the package and then do
# /Library/Frameworks/Python.framework/Versions/3.9/bin/pip3 install pyobjc

# We can't use the python in $PATH because xcode ships with Python and we need one that has pybobjc.

import os

try:
    del os.environ["MACOSX_DEPLOYMENT_TARGET"]
except KeyError:
    pass
from Foundation import NSMutableDictionary

version = open("version.txt").read().strip()

def update(path):
    plist = NSMutableDictionary.dictionaryWithContentsOfFile_(path)
    print("Updating versions:", path, version)
    if not plist:
        print(f"WARNING - FAILED TO LOAD PLIST from {path}")
    plist["CFBundleShortVersionString"] = version
    plist["CFBundleGetInfoString"] = version
    plist["CFBundleVersion"] = version
    plist.writeToFile_atomically_(path, 1)
    print(plist)


# Update the main app's plist

srcDir = os.environ["SRCROOT"]
print(f"SRCROOT={srcDir}")

path = os.path.join(srcDir, "plists", "iTerm2.plist")

update(path)
