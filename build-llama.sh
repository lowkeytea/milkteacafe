#!/bin/bash

# Detect architecture

ARCH=$(uname -m)
BUILD_DIR="build"

cd llama.cpp
# Clean previous build
rm -rf $BUILD_DIR
mkdir $BUILD_DIR
cd $BUILD_DIR

if [ "$ARCH" = "arm64" ]; then
    echo "Building for Apple Silicon (arm64)..."
cmake -G Xcode .. \
  -DBUILD_SHARED_LIBS=OFF \
  -DLLAMA_BUILD_EXAMPLES=OFF \
  -DLLAMA_BUILD_TOOLS=OFF \
  -DLLAMA_BUILD_TESTS=OFF \
  -DLLAMA_BUILD_SERVER=OFF \
  -DGGML_METAL_USE_BF16=ON \
  -DLLAMA_CURL=OFF \
  -DGGML_METAL_EMBED_LIBRARY=ON \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
  -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED=NO \
  -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED=NO \
  -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY="" \
  -DCMAKE_OSX_ARCHITECTURES="arm64" \
   -DCMAKE_XCODE_ATTRIBUTE_TARGETED_DEVICE_FAMILY="1,2"
cmake --build . --config Release -j $(sysctl -n hw.logicalcpu)
else
    echo "Building for Intel Mac (x64)..."
    cmake .. \
        -DLLAMA_FATAL_WARNINGS=ON \
        -DLLAMA_CURL=ON \
        -DGGML_METAL=OFF \
        -DGGML_RPC=ON \
        -DBUILD_SHARED_LIBS=OFF
fi

# Build using all available CPU cores
cmake --build . --config Release -j $(sysctl -n hw.logicalcpu)

# Install system-wide (optional, requires sudo)
sudo cmake --install . --config Release
