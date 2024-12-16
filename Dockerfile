FROM ubuntu:22.04 as base
WORKDIR /workdir
ENV HOME=/workdir

# 1) Install packages.
RUN apt-get update
RUN apt-get -y install autoconf automake autotools-dev curl python3 python3-pip \
    libmpc-dev libmpfr-dev libgmp-dev gawk build-essential bison flex texinfo gperf \
    libtool patchutils bc zlib1g-dev libexpat-dev ninja-build git cmake libglib2.0-dev \
    libslirp-dev qemu-user
RUN python3 -m pip install tomli

# 2) create release directory
RUN mkdir -p /opt/riscv 
ENV RISCV=/opt/riscv
ENV PATH=${RISCV}/bin:$PATH

# 3) build RISCV GNU toolchain
WORKDIR /workdir/riscv-toolchain
RUN git clone --recursive https://github.com/riscv/riscv-gnu-toolchain
WORKDIR /workdir/riscv-toolchain/riscv-gnu-toolchain
RUN ./configure --prefix=${RISCV} --enable-multilib --with-sim=spike  --with-arch=rv64gc_zifencei
RUN make -j`nproc`
RUN make -j`nproc` build-qemu
RUN ./configure --prefix=${RISCV} 
RUN make -j`nproc` build-sim

# 4) Build and install RISC-V Proxy Kernel and Boot Loader
WORKDIR /workdir/riscv-toolchain
RUN git clone --recursive https://github.com/riscv/riscv-pk
RUN mkdir -p /workdir/riscv-toolchain/riscv-pk/build
WORKDIR /workdir/riscv-toolchain/riscv-pk/build
RUN ../configure --prefix=$RISCV --host=riscv64-unknown-elf
RUN make; make install

# 5) Build and install RISC-V spike ISS simulator
WORKDIR /workdir/riscv-toolchain
RUN apt-get install -y device-tree-compiler libboost-regex-dev libboost-system-dev
RUN git clone --recursive https://github.com/riscv/riscv-isa-sim
RUN mkdir -p /workdir/riscv-toolchain/riscv-isa-sim/build
WORKDIR /workdir/riscv-toolchain/riscv-isa-sim/build
RUN ../configure --prefix=$RISCV
RUN make; make install

# 6) Build LLVM with bootstrapped riscv-gnu-toolchain
WORKDIR /workdir/riscv-toolchain
RUN git clone --recursive https://github.com/llvm/llvm-project.git riscv-llvm
WORKDIR /workdir/riscv-toolchain/riscv-llvm
RUN ln -s ../../clang llvm/tools || true
RUN mkdir build
WORKDIR /workdir/riscv-toolchain/riscv-llvm/build
ARG enable_projects="clang;clang-tools-extra;lldb;lld;mlir"
RUN apt-get install -y clang clang-tools lld

RUN cmake -G Ninja -DCMAKE_BUILD_TYPE="Release" \
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
RUN cmake --build . --target install

# 7) test installed toolchain
WORKDIR /workdir/riscv-toolchain
COPY hello.c /workdir/riscv-toolchain
COPY hello.cpp /workdir/riscv-toolchain

# 32 bit
RUN clang -O -c hello.c --target=riscv32
RUN riscv64-unknown-elf-gcc hello.o -o hello -march=rv32imac -mabi=ilp32
RUN qemu-riscv32 hello

# 64 bit
RUN clang -O -c hello.c --target=riscv64
RUN riscv64-unknown-elf-gcc hello.o -o hello -march=rv64imac -mabi=lp64
RUN qemu-riscv64 hello

# 32 bit
RUN clang++ -O -c hello.cpp --target=riscv32 --sysroot=${RISCV}/riscv64-unknown-elf/ --gcc-toolchain=${RISCV}
RUN riscv64-unknown-elf-g++ hello.o -o hello -march=rv32imac -mabi=ilp32
RUN qemu-riscv32 hello

# 64 bit
RUN clang++ -O -c hello.cpp --target=riscv64 --sysroot=${RISCV}/riscv64-unknown-elf/ --gcc-toolchain=${RISCV}
RUN riscv64-unknown-elf-g++ hello.o -o hello -march=rv64imac -mabi=lp64
RUN qemu-riscv64 hello

