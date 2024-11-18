#!/usr/bin/env bash
sudo apt-get install autoconf automake autotools-dev \
  curl python3 python3-pip libmpc-dev libmpfr-dev \
  libgmp-dev gawk build-essential bison flex texinfo \
  gperf libtool patchutils bc zlib1g-dev libexpat-dev \
  ninja-build git cmake libglib2.0-dev libslirp-dev

mkdir -p riscv-toolchain
cd riscv-toolchain

mkdir -p  release
export RISCV=`pwd`/release
export PATH=${RISCV}/bin:$PATH
hash -r

# gcc, binutils, newlib
git clone --recursive https://github.com/riscv/riscv-gnu-toolchain
pushd riscv-gnu-toolchain
./configure --prefix=${RISCV} --enable-multilib --with-sim=spike  --with-arch=rv64gc_zifencei 
make -j`nproc`

# qemu
make -j`nproc` build-qemu
popd

# LLVM
#git clone https://github.com/sifive/riscv-llvm
git clone --recursive https://github.com/llvm/llvm-project.git riscv-llvm
pushd riscv-llvm
ln -s ../../clang llvm/tools || true
rm -rf build
mkdir build
cd build
enable_projects="clang;clang-tools-extra;lldb;lld;mlir"

cmake -G Ninja -DCMAKE_BUILD_TYPE="Release" \
  -DLLVM_ENABLE_PROJECTS=${enable_projects} \
  -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ -DLLVM_ENABLE_LLD=ON \
  -DBUILD_SHARED_LIBS=True -DLLVM_USE_SPLIT_DWARF=True \
  -DLLVM_DISABLE_ABI_BREAKING_CHECKS_ENFORCING=OFF \
  -DCMAKE_INSTALL_PREFIX="${RISCV}" \
  -DLLVM_OPTIMIZED_TABLEGEN=True -DLLVM_BUILD_TESTS=False \
  -DDEFAULT_SYSROOT="${RISCV}/riscv64-unknown-elf" \
  -DLLVM_DEFAULT_TARGET_TRIPLE="riscv64-unknown-elf" \
  -DLLVM_TARGETS_TO_BUILD="RISCV" \
  ../llvm
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
clang++ -O -c hello.cpp --target=riscv32 --sysroot=${RISCV}/riscv64-unknown-elf/ --gcc-toolchain=${RISCV}
riscv64-unknown-elf-g++ hello.o -o hello -march=rv32imac -mabi=ilp32
qemu-riscv32 hello

# 64 bit
clang++ -O -c hello.cpp --target=riscv64 --sysroot=${RISCV}/riscv64-unknown-elf/ --gcc-toolchain=${RISCV}
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

#32-bit
clang++ --target=riscv32 hello.cpp -c -emit-llvm -o hello.bc --sysroot=_install/riscv64-unknown-elf/ --gcc-toolchain=_install
llc -filetype=obj hello.bc -o hello.riscvrel
riscv64-unknown-elf-g++ hello.riscvrel -o hello -march=rv32imac -mabi=ilp32
qemu-riscv32 hello

#64-bit
${RISCV}/bin/clang++ --target=riscv64 hello.cpp -c -emit-llvm -o hello.bc --sysroot=${RISCV}/riscv64-unknown-elf/ --gcc-toolchain=${RISCV} -march=rv64gc -mabi=lp64d
${RISCV}/bin/llc -filetype=obj hello.bc -o hello.riscvrel
${RISCV}/bin/riscv64-unknown-elf-g++ hello.riscvrel -o hello.riscvexec
${RISCV}/bin/spike ${RISCV}/riscv64-unknown-elf/bin/pk hello.riscvexec
