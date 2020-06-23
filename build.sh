#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Copyright (C) 2018 Yaroslav Furman (YaroST12)
# Copyright (C) 2019 Adam W. Willis (0ctobot)

# Setup build directories
kernel_dir="${PWD}"
builddir="${kernel_dir}/build"

# Neutrino Toolchains
GCC="/home/alexia/toolchains/proton-clang/bin/aarch64-linux-gnu-"
GCC_32="/home/alexia/toolchains/proton-clang/bin/arm-linux-gnueabi-"
CLANG="/home/alexia/toolchains/proton-clang/"
CLANG_BIN="${CLANG}/bin"
CLANG_CC="${CLANG_BIN}/clang"
TC="neutrino"

# Export build variables
export KBUILD_BUILD_USER="linuxandria"
export ARCH="arm64"
export CLANG_TRIPLE="aarch64-linux-gnu-"
export LD_LIBRARY_PATH=${CLANG}/lib:$LD_LIBRARY_PATH

# AOSP Toolchains
# GCC="/home/return_of_octobot/Android/Toolchains/prebuilts/gcc/aosp/aarch64-linux-android-4.9/bin/aarch64-linux-android-"
# GCC_32="/home/return_of_octobot/Android/Toolchains/prebuilts/gcc/aosp/arm-linux-androideabi-4.9/bin/arm-linux-androideabi-"
# CLANG="/home/return_of_octobot/Android/Toolchains/prebuilts/clang/aosp/clang-r353983d"
# CLANG_BIN="${CLANG}/bin"
# CLANG_CC="${CLANG_BIN}/clang"
# LD_LIBRARY_PATH=${CLANG}/lib64:$LD_LIBRARY_PATH
# TC="Android"

# DragonTC
# CLANG=/home/return_of_octobot/Android/Toolchains/prebuilts/dtc/9.0
# CLANG_BIN=${CLANG}/bin
# CLANG_CC=${CLANG_BIN}/clang
# LD_LIBRARY_PATH=${CLANG}/lib64:$LD_LIBRARY_PATH
# TC="DragonTC clang version 9.0.0"

# Snapdragon LLVM
# CLANG="/home/return_of_octobot/Android/Toolchains/prebuilts/clang/sdclang/proprietary_vendor_qcom_sdclang-8.0_linux-x86"
# CLANG_BIN="${CLANG}/bin"
# CLANG_CC="${CLANG_BIN}/clang"
# LD_LIBRARY_PATH=${CLANG}/lib:$LD_LIBRARY_PATH

# Colors
NC='\033[0m'
RED='\033[0;31m'
LRD='\033[1;31m'
LGR='\033[1;32m'
YEL='\033[1;33m'

# CPUs
cpus=$(nproc --all)

# Separator
SEP="######################################"

function die() {
	echo -e ${RED} ${SEP}
	echo -e ${RED} "${1}"
	echo -e ${RED} ${SEP}
	exit
}

function parse_parameters() {
	PARAMS="${*}"
	# Default params
	BUILD_GCC=false
	BUILD_CLEAN=false
	CONFIG_FILE="vendor/neutrino_defconfig"
	DEVICE="hotdogb"
	objdir="${kernel_dir}/out"

	while [[ ${#} -ge 1 ]]; do
		case ${1} in
			"-r"|"--release")
				CONFIG_FILE="neutrino_hotdogb_defconfig" ;;

			"-g"|"--gcc")
				objdir="${kernel_dir}/out_gcc"
				BUILD_GCC=true ;;

			"-c"|"--clean")
				BUILD_CLEAN=true ;;
            *) die "Invalid parameter specified!" ;;
		esac

		shift
	done
	echo -e ${LGR} ${SEP}
	echo -e ${LGR} "Compilation started for ${DEVICE} ${NC}"
}

# Formats the time for the end
function format_time() {
	MINS=$(((${2} - ${1}) / 60))
	SECS=$(((${2} - ${1}) % 60))

	TIME_STRING+="${MINS}:${SECS}"

	echo "${TIME_STRING}"
}

function make_image()
{
	# After we run savedefconfig in sources folder
	if [[ -f ${kernel_dir}/.config ]]; then
		make -s mrproper
	fi
	# Needed to make sure we get dtb built and added to kernel image properly
	# Cleanup existing build files
	if [ ${BUILD_CLEAN} == true ]; then
		echo -e ${LGR} "Cleaning up mess... ${NC}"
	    rm -rf ${objdir}
		make -s mrproper
	else
	    rm -rf ${objdir}/arch/arm64/boot/
	fi
	START=$(date +%s)
	echo -e ${LGR} "Generating Defconfig ${NC}"
	make -s ARCH=${ARCH} O=${objdir} ${CONFIG_FILE}

	if [ ! $? -eq 0 ]; then
		die "Defconfig generation failed"
	fi

	echo -e ${LGR} "Building image ${NC}"
	if [ ${BUILD_GCC} == true ]; then
		cd ${kernel_dir}
		make -s -j${cpus} CROSS_COMPILE=${GCC} CROSS_COMPILE_ARM32=${GCC_32} \
		O=${objdir} Image.gz-dtb
	else

		POLLY="-mllvm -polly \
			-mllvm -polly-run-dce \
			-mllvm -polly-run-inliner \
			-mllvm -polly-opt-fusion=max \
			-mllvm -polly-ast-use-context \
			-mllvm -polly-detect-keep-going \
			-mllvm -polly-vectorizer=stripmine \
			-mllvm -polly-invariant-load-hoisting"

		# major version, usually 3 numbers (8.0.5 or 6.0.1)
		# VERSION=$($CLANG_CC --version | grep -wo "[0-9][0-9].[0-9].[0-9]")
		# revision (?), usually 6 numbers with 'r' before them
		# REVISION=$($CLANG_CC --version | grep -wo "r[0-9]*")
		# if [[ -z ${REVISION} ]]; then
		#	COMPILER_NAME="${TC} clang ${VERSION}"
		# else
		# 	COMPILER_NAME="${TC} clang ${VERSION}-${REVISION}"
		# fi

		COMPILER_NAME="neutrino clang 11.0.0"

		echo -e ${LGR} "${COMPILER_NAME} ${NC}"

		cd ${kernel_dir}
		PATH=${CLANG_BIN}:${PATH} make -j${cpus} -s CC="clang ${POLLY}" \
		AR="llvm-ar" \
		NM="llvm-nm" \
		OBJCOPY="llvm-objcopy" \
		OBJDUMP="llvm-objdump" \
		STRIP="llvm-strip" \
		CROSS_COMPILE=${GCC} \
		CROSS_COMPILE_ARM32=${GCC_32} \
		KBUILD_COMPILER_STRING="${COMPILER_NAME}" O=${objdir} Image.gz-dtb
	fi
	END=$(date +%s)
}
function completion()
{
	cd ${objdir}
	COMPILED_IMAGE=arch/arm64/boot/Image.gz-dtb
	if [[ -f ${COMPILED_IMAGE} ]]; then
		echo -e ${LGR} "Build for $DEVICE competed in" \
			"$(format_time "${START}" "${END}")!"
		echo -e ${LGR} ${SEP}
	fi
}
parse_parameters "${@}"
make_image
completion
cd ${kernel_dir}
