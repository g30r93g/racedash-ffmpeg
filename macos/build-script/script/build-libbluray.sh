#!/bin/sh

# Copyright 2021 Martin Riedl
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# handle arguments
echo "arguments: $@"
SCRIPT_DIR=$1
SOURCE_DIR=$2
TOOL_DIR=$3
CPUS=$4

# load functions
. $SCRIPT_DIR/functions.sh

# load version
VERSION=$(cat "$SCRIPT_DIR/../version/libbluray")
checkStatus $? "load version failed"
echo "version: $VERSION"

# start in working directory
cd "$SOURCE_DIR"
checkStatus $? "change directory failed"
mkdir "libbluray"
checkStatus $? "create directory failed"
cd "libbluray/"
checkStatus $? "change directory failed"

# download source
download https://download.videolan.org/pub/videolan/libbluray/$VERSION/libbluray-$VERSION.tar.xz "libbluray.tar.xz"
checkStatus $? "download failed"

# unpack
tar -xf "libbluray.tar.xz"
checkStatus $? "unpack failed"

# prepare python3 virtual environment / meson
prepareMeson

# prepare build
cd "libbluray-$VERSION/"
checkStatus $? "change directory failed"
mkdir build && cd build
checkStatus $? "prepare build directory failed"
meson setup --prefix "$TOOL_DIR" --libdir=lib --default-library=static ..
checkStatus $? "configuration failed"

# build
ninja -v -j $CPUS -C .
checkStatus $? "build failed"

# install
ninja -v -C . install
checkStatus $? "installation failed"
