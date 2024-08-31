# android

Because Android requires some special integrations and project files,
this folder contains the Android project, which will import the C++
application as a library. 

Otherwise, we would have to build an entire Android project creation 
pipeline, which seems overkill for a singular application. 

https://developer.oculus.com/documentation/native/android/mobile-studio-setup-android/

Use Android Studio

Android SDK Platform, API level 26
Android SDK Build Tools, v 28.0.3 or later
Android NDK

C++ support:
https://developer.android.com/ndk/guides/cpp-support.html
libc++ is used, C++23 is fully supported in the libc++ runtime library