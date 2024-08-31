# Vulkan Layers and Drivers

vulkan layers are found and loaded by the vulkan loader (see the Vulkan-Loader repository)
these layers are searched for in specific directories, but can also be manually specified using
environment variables:

for example:
VK_ADD_LAYER_PATH=/Users/arjonagelhout/Documents/Experiments/metal-experiment/build/debug/external/build_vulkan_validation_layers-prefix/share/vulkan/explicit_layer.d

this layer is built from source in this experiment, and then installed in a specific directory.
this creates two files:
1. share/vulkan/explicit_layer.d/VkLayer_khronos_validation.json
2. lib/libVkLayer_khronos_validation.dylib

the dylib is loaded on runtime by the vulkan loader.
when calling a function, such as device.createFramebuffer(),
it gets passed through each layer, which each can perform additional functionality before passing it to the following layer
until reaching the actual driver

now, let's add the moltenVK dylib and icd
this is the driver that gets loaded by the vulkan loader
for this, we should specify the driver in the environment variables via VK_ADD_DRIVER_FILES (see https://github.com/KhronosGroup/Vulkan-Loader/blob/main/docs/LoaderInterfaceArchitecture.md#table-of-debug-environment-variables)
e.g.:
VK_ADD_DRIVER_FILES=/Users/arjonagelhout/Documents/Experiments/metal-experiment/external/MoltenVK/Package/Debug/MoltenVK/dylib/macOS/MoltenVK_icd.json