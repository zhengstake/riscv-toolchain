# build LLVM RISC-V Toolchain
LLVM RISC-V toolchain support needs to bootstrap GPU RISC-V toolchain. The project
demonstrates how both can be build and installed to a common installation directory.

```bash
mkdir -p riscv-toolchain
cd riscv-toolchain

mkdir -p  _install
export PATH=`pwd`/_install/bin:$PATH
hash -r
```

## Build and install riscv-gnu-toolchain
### gcc, binutils, newlib
```bash
git clone --recursive https://github.com/riscv/riscv-gnu-toolchain
pushd riscv-gnu-toolchain
./configure --prefix=`pwd`/../_install --enable-multilib
make -j`nproc`
```

### qemu
```bash
make -j`nproc` build-qemu
popd
```

### install qemu with apt-get as an alternative
```bash
sudo apt install qemu-user
```

## build LLVM with bootstrapped riscv-gnu-toolchain
```bash
git clone --recursive https://github.com/llvm/llvm-project.git riscv-llvm
pushd riscv-llvm
ln -s ../../clang llvm/tools || true
rm -rf _build
mkdir _build
cd _build
enable_projects="clang;clang-tools-extra;lldb;lld;mlir"

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
cmake --build . --target install
popd
```
## Compile Hello world sanity test your new RISC-V LLVM
### discover llvm targets
llvm-objdump --version | grep riscv
    riscv32    - 32-bit RISC-V
    riscv64    - 64-bit RISC-V

### generate source hello world
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

###  compile and execute RISCV elf via qemu
```bash
# 32 bit
clang -O -c hello.c --target=riscv32
riscv64-unknown-elf-gcc hello.o -o hello -march=rv32imac -mabi=ilp32
qemu-riscv32 hello

# 64 bit
clang -O -c hello.c --target=riscv64
riscv64-unknown-elf-gcc hello.o -o hello -march=rv64imac -mabi=lp64
qemu-riscv64 hello

# 32 bit
clang++ -O -c hello.cpp --target=riscv32 --sysroot=_install/riscv64-unknown-elf/ --gcc-toolchain=_install
riscv64-unknown-elf-g++ hello.o -o hello -march=rv32imac -mabi=ilp32
qemu-riscv32 hello

# 64 bit
clang++ -O -c hello.cpp --target=riscv64 --sysroot=_install/riscv64-unknown-elf/ --gcc-toolchain=_install
riscv64-unknown-elf-g++ hello.o -o hello -march=rv64imac -mabi=lp64
qemu-riscv64 hello
```

### Direct execution of RSIC-V binaray on Linux 
When running on Linux, the kernel supports a feature called binfmt_misc. This allows for an interpreter 
to be registered and invoked automatically for a specified binary type. When we installed QEMU, 
it went ahead and registered our user-mode emulators: 
ls /proc/sys/fs/binfmt_misc/


## Build and run C/C++ source through LLVM IR
_install/bin/clang++ --target=riscv32 prog.cpp -c -emit-llvm -o prog.bc

### LLVM IR to Relocatable RISC-V ELF binary
_install/bin/llc -filetype=obj prog.bc -o prog.riscvrel
file prog.riscvrel
prog.riscvrel: ELF 32-bit LSB relocatable, UCB RISC-V, version 1 (SYSV), not stripped

### Perform linking on relocatable RISC-V ELF binary
_install/bin/riscv32-unknown-elf-g++ prog.riscvrel -o prog.riscvexec
file prog.riscvexec
prog.riscvexec: ELF 32-bit LSB executable, UCB RISC-V, version 1 (SYSV), statically linked, not stripped

### running RSIC-V binaray on spike
../riscv-isa-sim/build/bin/spike ../riscv-pk/build/riscv32-unknown-elf/bin/pk prog.riscvexec

