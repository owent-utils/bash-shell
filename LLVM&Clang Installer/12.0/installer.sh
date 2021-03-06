#!/bin/bash

# Dependency: libedit-devel libxml2-devel ncurses-devel python-devel swig

# ======================================= 配置 =======================================
LLVM_VERSION=12.0.0
COMPOMENTS_LIBEDIT_VERSION=20210419-3.1
COMPOMENTS_PYTHON_VERSION=3.9.5;
COMPOMENTS_SWIG_VERSION=v4.0.2;
COMPOMENTS_ZLIB_VERSION=1.2.11;
COMPOMENTS_LIBFFI_VERSION=3.3;
PREFIX_DIR=/usr/local/llvm-$LLVM_VERSION;
#BUILD_TARGET_COMPOMENTS="clang;clang-tools-extra;compiler-rt;debuginfo-tests;libc;libclc;libcxx;libcxxabi;libunwind;lld;lldb;mlir;openmp;parallel-libs;polly;pstl";
# TODO 12.0.0版本编译polly失败。下个版本再开启试试
# BUILD_TARGET_COMPOMENTS="clang;clang-tools-extra;compiler-rt;libclc;libcxx;libcxxabi;libunwind;lld;lldb;openmp;parallel-libs;polly;pstl";
BUILD_TARGET_COMPOMENTS="clang;clang-tools-extra;compiler-rt;libclc;libcxx;libcxxabi;libunwind;lld;lldb;openmp;parallel-libs;pstl";
BUILD_TARGET_BAN_COMPOMENTS_STAGE_1="libclc;lldb"
# 这个版本的libc适配有点问题，这个版本增加了thread模块，对 ```stdatomic.h``` 的适配有问题，故而排除

# ======================= 非交叉编译 ======================= 
CHECK_TOTAL_MEMORY=$(cat /proc/meminfo | grep MemTotal | awk '{print $2}');
CHECK_AVAILABLE_MEMORY=$(cat /proc/meminfo | grep MemAvailable | awk '{print $2}');
BUILD_LLVM_LLVM_OPTION="-DLLVM_BUILD_EXAMPLES=OFF -DLLVM_BUILD_TESTS=OFF -DLLVM_TEMPORARILY_ALLOW_OLD_TOOLCHAIN=ON -DLLVM_ENABLE_EH=ON -DLLVM_ENABLE_RTTI=ON -DLLVM_ENABLE_PIC=ON -DLLVM_USE_INTEL_JITEVENTS=ON"; # -DLLVM_ENABLE_LTO=ON ,this may failed in llvm 3.9 
BUILD_OTHER_CONF_OPTION="";
BUILD_DOWNLOAD_ONLY=0;
BUILD_USE_SHM=0;
BUILD_USE_LD="";
BUILD_USE_GCC_TOOLCHAIN="";
BUILD_TYPE="Release";
BUILD_JOBS_OPTION="-j$(cat /proc/cpuinfo | grep processor | awk 'BEGIN{MAX_CORE_NUM=1}{if($3>MAX_CORE_NUM){MAX_CORE_NUM=$3;}}END{print MAX_CORE_NUM;}')";
LINK_JOBS_MAX_NUMBER=0;
if [[ "x$CHECK_AVAILABLE_MEMORY" != "x" ]]; then
    let LINK_JOBS_MAX_NUMBER=$CHECK_AVAILABLE_MEMORY/4194303 ; # 4GB for each linker
elif [[ "x$CHECK_TOTAL_MEMORY" != "x" ]]; then
    let LINK_JOBS_MAX_NUMBER=$CHECK_TOTAL_MEMORY/4194303 ; # 4GB for each linker
fi
if [[ $LINK_JOBS_MAX_NUMBER -gt 0 ]]; then
    BUILD_LLVM_LLVM_OPTION="$BUILD_LLVM_LLVM_OPTION -DLLVM_PARALLEL_LINK_JOBS=$LINK_JOBS_MAX_NUMBER" ;
fi

# ======================= 内存大于13GB，使用动态链接库（linking libLLVM-XXX.so的时候会消耗巨量内存） =======================
if [[ -z "$CHECK_AVAILABLE_MEMORY" ]]; then
    CHECK_AVAILABLE_MEMORY=0;
fi

if [[ -z "$CHECK_TOTAL_MEMORY" ]]; then
    CHECK_TOTAL_MEMORY=0;
fi

# if [ $CHECK_AVAILABLE_MEMORY -gt 13631488 ] || [ $CHECK_TOTAL_MEMORY -gt 13631488 ]; then
#     BUILD_LLVM_LLVM_OPTION="$BUILD_LLVM_LLVM_OPTION -DLLVM_BUILD_LLVM_DYLIB=ON -DLLVM_LINK_LLVM_DYLIB=ON";
#     for BUILD_TARGET in ${BUILD_TARGET_COMPOMENTS//;/ }; do
#         if [ "libc" == "$BUILD_TARGET" ]; then
#             BUILD_LLVM_LLVM_OPTION="$BUILD_LLVM_LLVM_OPTION -DLLVM_BUILD_LLVM_C_DYLIB=ON";
#             break;
#         fi
#     done
# fi
  
export BUILD_LLVM_PATCHED_OPTION="$BUILD_LLVM_LLVM_OPTION";

if [[ -z "$CC" ]]; then
    CC=$(which gcc);
    if [[ $? -eq 0 ]]; then
        CXX="$(dirname $CC)/g++";
    else
        CC=$(which clang);
        if [[ $? -eq 0 ]]; then
            CXX="$(dirname $CC)/clang++";
        else
            echo -e "\\033[32;1mCan not find gcc or clang.\\033[39;49;0m";
            exit 1;
        fi
    fi
fi
export CC="$CC";
export CXX="$CXX";

ORIGIN_COMPILER_CC="$(readlink -f "$CC")";
ORIGIN_COMPILER_CXX="$(readlink -f "$CXX")";

echo '
#include <stdio.h>
int main() {
    puts("test ld.gold");
    return 0;
}
' > contest.tmp.c;
$CC -o contest.tmp.exe -O2 -fuse-ld=gold contest.tmp.c;
if [[ $? -eq 0 ]]; then
    BUILD_USE_LD="gold";
fi
rm -f contest.tmp.exe contest.tmp.c;
 
# ======================= 检测完后等待时间 ======================= 
CHECK_INFO_SLEEP=3
 
