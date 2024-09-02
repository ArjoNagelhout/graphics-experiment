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

I now used the android sample project that interfaces with a compiled native C++ static library. 

# How to get SDL working:
See the [README-android.md](../external/SDL/docs/README-android.md)

JNI (Java Native Interface) needed

We copy the project structure from [SDL/android-project](../external/SDL/android-project) and create
symlinks. 

jni folder is copied from the `external/SDL/android-project/app/jni`

## Symlink 1 - java libsdl wrapper

```shell
cd platforms/android/app/src/main/
mkdir java/org/
cd java/org
ln -s ../../../../../../../external/SDL/android-project/app/src/main/java/org/libsdl
```

## Symlink 2 - JNI external folder
```shell
cd platforms/android/app/jni
ln -s ../../../../external
```

## Symlink 3 - JNI src_vulkan folder
```shell
cd platforms/android/app/jni
ln -s ../../../../src_vulkan
```

## Gradle + Cmake
https://developer.android.com/ndk/guides/cmake.html#gradle

Warning: two separate `externalNativeBuild`.

- arguments can only be added to inside a `config` or `build type`. 
- The one directly inside the `android` object does not accept arguments. 

## How to get shaderc working in the NDK
https://developer.android.com/ndk/guides/graphics/shader-compilers#%E2%80%9Dgradle%E2%80%9D

Where is the NDK / SDK installed? -> on macOS `~/Library/Android/sdk`

So the commands to run are (replace the version with the current ndk version): 
```shell
cd ~/Library/Android/sdk/ndk/26.1.10909125/sources/third_party/shaderc/
../../../ndk-build NDK_PROJECT_PATH=. APP_BUILD_SCRIPT=Android.mk \
APP_STL:=c++_shared APP_ABI=all libshaderc_combined
```

Okay, it's now compiling. 

Sample code for including the library using cmake target_link_libraries:
https://github.com/android/ndk-samples/blob/master/hello-libs/app/src/main/cpp/CMakeLists.txt