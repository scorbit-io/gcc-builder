# CMake Toolchain File for ARM Linux GNUEABIHF with GCC 15
# Usage: cmake -DCMAKE_TOOLCHAIN_FILE=armhf-toolchain.cmake ..

set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR arm)

# Specify the cross compiler
set(CMAKE_C_COMPILER /opt/wrappers/armhf-gcc)
set(CMAKE_CXX_COMPILER /opt/wrappers/armhf-g++)

# Specify the target environment
set(CMAKE_SYSROOT /opt/sysroot)
set(CMAKE_FIND_ROOT_PATH /opt/sysroot)

# Specify additional compiler flags if needed
set(CMAKE_C_FLAGS_INIT "-march=armv7-a -mfpu=neon-vfpv4 -mfloat-abi=hard")
set(CMAKE_CXX_FLAGS_INIT "-march=armv7-a -mfpu=neon-vfpv4 -mfloat-abi=hard")

# Search for programs in the build host directories
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)

# Search for libraries and headers in the target directories
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

# Additional settings for better compatibility
set(CMAKE_C_COMPILER_WORKS 1)
set(CMAKE_CXX_COMPILER_WORKS 1)

# Explicitly set the target triplet
set(CMAKE_C_COMPILER_TARGET arm-linux-gnueabihf)
set(CMAKE_CXX_COMPILER_TARGET arm-linux-gnueabihf)