# ======================= 安装目录初始化/工作目录清理 ======================= 
while getopts "b:cdg:hj:l:m:np:st:" OPTION; do
    case $OPTION in
        p)
            PREFIX_DIR="$OPTARG";
        ;;
        b)
            BUILD_TYPE="$OPTARG";
        ;;
        c)
            for CLEANUP_DIR in $(find . -maxdepth 1 -mindepth 1 -type d -name "*"); do
                if [[ -e "$CLEANUP_DIR/.git" ]]; then
                    cd "$CLEANUP_DIR";
                    git reset --hard;
                    git clean -dfx;
                    cd -;
                else
                    rm -rf "$CLEANUP_DIR";
                fi
            done
            echo -e "\\033[32;1mnotice: clear work dir(s) done.\\033[39;49;0m";
            exit 0;
        ;;
        d)
            BUILD_DOWNLOAD_ONLY=1;
            echo -e "\\033[32;1mDownload mode.\\033[39;49;0m";
        ;;
        h)
            echo "usage: $0 [options] -p=prefix_dir -c -h";
            echo "options:";
            echo "-b [build type]             Release (default), RelWithDebInfo, MinSizeRel, Debug";
            echo "-c                          clean build cache.";
            echo "-d                          download only.";
            echo "-h                          help message.";
            echo "-j [parallel jobs]          build in parallel using the given number of jobs.";
            echo "-l [llvm configure option]  add llvm build options.";
            echo "-m [llvm cmake option]      add llvm build options.";
            echo "-g [gcc toolchain]          set gcc toolchain.";
            echo "-n                          print toolchain version and exit.";
            echo "-p [prefix_dir]             set prefix directory.";
            echo "-s                          use shared memory to build targets when support.";
            echo "-t [build target]           set build target(all;clang;clang-tools-extra;compiler-rt;debuginfo-tests;libc;libclc;libcxx;libcxxabi;libunwind;lld;lldb;mlir;openmp;parallel-libs;polly;pstl).";
            exit 0;
        ;;
        t)
            if [ "x$BUILD_TARGET_COMPOMENTS" == "xall" ]; then
                BUILD_TARGET_COMPOMENTS="";
            fi
            if [ "+" == "${OPTARG:0:1}" ]; then
                BUILD_TARGET_COMPOMENTS="$BUILD_TARGET_COMPOMENTS ${OPTARG:1}";
            else
                BUILD_TARGET_COMPOMENTS="$OPTARG";
            fi
        ;;
        j)
            BUILD_JOBS_OPTION="-j$OPTARG";
        ;;
        l)
            BUILD_LLVM_CONF_OPTION="$BUILD_LLVM_CONF_OPTION $OPTARG";
        ;;
        m)
            BUILD_LLVM_CMAKE_OPTION="$BUILD_LLVM_CMAKE_OPTION $OPTARG";
        ;;
        n)
            echo $LLVM_VERSION;
            exit 0;
        ;;
        s)
            BUILD_USE_SHM=1;
        ;;
        g)
            BUILD_USE_GCC_TOOLCHAIN="$OPTARG";
        ;;
        ?)  #当有不认识的选项的时候arg为?
            echo "unkonw argument detected";
            exit 1;
        ;;
    esac
done

if [[ $BUILD_DOWNLOAD_ONLY -eq 0 ]]; then
    mkdir -p "$PREFIX_DIR"
    PREFIX_DIR="$( cd "$PREFIX_DIR" && pwd )";
fi

# ======================= 转到脚本目录 ======================= 
WORKING_DIR="$PWD";

