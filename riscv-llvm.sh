#!/usr/bin/env bash
sudo apt-get -y install \
  binutils build-essential libtool texinfo \
  gzip zip unzip patchutils curl git \
  make cmake ninja-build automake bison flex gperf \
  grep sed gawk python3 bc \
  zlib1g-dev libexpat1-dev libmpc-dev \
  libglib2.0-dev libfdt-dev libpixman-1-dev 

mkdir -p riscv-toolchain
cd riscv-toolchain

mkdir -p  _install
export PATH=`pwd`/_install/bin:$PATH
hash -r

# gcc, binutils, newlib
git clone --recursive https://github.com/riscv/riscv-gnu-toolchain
pushd riscv-gnu-toolchain
./configure --prefix=`pwd`/../_install --enable-multilib
make -j`nproc`

# qemu
make -j`nproc` build-qemu
popd

# LLVM
git clone --recursive https://github.com/llvm/llvm-project.git riscv-llvm
#git clone https://github.com/sifive/riscv-llvm
pushd riscv-llvm
ln -s ../../clang llvm/tools || true
rm -rf _build
mkdir _build
cd _build
#enable_projects="clang;clang-tools-extra;lldb;lld;mlir"
enable_projects="clang;clang-tools-extra;lldb;lld;mlir"
#enable_runtimes="libcxx;libcxxabi;libunwind;compiler-rt"
#	-DLLVM_ENABLE_RUNTIMES=${enable_runtimes} \

cmake -G Ninja -DCMAKE_BUILD_TYPE="Release" \
	-DLLVM_ENABLE_PROJECTS=${enable_projects} \
	-DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ -DLLVM_ENABLE_LLD=ON \
  -DBUILD_SHARED_LIBS=True -DLLVM_USE_SPLIT_DWARF=True \
  -DLLVM_DISABLE_ABI_BREAKING_CHECKS_ENFORCING=OFF \
	-DCMAKE_INSTALL_PREFIX="../../_install" \
	-DLLVM_OPTIMIZED_TABLEGEN=True -DLLVM_BUILD_TESTS=False \
	-DDEFAULT_SYSROOT="../../_install/riscv64-unknown-elf" \
	-DLLVM_DEFAULT_TARGET_TRIPLE="riscv64-unknown-elf" \
	-DLLVM_TARGETS_TO_BUILD="RISCV" \
	../llvm
#cmake --build . --target check-llvm
cmake --build . --target install
popd

# Sanity test your new RISC-V LLVM
cat >hello.c <<END
#include <stdio.h>

int main(){
  printf("Hello RISCV!\n");
  return 0;
}
END

# 32 bit
clang -O -c hello.c --target=riscv32
riscv64-unknown-elf-gcc hello.o -o hello -march=rv32imac -mabi=ilp32
qemu-riscv32 hello

# 64 bit
clang -O -c hello.c --target=riscv64
riscv64-unknown-elf-gcc hello.o -o hello -march=rv64imac -mabi=lp64
qemu-riscv64 hello

cat >hello.cpp <<END
#include <iostream>

int main()
{
  std::cout << "Hello RISCV c++!" << std::endl;
  return 0;
}
END

# 32 bit
clang++ -O -c hello.cpp --target=riscv32 --sysroot=_install/riscv64-unknown-elf/ --gcc-toolchain=_install
riscv64-unknown-elf-g++ hello.o -o hello -march=rv32imac -mabi=ilp32
qemu-riscv32 hello

# 64 bit
clang++ -O -c hello.cpp --target=riscv64 --sysroot=_install/riscv64-unknown-elf/ --gcc-toolchain=_install
riscv64-unknown-elf-g++ hello.o -o hello -march=rv64imac -mabi=lp64
qemu-riscv64 hello

cat >hello.ll <<END
@string = private constant [15 x i8] c"Hello, RISCV!\0A\00"

declare i32 @puts(i8*)

define i32 @main() {
  %address = getelementptr [15 x i8], [15 x i8]* @string, i64 0, i64 0
  call i32 @puts(i8* %address)
  ret i32 0
}
END

clang++ --target=riscv32 hello.cpp -c -emit-llvm -o hello.bc --sysroot=_install/riscv64-unknown-elf/ --gcc-toolchain=_install
llc -filetype=obj hello.bc -o hello.riscvrel
riscv64-unknown-elf-g++ hello.riscvrel -o hello -march=rv32imac -mabi=ilp32
qemu-riscv32 hello
