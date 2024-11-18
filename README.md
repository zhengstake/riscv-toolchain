RISC-V Toolchain and ISS Simulator
============================

About
-------------
This project document the steps to build RISC-V LLVM toolchain and spike ISS simulator and examples to compile and 
simulate a C application.

RISC-V LLVM oolchain support needs to bootstrap RISC-V GNU toolchain. The project
demonstrates how both can be build and installed to a common installation directory.

Overall there are four main steps:
1. Build and install riscv-gnu-toolchain
2. Build LLVM with bootstrapped riscv-gnu-toolchain
3. Build and install RISC-V Proxy Kernel and Boot Loader
4. Build and install RISC-V spike ISS simulator

We will start with the root toolchain directory riscv-toolchain.

```bash
mkdir -p riscv-toolchain
cd riscv-toolchain

mkdir -p  release
export RISCV=`pwd`/release
export PATH=${RISCV}/bin:$PATH
hash -r
```

# Step 1: Build and install riscv-gnu-toolchain
## install standard packages
```bash
$ sudo apt-get install autoconf automake autotools-dev curl python3 python3-pip libmpc-dev libmpfr-dev libgmp-dev gawk build-essential bison flex texinfo gperf libtool patchutils bc zlib1g-dev libexpat-dev ninja-build git cmake libglib2.0-dev libslirp-dev
```

## gcc, binutils, newlib
```bash
git clone --recursive https://github.com/riscv/riscv-gnu-toolchain
pushd riscv-gnu-toolchain
./configure --prefix=${RISCV} --enable-multilib --with-sim=spike  --with-arch=rv64gc_zifencei 
make -j`nproc`
```

## qemu
```bash
make -j`nproc` build-qemu
popd
```

## spike
```bash
make -j`nproc` build-sim
```

### install qemu with apt-get as an alternative
```bash
sudo apt install qemu-user
```

# Step 2: Build LLVM with bootstrapped riscv-gnu-toolchain
```bash
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
```

# Step 3: Build and install RISC-V Proxy Kernel and Boot Loader
The RISC-V Proxy Kernel, `pk`, is a lightweight application execution
environment that can host statically-linked RISC-V ELF binaries.

```bash
git clone --recursive https://github.com/riscv/riscv-pk
pushd riscv-pk
rm -rf build
mkdir build
cd build
../configure --prefix=$RISCV --host=riscv64-unknown-elf
make
make install

```

# Step 4: Build and install RISC-V spike ISS simulator
This step can be skipped if you already configured '--with-sim=spike' and make 'build-im' target under riscv-gnu-toolchain.

```bash
git clone --recursive https://github.com/riscv/riscv-isa-sim
pushd riscv-isa-sim
sudo apt-get install device-tree-compiler libboost-regex-dev libboost-system-dev
rm -rf build
mkdir build
cd build
../configure --prefix=$RISCV
make
[sudo] make install

```

# Compile Hello world sanity test your new RISC-V LLVM
## generate source hello world
```bash
cat >hello.c <<END
#include <stdio.h>

int main(){
  printf("Hello RISCV!\n");
  return 0;
}
END

cat >hello.cpp <<END
#include <iostream>

int main()
{
  std::cout << "Hello RISCV c++!" << std::endl;
  return 0;
}
END
```

##  compile and execute RISCV elf via qemu
Make sure that all binaries refer to ${RISCV}/bin.

```bash
export PATH=${RISCV}/bin:$PATH

# 32 bit
clang -O -c hello.c --target=riscv32
riscv64-unknown-elf-gcc hello.o -o hello -march=rv32imac -mabi=ilp32
qemu-riscv32 hello

# 64 bit
clang -O -c hello.c --target=riscv64
riscv64-unknown-elf-gcc hello.o -o hello -march=rv64imac -mabi=lp64
qemu-riscv64 hello

# 32 bit
clang++ -O -c hello.cpp --target=riscv32 --sysroot=${RISCV}/riscv64-unknown-elf/ --gcc-toolchain=${RISCV}
riscv64-unknown-elf-g++ hello.o -o hello -march=rv32imac -mabi=ilp32
qemu-riscv32 hello

# 64 bit
clang++ -O -c hello.cpp --target=riscv64 --sysroot=${RISCV}/riscv64-unknown-elf/ --gcc-toolchain=${RISCV}
riscv64-unknown-elf-g++ hello.o -o hello -march=rv64imac -mabi=lp64
qemu-riscv64 hello
```

## Direct execution of RSIC-V binaray on X86 Ubuntu Linux 
When running on Linux, the kernel supports a feature called binfmt_misc. This allows for an interpreter 
to be registered and invoked automatically for a specified binary type. When we installed QEMU, 
it went ahead and registered our user-mode emulators: 
```bash
ls /proc/sys/fs/binfmt_misc/
```

## discover llvm targets
```bash
llvm-objdump --version | grep riscv
```
   * riscv32    - 32-bit RISC-V
   * riscv64    - 64-bit RISC-V

## Build and run C/C++ source through LLVM IR
```bash
${RISCV}/bin/clang++ --target=riscv64 hello.cpp -c -emit-llvm -o hello.bc --sysroot=${RISCV}/riscv64-unknown-elf/ --gcc-toolchain=${RISCV} -march=rv64gc -mabi=lp64d
```

### LLVM IR to Relocatable RISC-V ELF binary
```bash
${RISCV}/bin/llc -filetype=obj hello.bc -o hello.riscvrel
file hello.riscvrel
```

hello.riscvrel: ELF 64-bit LSB relocatable, UCB RISC-V, version 1 (SYSV), not stripped

### Perform linking on relocatable RISC-V ELF binary
```bash
${RISCV}/bin/riscv64-unknown-elf-g++ hello.riscvrel -o hello.riscvexec
file hello.riscvexec
```

hello.riscvexec: ELF 64-bit LSB executable, UCB RISC-V, version 1 (SYSV), statically linked, not stripped

### running RSIC-V binaray on spike
```bash
${RISCV}/bin/spike ${RISCV}/riscv64-unknown-elf/bin/pk hello.riscvexec
```