# ======================= 统一的包检查和下载函数 =======================
function check_and_download(){
    PKG_NAME="$1";
    PKG_MATCH_EXPR="$2";
    PKG_URL="$3";
     
    PKG_VAR_VAL=($(find . -maxdepth 1 -name "$PKG_MATCH_EXPR"));
    if [[ ${#PKG_VAR_VAL} -gt 0 ]]; then
        echo "${PKG_VAR_VAL[0]}"
        return 0;
    fi
     
    if [[ -z "$PKG_URL" ]]; then
        echo -e "\\033[31;1m$PKG_NAME not found.\\033[39;49;0m" 
        return 1;
    fi
     
    if [[ -z "$4" ]]; then
        wget -c "$PKG_URL";
    else
        wget -c "$PKG_URL" -O "$4";
    fi
    
    PKG_VAR_VAL=($(find . -maxdepth 1 -name "$PKG_MATCH_EXPR"));
     
    if [[ ${#PKG_VAR_VAL} -eq 0 ]]; then
        echo -e "\\033[31;1m$PKG_NAME not found.\\033[39;49;0m" 
        return 1;
    fi
     
    echo "${PKG_VAR_VAL[0]}";
}

function is_in_list() {
    if [[ "x$BUILD_TARGET_COMPOMENTS" == "xall" ]]; then
        echo 0;
        exit 0;
    fi

    ele="$1";
    shift;

    for i in $(echo "$BUILD_TARGET_COMPOMENTS" | tr ';' ' '); do
        if [[ "$ele" == "$i" ]]; then
            echo 0;
            exit 0;
        fi
    done

    echo 1;
    exit 1;
}

function is_in_ban_list() {
    ele="$1";
    shift;

    for i in $(echo "$BUILD_TARGET_BAN_COMPOMENTS_STAGE_1" | tr ';' ' '); do
        if [[ "$ele" == "$i" ]]; then
            echo 0;
            exit 0;
        fi
    done

    echo 1;
    exit 1;
}

# ======================= 如果是64位系统且没安装32位的开发包，则编译要gcc加上 --disable-multilib 参数, 不生成32位库 ======================= 
SYS_LONG_BIT=$(getconf LONG_BIT);
 
# ======================================= 搞起 ======================================= 
echo -e "\\033[31;1mcheck complete.\\033[39;49;0m"
 
# ======================= 准备环境, 把库和二进制目录导入，否则编译会找不到库或文件 ======================= 
echo "WORKING_DIR               = $WORKING_DIR";
echo "PREFIX_DIR                = $PREFIX_DIR";
echo "BUILD_TARGET_COMPOMENTS   = $BUILD_TARGET_COMPOMENTS";
echo "BUILD_LLVM_CONF_OPTION    = $BUILD_LLVM_CONF_OPTION";
echo "BUILD_LLVM_CMAKE_OPTION   = $BUILD_LLVM_CMAKE_OPTION";
echo "BUILD_OTHER_CONF_OPTION   = $BUILD_OTHER_CONF_OPTION";
echo "CHECK_INFO_SLEEP          = $CHECK_INFO_SLEEP";
echo "SYS_LONG_BIT              = $SYS_LONG_BIT";
echo "CC                        = $CC";
echo "CXX                       = $CXX";
echo "BUILD_USE_LD              = $BUILD_USE_LD";

 
echo -e "\\033[32;1mnotice: now, sleep for $CHECK_INFO_SLEEP seconds.\\033[39;49;0m"; 
sleep $CHECK_INFO_SLEEP
  
# ======================= 关闭交换分区，否则就爽死了 ======================= 
if [[ $BUILD_DOWNLOAD_ONLY -eq 0 ]]; then
    swapoff -a ;
fi

# ======================= 统一的包检查和下载函数 =======================
if [[ ! -e "llvm-project-$LLVM_VERSION" ]]; then
    git clone -b "llvmorg-$LLVM_VERSION" --depth 1 "https://github.com/llvm/llvm-project.git" "llvm-project-$LLVM_VERSION";
fi

if [[ ! -e "llvm-project-$LLVM_VERSION/.git" ]]; then
    echo -e "\\033[31;1mgit clone https://github.com/llvm/llvm-project.git failed.\\033[39;49;0m";
    exit 1;
fi

if [[ ! -e "libedit-$COMPOMENTS_LIBEDIT_VERSION.tar.gz" ]]; then
    wget "http://thrysoee.dk/editline/libedit-$COMPOMENTS_LIBEDIT_VERSION.tar.gz";
    if [[ $? -ne 0 ]]; then
        rm -f "libedit-$COMPOMENTS_LIBEDIT_VERSION.tar.gz";
        echo -e "\\033[31;1mDownload from http://thrysoee.dk/editline/libedit-$COMPOMENTS_LIBEDIT_VERSION.tar.gz failed.\\033[39;49;0m";
        exit 1;
    fi
fi

if [[ ! -e "libffi-$COMPOMENTS_LIBFFI_VERSION.tar.gz" ]]; then
    wget "https://github.com/libffi/libffi/releases/download/v$COMPOMENTS_LIBFFI_VERSION/libffi-$COMPOMENTS_LIBFFI_VERSION.tar.gz";
    if [[ $? -ne 0 ]]; then
        rm -f "libffi-$COMPOMENTS_LIBFFI_VERSION.tar.gz";
        echo -e "\\033[31;1mDownload from https://github.com/libffi/libffi/releases/download/v$COMPOMENTS_LIBFFI_VERSION/libffi-$COMPOMENTS_LIBFFI_VERSION.tar.gz failed.\\033[39;49;0m";
        exit 1;
    fi
fi

if [[ ! -e "zlib-$COMPOMENTS_ZLIB_VERSION" ]]; then
    git clone -b "v$COMPOMENTS_ZLIB_VERSION" --depth 1 "https://github.com/madler/zlib.git" "zlib-$COMPOMENTS_ZLIB_VERSION";
fi

if [[ -z "$BUILD_TARGET_COMPOMENTS" ]] || [[ "xall" == "x$BUILD_TARGET_COMPOMENTS" ]] || [[ "0" == $(is_in_list lldb) ]]; then
    PYTHON_PKG=$(check_and_download "python" "Python-*.tar.xz" "https://www.python.org/ftp/python/$COMPOMENTS_PYTHON_VERSION/Python-$COMPOMENTS_PYTHON_VERSION.tar.xz" );
    if [[ $? -ne 0 ]]; then
        return;
    fi

    if [[ ! -e "swig-$COMPOMENTS_SWIG_VERSION" ]]; then
        git clone -b "$COMPOMENTS_SWIG_VERSION" --depth 1 "https://github.com/swig/swig.git" "swig-$COMPOMENTS_SWIG_VERSION";
        if [[ $? -ne 0 ]]; then
            return;
        fi
    fi
fi

if [[ $BUILD_DOWNLOAD_ONLY -ne 0 ]]; then
    exit 0;
fi

export LLVM_DIR="$PWD/llvm-project-$LLVM_VERSION";

export STAGE_BUILD_CMAKE_OPTION="";

function build_llvm_toolchain() {
    STAGE_BUILD_EXT_CMAKE_OPTION="";
    STAGE_BUILD_EXT_COMPILER_FLAGS="-DCMAKE_INSTALL_RPATH_USE_LINK_PATH=YES";
    if [[ ! -z "$CC" ]]; then
        STAGE_BUILD_EXT_CMAKE_OPTION="$STAGE_BUILD_EXT_CMAKE_OPTION -DCMAKE_C_COMPILER=$CC";
    fi
    if [[ ! -z "$CXX" ]]; then
        STAGE_BUILD_EXT_CMAKE_OPTION="$STAGE_BUILD_EXT_CMAKE_OPTION -DCMAKE_CXX_COMPILER=$CXX";
    fi
    if [[ ! -z "$BUILD_USE_LD" ]]; then
        CMAKE_RUNTIME_LINKER_FLAGS="$CMAKE_RUNTIME_LINKER_FLAGS -DLLVM_USE_LINKER=$BUILD_USE_LD";
    fi

    if [[ $STAGE_BUILD_STEP -eq 2 ]] && [[ ! -z "$BUILD_USE_GCC_TOOLCHAIN" ]]; then
        if [[ -z "CFLAGS" ]]; then
            export CFLAGS="--gcc-toolchain=$BUILD_USE_GCC_TOOLCHAIN"
        else
            export CFLAGS="$CFLAGS --gcc-toolchain=$BUILD_USE_GCC_TOOLCHAIN"
        fi

        if [[ -z "CXXFLAGS" ]]; then
            export CXXFLAGS="--gcc-toolchain=$BUILD_USE_GCC_TOOLCHAIN"
        else
            export CXXFLAGS="$CXXFLAGS --gcc-toolchain=$BUILD_USE_GCC_TOOLCHAIN"
        fi
    fi

    if [[ ! -z "$CMAKE_CXX_FLAGS" ]]; then
        if [[ "${CMAKE_CXX_FLAGS:0:1}" == " " ]]; then
            CMAKE_CXX_FLAGS="${CMAKE_CXX_FLAGS:1}";
        fi
        if [[ $STAGE_BUILD_STEP -eq 2 ]] && [[ ! -z "$BUILD_USE_GCC_TOOLCHAIN" ]]; then
            CMAKE_CXX_FLAGS="$CMAKE_CXX_FLAGS --gcc-toolchain=$BUILD_USE_GCC_TOOLCHAIN"
        fi
        STAGE_BUILD_EXT_COMPILER_FLAGS="$STAGE_BUILD_EXT_COMPILER_FLAGS -DCMAKE_CXX_FLAGS='$CMAKE_CXX_FLAGS'";
    fi
    if [[ ! -z "$CMAKE_C_FLAGS" ]]; then
        if [[ "${CMAKE_C_FLAGS:0:1}" == " " ]]; then
            CMAKE_C_FLAGS="${CMAKE_C_FLAGS:1}";
        fi
        if [[ $STAGE_BUILD_STEP -eq 2 ]] && [[ ! -z "$BUILD_USE_GCC_TOOLCHAIN" ]]; then
            CMAKE_C_FLAGS="$CMAKE_C_FLAGS --gcc-toolchain=$BUILD_USE_GCC_TOOLCHAIN"
        fi
        STAGE_BUILD_EXT_COMPILER_FLAGS="$STAGE_BUILD_EXT_COMPILER_FLAGS -DCMAKE_C_FLAGS='$CMAKE_C_FLAGS'";
    fi
    if [[ ! -z "$CMAKE_RUNTIME_LINKER_FLAGS" ]]; then
        if [[ "${CMAKE_RUNTIME_LINKER_FLAGS:0:1}" == " " ]]; then
            CMAKE_RUNTIME_LINKER_FLAGS="${CMAKE_RUNTIME_LINKER_FLAGS:1}";
        fi
        STAGE_BUILD_EXT_COMPILER_FLAGS="$STAGE_BUILD_EXT_COMPILER_FLAGS -DCMAKE_EXE_LINKER_FLAGS='$CMAKE_RUNTIME_LINKER_FLAGS' -DCMAKE_MODULE_LINKER_FLAGS='$CMAKE_RUNTIME_LINKER_FLAGS' -DCMAKE_SHARED_LINKER_FLAGS='$CMAKE_RUNTIME_LINKER_FLAGS'";
    fi

    which ninja > /dev/null 2>&1;
    if [[ $? -eq 0 ]]; then
        BUILD_WITH_NINJA="-G Ninja";
    else
        which ninja-build > /dev/null 2>&1;
        if [ $? -eq 0 ]; then
            BUILD_WITH_NINJA="-G Ninja";
        else
            BUILD_WITH_NINJA="";
        fi
    fi

    # ready to build 
    # if [ ! -e "$STAGE_BUILD_PREFIX_DIR/bin/llvm-config" ]; then
    cd "$LLVM_DIR";
    # clean build cache
    if [[ -e "/dev/shm/build-install-llvm/build_stage_$STAGE_BUILD_STEP" ]]; then
        rm -rf "/dev/shm/build-install-llvm/build_stage_$STAGE_BUILD_STEP";
    fi
    if [[ -e "$LLVM_DIR/build_stage_$STAGE_BUILD_STEP" ]]; then
        rm -rf "$LLVM_DIR/build_stage_$STAGE_BUILD_STEP";
    fi
    CHECK_AVAILABLE_MEMORY=$(cat /proc/meminfo | grep MemAvailable | awk '{print $2}');
    # Use memory disk to build if we have enough memory(16GB)
    if [[ $BUILD_USE_SHM -ne 0 ]] && [[ ! -z "$CHECK_AVAILABLE_MEMORY" ]]; then
        if [[ $CHECK_AVAILABLE_MEMORY -gt 16777216 ]]; then
            mkdir -p "/dev/shm/build-install-llvm/build_stage_$STAGE_BUILD_STEP";
            ln -s "/dev/shm/build-install-llvm/build_stage_$STAGE_BUILD_STEP" "$LLVM_DIR/build_stage_$STAGE_BUILD_STEP";
        fi
    fi
    if [[ ! -e "$LLVM_DIR/build_stage_$STAGE_BUILD_STEP" ]]; then
        mkdir -p "$LLVM_DIR/build_stage_$STAGE_BUILD_STEP" ;
    fi
    cd "$LLVM_DIR/build_stage_$STAGE_BUILD_STEP" ;
    BUILD_TARGET_COMPOMENTS_CURRENT_STAGE="";
    if [[ "x$BUILD_TARGET_BAN_COMPOMENTS_STAGE_1" != "x" ]]; then
        for CHECK_COMPONENT in $(echo "$BUILD_TARGET_COMPOMENTS" | tr ';' ' '); do
            if [[ "0" != "$(is_in_ban_list $CHECK_COMPONENT)" ]]; then
                if [[ "x$BUILD_TARGET_COMPOMENTS_CURRENT_STAGE" == "x" ]]; then
                    BUILD_TARGET_COMPOMENTS_CURRENT_STAGE="$CHECK_COMPONENT";
                else
                    BUILD_TARGET_COMPOMENTS_CURRENT_STAGE="$BUILD_TARGET_COMPOMENTS_CURRENT_STAGE;$CHECK_COMPONENT";
                fi
            fi
        done
    else
        BUILD_TARGET_COMPOMENTS_CURRENT_STAGE="$BUILD_TARGET_COMPOMENTS";
    fi

    if [[ $STAGE_BUILD_STEP -eq 2 ]]; then
        STAGE_BUILD_EXT_COMPILER_FLAGS="$STAGE_BUILD_EXT_COMPILER_FLAGS -DCLANG_ENABLE_BOOTSTRAP=ON" ;
    fi

    echo "cmake $LLVM_DIR/llvm $BUILD_WITH_NINJA -DCMAKE_INSTALL_PREFIX=$STAGE_BUILD_PREFIX_DIR -DCMAKE_BUILD_TYPE=$BUILD_TYPE -DCMAKE_FIND_ROOT_PATH=$PREFIX_DIR $BUILD_LLVM_PATCHED_OPTION $STAGE_BUILD_CMAKE_OPTION $STAGE_BUILD_EXT_CMAKE_OPTION $STAGE_BUILD_EXT_COMPILER_FLAGS -DLLVM_ENABLE_PROJECTS=$BUILD_TARGET_COMPOMENTS_CURRENT_STAGE";
    cmake "$LLVM_DIR/llvm" $BUILD_WITH_NINJA -DCMAKE_INSTALL_PREFIX=$STAGE_BUILD_PREFIX_DIR -DCMAKE_BUILD_TYPE=$BUILD_TYPE -DCMAKE_FIND_ROOT_PATH=$PREFIX_DIR $BUILD_LLVM_PATCHED_OPTION $STAGE_BUILD_CMAKE_OPTION $STAGE_BUILD_EXT_CMAKE_OPTION $STAGE_BUILD_EXT_COMPILER_FLAGS "-DLLVM_ENABLE_PROJECTS=$BUILD_TARGET_COMPOMENTS_CURRENT_STAGE";
    if [[ 0 -ne $? ]]; then
        echo -e "\\033[31;1mError: build llvm $STAGE_BUILD_PREFIX_DIR failed when run cmake.\\033[39;49;0m";
        return 1;
    fi

    # 这里会消耗茫茫多内存，所以尝试先开启多进程编译，失败之后降级到单进程
    if [[ $STAGE_BUILD_STEP -eq 2 ]]; then
        cmake --build . $BUILD_JOBS_OPTION --config $BUILD_TYPE -- stage2 || cmake --build . -j2 --config $BUILD_TYPE -- stage2 || cmake --build . --config $BUILD_TYPE -- stage2 ;
    else
        cmake --build . $BUILD_JOBS_OPTION --config $BUILD_TYPE || cmake --build . -j2 --config $BUILD_TYPE || cmake --build . --config $BUILD_TYPE ;
    fi
    if [[ 0 -ne $? ]]; then
        echo -e "\\033[31;1mError: build llvm $STAGE_BUILD_PREFIX_DIR failed when run cmake --build ..\\033[39;49;0m";
        return 1;
    fi

    cmake --build . --target install;
    if [[ 0 -ne $? ]]; then
        echo -e "\\033[31;1mError: build llvm $STAGE_BUILD_PREFIX_DIR failed when install.\\033[39;49;0m";
        return 1;
    fi

    if [[ -e "/dev/shm/build-install-llvm/build_stage_$STAGE_BUILD_STEP" ]]; then
        cd ..;
        rm -rf "/dev/shm/build-install-llvm/build_stage_$STAGE_BUILD_STEP";
        rm -rf "$LLVM_DIR/build_stage_$STAGE_BUILD_STEP";
    fi
    return 0 ;
}

export STAGE_BUILD_STEP=1;
STAGE_BUILD_PREFIX_DIR_1="$PREFIX_DIR-stage-1";
export STAGE_BUILD_PREFIX_DIR="$STAGE_BUILD_PREFIX_DIR_1";

# Build libedit
if [[ -e "libedit-$COMPOMENTS_LIBEDIT_VERSION.tar.gz" ]]; then
    if [[ ! -e "libedit-$COMPOMENTS_LIBEDIT_VERSION-stage-1" ]]; then
        tar -axvf "libedit-$COMPOMENTS_LIBEDIT_VERSION.tar.gz";
        mv -f "libedit-$COMPOMENTS_LIBEDIT_VERSION" "libedit-$COMPOMENTS_LIBEDIT_VERSION-stage-1";
    fi
    tar -axvf "libedit-$COMPOMENTS_LIBEDIT_VERSION.tar.gz";
    cd "libedit-$COMPOMENTS_LIBEDIT_VERSION-stage-1";
    ./configure --prefix=$STAGE_BUILD_PREFIX_DIR --with-pic=yes;
    make $BUILD_JOBS_OPTION || make;
    if [[ $? -ne 0 ]]; then
        echo -e "\\033[31;1mBuild libedit failed.\\033[39;49;0m";
        exit 1;
    fi
    make install;
    cd "$WORKING_DIR";
fi

build_llvm_toolchain ;

if [[ 0 -ne $? ]] ; then
    if [ $BUILD_DOWNLOAD_ONLY -eq 0 ]; then
        echo -e "\\033[31;1mError: build llvm $STAGE_BUILD_PREFIX_DIR failed on stage 1.\\033[39;49;0m";
        exit 1;
    fi
fi
BUILD_TARGET_BAN_COMPOMENTS_STAGE_1="";

echo -e "\\033[32;1mbuild llvm $STAGE_BUILD_PREFIX_DIR success on stage 1.\\033[39;49;0m";

cd "$WORKING_DIR";

CXX_ABI_PATH=$(find "$STAGE_BUILD_PREFIX_DIR/include" -name "cxxabi.h");
if [[ ! -z "$CXX_ABI_PATH" ]]; then
    # CXX_ABI_DIR=${CXX_ABI_PATH%%/cxxabi.h};
    # export LDFLAGS="$LDFLAGS -lc++ -lc++abi";
    # export STAGE_BUILD_CMAKE_OPTION="$STAGE_BUILD_CMAKE_OPTION -DLIBCXX_CXX_ABI=libcxxabi -DLIBCXX_CXX_ABI_INCLUDE_PATHS=$CXX_ABI_DIR";
    # CMAKE_CXX_FLAGS="$CMAKE_CXX_FLAGS -stdlib=libc++";
    export STAGE_BUILD_CMAKE_OPTION="$STAGE_BUILD_CMAKE_OPTION -DLLVM_ENABLE_LIBCXX=ON" ;
fi
# export STAGE_BUILD_CMAKE_OPTION="$STAGE_BUILD_CMAKE_OPTION -DLLVM_TOOLS_BINARY_DIR=$STAGE_BUILD_PREFIX_DIR/bin";
export STAGE_BUILD_CMAKE_OPTION="$STAGE_BUILD_CMAKE_OPTION -DLLVM_ENABLE_MODULES=ON -DLLVM_ENABLE_LTO=ON";


if [[ "x$BUILD_TARGET_COMPOMENTS" == "xall" ]]; then
    export STAGE_BUILD_CMAKE_OPTION="$STAGE_BUILD_CMAKE_OPTION -DCOMPILER_RT_USE_BUILTINS_LIBRARY=ON -DLIBUNWIND_USE_COMPILER_RT=ON -DLIBCXX_USE_COMPILER_RT=ON -DLIBCXXABI_USE_COMPILER_RT=ON -DLIBCXXABI_USE_LLVM_UNWINDER=ON";
    BUILD_TARGET_HAS_COMPILER_RT=1;
    BUILD_TARGET_HAS_LIBCXX=1;
    BUILD_TARGET_HAS_LIBCXX_ABI=1;
    BUILD_TARGET_HAS_LIBUNWIND=1;
    BUILD_TARGET_HAS_LLD=1;
else
    BUILD_TARGET_HAS_COMPILER_RT=0;
    BUILD_TARGET_HAS_LIBCXX=0;
    BUILD_TARGET_HAS_LIBCXX_ABI=0;
    BUILD_TARGET_HAS_LIBUNWIND=0;
    BUILD_TARGET_HAS_LLD=0;
    for BUILD_TARGET in ${BUILD_TARGET_COMPOMENTS//;/ }; do
        if [[ "compiler-rt" == "$BUILD_TARGET" ]]; then
            BUILD_TARGET_HAS_COMPILER_RT=1;
        elif [[ "libcxx" == "$BUILD_TARGET" ]]; then
            BUILD_TARGET_HAS_LIBCXX=1;
        elif [[ "libcxxabi" == "$BUILD_TARGET" ]]; then
            BUILD_TARGET_HAS_LIBCXX_ABI=1;
        elif [[ "libunwind" == "$BUILD_TARGET" ]]; then
            BUILD_TARGET_HAS_LIBUNWIND=1;
        elif [[ "lld" == "$BUILD_TARGET" ]]; then
            BUILD_TARGET_HAS_LLD=1;
        fi
    done

    if [[ $BUILD_TARGET_HAS_COMPILER_RT -ne 0 ]] && [[ $BUILD_TARGET_HAS_LIBCXX -ne 0 ]] && [[ $BUILD_TARGET_HAS_LIBCXX_ABI -ne 0 ]] && [[ $BUILD_TARGET_HAS_LIBUNWIND -ne 0 ]] && [[ $BUILD_TARGET_HAS_LLD -ne 0 ]]; then
        export STAGE_BUILD_CMAKE_OPTION="$STAGE_BUILD_CMAKE_OPTION -DCOMPILER_RT_USE_BUILTINS_LIBRARY=ON";
    fi

    if [[ $BUILD_TARGET_HAS_COMPILER_RT -ne 0 ]] && [[ $BUILD_TARGET_HAS_LIBUNWIND -ne 0 ]]; then
        export STAGE_BUILD_CMAKE_OPTION="$STAGE_BUILD_CMAKE_OPTION -DLIBUNWIND_USE_COMPILER_RT=ON";
    fi

    if [[ $BUILD_TARGET_HAS_COMPILER_RT -ne 0 ]] && [[ $BUILD_TARGET_HAS_LIBCXX -ne 0 ]]; then
        export STAGE_BUILD_CMAKE_OPTION="$STAGE_BUILD_CMAKE_OPTION -DLIBCXX_USE_COMPILER_RT=ON";
    fi

    if [[ $BUILD_TARGET_HAS_COMPILER_RT -ne 0 ]] && [[ $BUILD_TARGET_HAS_LIBCXX_ABI -ne 0 ]]; then
        export STAGE_BUILD_CMAKE_OPTION="$STAGE_BUILD_CMAKE_OPTION -DLIBCXXABI_USE_COMPILER_RT=ON";
    fi

    if [[ $BUILD_TARGET_HAS_LIBUNWIND -ne 0 ]] && [[ $BUILD_TARGET_HAS_LIBCXX_ABI -ne 0 ]]; then
        export STAGE_BUILD_CMAKE_OPTION="$STAGE_BUILD_CMAKE_OPTION -DLIBCXXABI_USE_LLVM_UNWINDER=ON";
    fi
fi

# ================================== 自举编译 ==================================

# ================================== 环境覆盖 ==================================
if [[ "x$LD_LIBRARY_PATH" == "x" ]]; then
    export LD_LIBRARY_PATH="$STAGE_BUILD_PREFIX_DIR/lib"
else
    export LD_LIBRARY_PATH="$STAGE_BUILD_PREFIX_DIR/lib:$LD_LIBRARY_PATH"
fi
export PATH=$STAGE_BUILD_PREFIX_DIR/bin:$PATH

echo "add $STAGE_BUILD_PREFIX_DIR/bin to PTAH";
echo "add $STAGE_BUILD_PREFIX_DIR/lib to LD_LIBRARY_PATH";

export CC=$STAGE_BUILD_PREFIX_DIR/bin/clang ;
export CXX=$STAGE_BUILD_PREFIX_DIR/bin/clang++ ;
export AR="$STAGE_BUILD_PREFIX_DIR/bin/llvm-ar" ;
export AS="$STAGE_BUILD_PREFIX_DIR/bin/llvm-as" ;
export NM="$STAGE_BUILD_PREFIX_DIR/bin/llvm-nm" ;
export RANLIB="$STAGE_BUILD_PREFIX_DIR/bin/llvm-ranlib" ;
export OBJCOPY="$STAGE_BUILD_PREFIX_DIR/bin/llvm-objcopy" ;
export OBJDUMP="$STAGE_BUILD_PREFIX_DIR/bin/llvm-objdump" ;
export STRIP="$STAGE_BUILD_PREFIX_DIR/bin/llvm-strip" ;
export STAGE_BUILD_CMAKE_OPTION="$STAGE_BUILD_CMAKE_OPTION -DCMAKE_AR=$AR -DCMAKE_RANLIB=$RANLIB -DCMAKE_NM=$NM -DCMAKE_OBJCOPY=$OBJCOPY -DCMAKE_OBJDUMP=$OBJDUMP -DCMAKE_STRIP=$STRIP";

for ADDITIONAL_PKGCONFIG_PATH in $(find $PREFIX_DIR -name pkgconfig); do
    if [[ "x$PKG_CONFIG_PATH" == "x" ]]; then
        export PKG_CONFIG_PATH="$ADDITIONAL_PKGCONFIG_PATH"
    else
        export PKG_CONFIG_PATH="$ADDITIONAL_PKGCONFIG_PATH:$PKG_CONFIG_PATH"
    fi
done

CHECK_IS_WINDOWS=0;
CHECK_IS_MACOS=0;
CHECK_IS_UNIX=0;
"$CC" -dM -E - < /dev/null | grep -i _win32 ;
if [[ $? -eq 0 ]]; then
    CHECK_IS_WINDOWS=1;
fi
"$CC" -dM -E - < /dev/null | grep -i _win64 ;
if [[ $? -eq 0 ]]; then
    CHECK_IS_WINDOWS=1;
fi
"$CC" -dM -E - < /dev/null | grep -i __linux ;
if [[ $? -eq 0 ]]; then
    CHECK_IS_UNIX=1;
fi
"$CC" -dM -E - < /dev/null | grep -i __unix ;
if [[ $? -eq 0 ]]; then
    CHECK_IS_UNIX=1;
fi
"$CC" -dM -E - < /dev/null | grep -i __apple ;
if [[ $? -eq 0 ]]; then
    CHECK_IS_MACOS=1;
fi


if [[ $CHECK_IS_UNIX -ne 0 ]] && [[ -e "$STAGE_BUILD_PREFIX_DIR/bin/ld.lld" ]]; then
    export LD="$STAGE_BUILD_PREFIX_DIR/bin/ld.lld" ;
    export STAGE_BUILD_CMAKE_OPTION="$STAGE_BUILD_CMAKE_OPTION -DLLVM_ENABLE_LLD=YES -DCMAKE_LINKER=$LD" ;
    LD_LOADER_SCRIPT="export LD=\"$LD\"";
elif [[ $CHECK_IS_MACOS -ne 0 ]] && [[ -e "$STAGE_BUILD_PREFIX_DIR/bin/ld64.lld" ]]; then
    export LD="$STAGE_BUILD_PREFIX_DIR/bin/ld64.lld" ;
    export STAGE_BUILD_CMAKE_OPTION="$STAGE_BUILD_CMAKE_OPTION -DLLVM_ENABLE_LLD=YES -DCMAKE_LINKER=$LD" ;
    LD_LOADER_SCRIPT="export LD=\"$LD\"";
elif [[ $CHECK_IS_WINDOWS -ne 0 ]] && [[ -e "$STAGE_BUILD_PREFIX_DIR/bin/lld-link" ]]; then
    export LD="$STAGE_BUILD_PREFIX_DIR/bin/lld-link" ;
    export STAGE_BUILD_CMAKE_OPTION="$STAGE_BUILD_CMAKE_OPTION -DLLVM_ENABLE_LLD=YES -DCMAKE_LINKER=$LD" ;
    LD_LOADER_SCRIPT="export LD=\"$LD\"";
elif [[ -e "$STAGE_BUILD_PREFIX_DIR/bin/lld" ]]; then
    export LD="$STAGE_BUILD_PREFIX_DIR/bin/lld" ;
    export STAGE_BUILD_CMAKE_OPTION="$STAGE_BUILD_CMAKE_OPTION -DLLVM_ENABLE_LLD=YES -DCMAKE_LINKER=$LD" ;
    LD_LOADER_SCRIPT="export LD=\"$LD\"";
fi
BUILD_USE_LD="";

# 先尝试查找和编译基础依赖(python开发包等)
BACKUP_PATH="$PATH";
BACKUP_LD_LIBRARY_PATH="$LD_LIBRARY_PATH";
BACKUP_CFLAGS="$CFLAGS";
BACKUP_CPPFLAGS="$CPPFLAGS";
BACKUP_CXXFLAGS="$CXXFLAGS";
BACKUP_LDFLAGS="$LDFLAGS";
export PATH="$STAGE_BUILD_PREFIX_DIR/bin:$PREFIX_DIR/bin:$PATH" ;
export LD_LIBRARY_PATH="$STAGE_BUILD_PREFIX_DIR/lib:$PREFIX_DIR/lib:$LD_LIBRARY_PATH" ;
if [[ -z "$CFLAGS" ]]; then
    export CFLAGS="-I$PREFIX_DIR/include -fPIC";
else
    export CFLAGS="$CFLAGS -I$PREFIX_DIR/include -fPIC";
fi
if [[ -z "$CPPFLAGS" ]]; then
    export CPPFLAGS="-I$PREFIX_DIR/include -fPIC";
else
    export CPPFLAGS="$CPPFLAGS -I$PREFIX_DIR/include -fPIC";
fi
if [[ -z "$CXXFLAGS" ]]; then
    export CXXFLAGS="-I$PREFIX_DIR/include -fPIC";
else
    export CXXFLAGS="$CXXFLAGS -I$PREFIX_DIR/include -fPIC";
fi
if [[ -z "$LDFLAGS" ]]; then
    export LDFLAGS="-L$PREFIX_DIR/lib64 -L$PREFIX_DIR/lib";
else
    export LDFLAGS="$LDFLAGS -L$PREFIX_DIR/lib64 -L$PREFIX_DIR/lib";
fi

# Build libedit again
if [[ -e "libedit-$COMPOMENTS_LIBEDIT_VERSION.tar.gz" ]]; then
    if [[ ! -e "libedit-$COMPOMENTS_LIBEDIT_VERSION-stage-2" ]]; then
        tar -axvf "libedit-$COMPOMENTS_LIBEDIT_VERSION.tar.gz";
        mv -f "libedit-$COMPOMENTS_LIBEDIT_VERSION" "libedit-$COMPOMENTS_LIBEDIT_VERSION-stage-2";
    fi
    tar -axvf "libedit-$COMPOMENTS_LIBEDIT_VERSION.tar.gz";
    cd "libedit-$COMPOMENTS_LIBEDIT_VERSION-stage-2";
    make clean || true;
    ./configure --prefix=$PREFIX_DIR --with-pic=yes;
    make $BUILD_JOBS_OPTION || make;
    if [[ $? -ne 0 ]]; then
        echo -e "\\033[31;1mBuild libedit failed.\\033[39;49;0m";
        exit 1;
    fi
    make install;
    cd "$WORKING_DIR";
fi

if [[ -e "zlib-$COMPOMENTS_ZLIB_VERSION" ]]; then
    mkdir -p "zlib-$COMPOMENTS_ZLIB_VERSION/build_jobs_dir";
    cd "zlib-$COMPOMENTS_ZLIB_VERSION/build_jobs_dir";
    cmake --build . -- clean || true;
    cmake .. -DCMAKE_POSITION_INDEPENDENT_CODE=YES -DBUILD_SHARED_LIBS=OFF "-DCMAKE_INSTALL_PREFIX=$PREFIX_DIR" ;
    cmake --build . -j $BUILD_JOBS_OPTION || cmake --build . ;
    if [[ $? -ne 0 ]]; then
        echo -e "\\033[31;1mBuild zlib failed.\\033[39;49;0m";
        exit 1;
    fi
    cmake --build . -- install ;
    cd "$WORKING_DIR";
fi

if [[ -e "libffi-$COMPOMENTS_LIBFFI_VERSION.tar.gz" ]]; then
    if [[ ! -e "libffi-$COMPOMENTS_LIBFFI_VERSION" ]]; then
        tar -axvf "libffi-$COMPOMENTS_LIBFFI_VERSION.tar.gz";
    fi
    cd "libffi-$COMPOMENTS_LIBFFI_VERSION";
    make clean || true;
    ./configure --prefix=$PREFIX_DIR --with-pic=yes ;
    make $BUILD_JOBS_OPTION || make;
    if [[ $? -ne 0 ]]; then
        echo -e "\\033[31;1mBuild libffi failed.\\033[39;49;0m";
        exit 1;
    fi
    make install;
    cd "$WORKING_DIR";
fi

if [[ -z "$BUILD_TARGET_COMPOMENTS" ]] || [[ "all" == "$BUILD_TARGET_COMPOMENTS" ]] || [[ "0" == $(is_in_list lldb) ]]; then
    if [[ -z "$(find $PREFIX_DIR -name swig)" ]]; then
        cd "swig-$COMPOMENTS_SWIG_VERSION";
        ./autogen.sh ;
        make clean || true;
        ./configure --prefix=$PREFIX_DIR ;
        make $BUILD_JOBS_OPTION || make;
        if [[ $? -ne 0 ]]; then
            echo -e "\\033[31;1mBuild swig failed.\\033[39;49;0m";
            exit 1;
        fi
        make install;
        cd "$WORKING_DIR";
    fi

    if [[ -z "$(find $PREFIX_DIR -name Python.h)" ]]; then
        # =======================  尝试编译安装python  =======================
        tar -Jxvf $PYTHON_PKG;
        PYTHON_DIR=$(ls -d Python-* | grep -v \.tar.xz);
        cd $PYTHON_DIR;
        # --enable-shared 会导致llvm的Find脚本找不到
        # 尝试使用gcc构建脚本中构建的openssl
        OPENSSL_INSTALL_DIR="";
        if [[ -e "$(dirname "$ORIGIN_COMPILER_CC")/../internal-packages/lib/libssl.a" ]]; then
            OPENSSL_INSTALL_DIR="$(readlink -f "$(dirname "$ORIGIN_COMPILER_CC")"/../internal-packages)";
        fi
        # --enable-optimizations require gcc 8.1.0 or later
        PYTHON_CONFIGURE_OPTIONS=("--prefix=$PREFIX_DIR" "--enable-optimizations" "--with-ensurepip=install" "--enable-shared");
        if [[ ! -z "$OPENSSL_INSTALL_DIR" ]]; then
            PYTHON_CONFIGURE_OPTIONS=(${PYTHON_CONFIGURE_OPTIONS[@]} "--with-openssl=$OPENSSL_INSTALL_DIR");
        fi
        make clean || true;
        ./configure ${PYTHON_CONFIGURE_OPTIONS[@]}  ;
        make $BUILD_JOBS_OPTION || make;
        if [[ $? -ne 0 ]]; then
            echo -e "\\033[31;1mBuild python failed.\\033[39;49;0m";
            exit 1;
        fi
        make install;

        cd "$WORKING_DIR";
    fi
    if [[ ! -z "$(find $PREFIX_DIR -name Python.h)" ]]; then
        export BUILD_LLVM_PATCHED_OPTION="$BUILD_LLVM_LLVM_OPTION -DPYTHON_HOME=$PREFIX_DIR -DLLDB_PYTHON_VERSION=3 -DLLDB_ENABLE_PYTHON=ON -DLLDB_RELOCATABLE_PYTHON=1";
    fi
fi

export PATH="$BACKUP_PATH";
# export LD_LIBRARY_PATH="$BACKUP_LD_LIBRARY_PATH"; # Build lldb require load libraries from $PREFIX_DIR
export CFLAGS="$BACKUP_CFLAGS";
export CPPFLAGS="$BACKUP_CPPFLAGS";
export CXXFLAGS="$BACKUP_CXXFLAGS";
export LDFLAGS="$BACKUP_LDFLAGS";


# 自举编译， 脱离对gcc的依赖
export STAGE_BUILD_STEP=2;
export STAGE_BUILD_PREFIX_DIR="$PREFIX_DIR";
build_llvm_toolchain ;

if [[ ! -e "$PREFIX_DIR/bin/clang" ]] ; then
    if [ $BUILD_DOWNLOAD_ONLY -eq 0 ]; then
        echo -e "\\033[31;1mError: build llvm $STAGE_BUILD_PREFIX_DIR failed on stage 2.\\033[39;49;0m";
        exit 1;
    fi
fi

rm -rf "$STAGE_BUILD_PREFIX_DIR_1";

# Patch python3-config to change compiler directory from $PREFIX_DIR-stage-1 to $PREFIX_DIR
PYTHON3_CONFIG_MAKEFILE="$(python3-config --configdir)/Makefile"
PYTHON3_CONFIG_SYSCONFIGDATA="$(find $(dirname $(python3-config --configdir)) -name "_sysconfigdata_*.py")";
if [[ -e "$PYTHON3_CONFIG_MAKEFILE" ]]; then
    sed -i.bak "s;$PREFIX_DIR-stage-1;$PREFIX_DIR;g" $PYTHON3_CONFIG_MAKEFILE ;
fi
if [[ -e "$PYTHON3_CONFIG_SYSCONFIGDATA" ]]; then
    sed -i.bak "s;$PREFIX_DIR-stage-1;$PREFIX_DIR;g" $PYTHON3_CONFIG_SYSCONFIGDATA ;
fi

if [[ $BUILD_DOWNLOAD_ONLY -eq 0 ]]; then

    DEP_COMPILER_HOME="$(dirname "$(dirname "$ORIGIN_COMPILER_CXX")")";
    echo "#!/bin/bash

if [[ \"x\$GCC_HOME_DIR\" == \"x\" ]]; then
    GCC_HOME_DIR=\"$DEP_COMPILER_HOME\";
fi" > "$PREFIX_DIR/load-llvm-envs.sh" ;

    echo '
LLVM_HOME_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )";

if [[ "x/" == "x$GCC_HOME_DIR" ]] || [[ "x/usr" == "x$GCC_HOME_DIR" ]] || [[ "x/usr/local" == "x$GCC_HOME_DIR" ]] || [[ "x$LLVM_HOME_DIR" == "x$GCC_HOME_DIR" ]]; then
    if [[ "x$LD_LIBRARY_PATH" == "x" ]]; then
        export LD_LIBRARY_PATH="$LLVM_HOME_DIR/lib" ;
    else
        export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:$LLVM_HOME_DIR/lib" ;
    fi
    
    export PATH="$LLVM_HOME_DIR/bin:$LLVM_HOME_DIR/libexec:$PATH" ;
else
    if [[ "x$LD_LIBRARY_PATH" == "x" ]]; then
        export LD_LIBRARY_PATH="$LLVM_HOME_DIR/lib:$GCC_HOME_DIR/lib64:$GCC_HOME_DIR/lib" ;
    else
        export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:$LLVM_HOME_DIR/lib:$GCC_HOME_DIR/lib64:$GCC_HOME_DIR/lib" ;
    fi
    
    export PATH="$LLVM_HOME_DIR/bin:$LLVM_HOME_DIR/libexec:$GCC_HOME_DIR/bin:$PATH" ;
fi

function build_with_llvm_clang() {
  export CC="$LLVM_HOME_DIR/bin/clang" ;
  export CXX="$LLVM_HOME_DIR/bin/clang++" ;
  export AR="$LLVM_HOME_DIR/bin/llvm-ar" ;
  export AS="$LLVM_HOME_DIR/bin/llvm-as" ;
' >> "$PREFIX_DIR/load-llvm-envs.sh" ;
echo "  $LD_LOADER_SCRIPT" >> "$PREFIX_DIR/load-llvm-envs.sh" ;
echo '  export RANLIB="$LLVM_HOME_DIR/bin/llvm-ranlib" ;
  export NM="$LLVM_HOME_DIR/bin/llvm-nm" ;
  export STRIP="$LLVM_HOME_DIR/bin/llvm-strip" ;
  export OBJCOPY="$LLVM_HOME_DIR/bin/llvm-objcopy" ;
  export OBJDUMP="$LLVM_HOME_DIR/bin/llvm-objdump" ;
  export READELF="$LLVM_HOME_DIR/bin/llvm-readelf" ;

  # Maybe need add --gcc-toolchain=$GCC_HOME_DIR to compile options
  "$@"
}
if [[ $# -gt 0 ]]; then
  build_with_llvm_clang "$@"
fi
' >> "$PREFIX_DIR/load-llvm-envs.sh" ;
    chmod +x "$PREFIX_DIR/load-llvm-envs.sh";

    LLVM_CONFIG_PATH="$PREFIX_DIR/bin/llvm-config";
    echo -e "\\033[33;1mAddition, run the cmds below to add environment var(s).\\033[39;49;0m";
    echo -e "\\033[31;1mexport PATH=$($LLVM_CONFIG_PATH --bindir):$PATH\\033[39;49;0m";
    echo -e "\\033[33;1mBuild LLVM done.\\033[39;49;0m";
    echo "";
    echo -e "\\033[32;1mSample flags to build exectable file:.\\033[39;49;0m";
    echo -e "\\033[35;1m\tCC=$STAGE_BUILD_PREFIX_DIR/bin/clang\\033[39;49;0m";
    echo -e "\\033[35;1m\tCXX=$STAGE_BUILD_PREFIX_DIR/bin/clang++\\033[39;49;0m";
    echo -e "\\033[35;1m\tCFLAGS=$($LLVM_CONFIG_PATH --cflags) -std=libc++\\033[39;49;0m";
    if [ ! -z "$(find $($LLVM_CONFIG_PATH --libdir) -name libc++abi.so)" ]; then
        echo -e "\\033[35;1m\tCXXFLAGS=$($LLVM_CONFIG_PATH --cxxflags) -std=libc++\\033[39;49;0m";
        echo -e "\\033[35;1m\tLDFLAGS=$($LLVM_CONFIG_PATH --ldflags) -lc++ -lc++abi\\033[39;49;0m";
    else
        echo -e "\\033[35;1m\tCXXFLAGS=$($LLVM_CONFIG_PATH --cxxflags)\\033[39;49;0m";
        echo -e "\\033[35;1m\tLDFLAGS=$($LLVM_CONFIG_PATH --ldflags)\\033[39;49;0m";
    fi
    echo -e "\\033[35;1m\tMaybe need add --gcc-toolchain=$GCC_HOME_DIR to compile options\\033[39;49;0m";
else
    echo -e "\\033[35;1mDownloaded: $BUILD_TARGET_COMPOMENTS.\\033[39;49;0m";
fi

PAKCAGE_NAME="$(dirname "$PREFIX_DIR")";
PAKCAGE_NAME="${PAKCAGE_NAME//\//-}-llvm-clang-libc++";
if [[ "x${PAKCAGE_NAME:0:1}" == "x-" ]]; then
    PAKCAGE_NAME="${PAKCAGE_NAME:1}";
fi
mkdir -p "$PREFIX_DIR/SPECS";
echo "Name:           $PAKCAGE_NAME
Version:        $LLVM_VERSION
Release:        1%{?dist}
Summary:        llvm-clang-libc++ $LLVM_VERSION
Group:          Development Tools
License:        BSD
URL:            https://github.com/owent-utils/bash-shell/tree/master/LLVM%26Clang%20Installer
BuildRoot:      %_topdir/BUILDROOT
Prefix:         $PREFIX_DIR
# Source0:
# BuildRequires:
Requires:       gcc,make
%description
llvm-clang-libc++ $LLVM_VERSION
%install
  mkdir -p %{buildroot}$(dirname "$PREFIX_DIR")
  ln -s $PREFIX_DIR %{buildroot}$PREFIX_DIR
  exit 0
%files
%defattr  (-,root,root,0755)
$PREFIX_DIR/*
%exclude $PREFIX_DIR

%global __requires_exclude_from ^$PREFIX_DIR/.*

%global __provides_exclude_from ^$PREFIX_DIR/.*

" > "$PREFIX_DIR/SPECS/rpm.spec";

echo "Using:"
echo "    mkdir -pv \$HOME/rpmbuild/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}"
echo "    cd $PREFIX_DIR && rpmbuild -bb --target=x86_64 SPECS/rpm.spec"
echo "to build rpm package."
