#!/usr/bin/env bash

unset CDPATH

# target directory
PREFIX=${PREFIX-/usr/local/djgpp}

TARGET="i586-pc-msdosdjgpp"

# enabled languages
#ENABLE_LANGUAGES=${ENABLE_LANGUAGES-c,c++,f95,objc,obj-c++}
ENABLE_LANGUAGES=${ENABLE_LANGUAGES-c,c++}

# number of parallel build threads
MAKE_JOBS=${MAKE_JOBS-4}

#DJGPP_DOWNLOAD_BASE="ftp://ftp.delorie.com/pub"
export DJGPP_DOWNLOAD_BASE="http://www.delorie.com/pub"

BASE=`pwd`

if [ -z $1 ]; then
  echo "Usage: $0 [packages...]"
  echo "Supported packages:"
  ls djgpp/
  ls script/
  exit 1
fi

while [ ! -z $1 ]; do
  if [ ! -x djgpp/$1 ] && [ ! -x script/$1 ]; then
    echo "Unsupported package: $1"
    exit 1
  fi

  ([ -e djgpp/$1 ] && source djgpp/$1) || source script/$1
  shift
done

DEPS=""

[ ! -z ${GCC_VERSION} ] && DEPS+=" djgpp binutils"
[ ! -z ${BINUTILS_VERSION} ] && DEPS+=" "
[ ! -z ${GDB_VERSION} ] && DEPS+=" "
[ ! -z ${DJGPP_VERSION} ] && DEPS+=" "
[ ! -z ${BUILD_DXEGEN} ] && DEPS+=" djgpp binutils gcc"

for DEP in ${DEPS}; do
  case $DEP in
    djgpp)
      [ -z ${DJGPP_VERSION} ] \
        && source djgpp/djgpp
      ;;
    binutils)
      [ -z "`ls ${PREFIX}/${TARGET}/etc/binutils-*-installed 2> /dev/null`" ] \
        && [ -z ${BINUTILS_VERSION} ] \
        && source djgpp/binutils
      ;;
    gcc)
      [ -z "`ls ${PREFIX}/${TARGET}/etc/gcc-*-installed 2> /dev/null`" ] \
        && [ -z ${GCC_VERSION} ] \
        && source script/gcc
      ;;
    gdb)
      [ -z "`ls ${PREFIX}/${TARGET}/etc/gdb-*-installed 2> /dev/null`" ] \
        && [ -z ${GDB_VERSION} ] \
        && source script/gdb
      ;;
    dxegen)
      [ -z "`ls ${PREFIX}/${TARGET}/etc/dxegen-installed 2> /dev/null`" ] \
        && [ -z ${BUILD_DXEGEN} ] \
        && source script/dxegen
      ;;
  esac
done

source script/stage1.sh

source script/build-tools.sh

if [ ! -z ${BINUTILS_VERSION} ]; then
  echo "Building binutils"
  mkdir -p bnu${BINUTILS_VERSION}s
  cd bnu${BINUTILS_VERSION}s
  if [ ! -e binutils-unpacked ]; then
    unzip -o ../../download/bnu${BINUTILS_VERSION}s.zip || exit 1

    # patch for binutils 2.27
    [ ${BINUTILS_VERSION} == 227 ] && (patch gnu/binutils-*/bfd/init.c ${BASE}/patch/patch-bnu27-bfd-init.txt || exit 1 )

    touch binutils-unpacked
  fi
  cd gnu/binutils-* || exit 1

  # exec permission of some files are not set, fix it.
  for EXEC_FILE in install-sh missing; do
    echo "chmod a+x $EXEC_FILE"
    chmod a+x $EXEC_FILE || exit 1
  done

  source script/build-binutils.sh
fi

cd ${BASE}/build/

if [ ! -z ${DJGPP_VERSION} ] || [ ! -z ${BUILD_DXEGEN} ]; then
  echo "Prepare djgpp"
  rm -rf ${BASE}/build/djgpp-${DJGPP_VERSION}
  mkdir -p ${BASE}/build/djgpp-${DJGPP_VERSION}
  cd ${BASE}/build/djgpp-${DJGPP_VERSION} || exit 1
  unzip -o ../../download/djdev${DJGPP_VERSION}.zip || exit 1
  unzip -o ../../download/djlsr${DJGPP_VERSION}.zip || exit 1
  unzip -o ../../download/djcrx${DJGPP_VERSION}.zip || exit 1
  patch -p1 -u < ../../patch/patch-djlsr${DJGPP_VERSION}.txt || exit 1
  patch -p1 -u < ../../patch/patch-djcrx${DJGPP_VERSION}.txt || exit 1

  cd src/stub
  ${CC} -O2 ${CFLAGS} stubify.c -o ${TARGET}-stubify || exit 1
  ${CC} -O2 ${CFLAGS} stubedit.c -o ${TARGET}-stubedit || exit 1

  cd ../..

  mkdir -p $PREFIX/${TARGET}/sys-include || exit 1
  cp -rp include/* $PREFIX/${TARGET}/sys-include/ || exit 1
  cp -rp lib $PREFIX/${TARGET}/ || exit 1
  mkdir -p $PREFIX/bin || exit 1
  cp -p src/stub/${TARGET}-stubify $PREFIX/bin/ || exit 1
  cp -p src/stub/${TARGET}-stubedit $PREFIX/bin/ || exit 1

  rm ${PREFIX}/${TARGET}/etc/djgpp-*-installed
  touch ${PREFIX}/${TARGET}/etc/djgpp-${DJGPP_VERSION}-installed
fi

cd ${BASE}/build/

if [ ! -z ${GCC_VERSION} ]; then
  # build gcc
  untar djcross-gcc-${GCC_VERSION} || exit 1
  cd djcross-gcc-${GCC_VERSION}/

  BUILDDIR=`pwd`

  if [ ! -e ${BUILDDIR}/tmpinst/autoconf-${AUTOCONF_VERSION}-built ]; then
    echo "Building autoconf"
    cd $BUILDDIR
    untar autoconf-${AUTOCONF_VERSION} || exit 1
    cd autoconf-${AUTOCONF_VERSION}/
    PATH="${BUILDDIR}/tmpinst/bin:${BASE}/build/tmpinst/:$PATH" \
      ./configure --prefix=$BUILDDIR/tmpinst || exit 1
    PATH="${BUILDDIR}/tmpinst/bin:${BASE}/build/tmpinst/:$PATH" \
      ${MAKE} -j${MAKE_JOBS} all install || exit 1
    rm ${BUILDDIR}/tmpinst/autoconf-*-built
    touch ${BUILDDIR}/tmpinst/autoconf-${AUTOCONF_VERSION}-built
  else
    echo "autoconf already built, skipping."
  fi

  if [ ! -e ${BUILDDIR}/tmpinst/automake-${AUTOMAKE_VERSION}-built ]; then
    echo "Building automake"
    cd $BUILDDIR
    untar automake-${AUTOMAKE_VERSION} || exit 1
    cd automake-${AUTOMAKE_VERSION}/
    PATH="${BUILDDIR}/tmpinst/bin:${BASE}/build/tmpinst/:$PATH" \
      ./configure --prefix=$BUILDDIR/tmpinst || exit 1
    PATH="${BUILDDIR}/tmpinst/bin:${BASE}/build/tmpinst/:$PATH" \
      ${MAKE} all install || exit 1
    rm ${BUILDDIR}/tmpinst/automake-*-built
    touch ${BUILDDIR}/tmpinst/automake-${AUTOMAKE_VERSION}-built
  else
    echo "automake already built, skipping."
  fi

  cd $BUILDDIR

  if [ ! -e gcc-unpacked ]; then
    echo "Patch unpack-gcc.sh"

    if [ `uname` = "FreeBSD" ]; then
      # The --verbose option is not recognized by BSD patch
      $SED -i 's/patch --verbose/patch/' unpack-gcc.sh || exit 1
    fi

    echo "Running unpack-gcc.sh"
    PATH="${BUILDDIR}/tmpinst/bin:${BASE}/build/tmpinst/:$PATH" \
      sh unpack-gcc.sh --no-djgpp-source $(ls -t ${BASE}/download/gcc-${GCC_VERSION}.tar.* | head -n 1) || exit 1

    # patch gnu/gcc-X.XX/gcc/doc/gcc.texi
    echo "Patch gcc/doc/gcc.texi"
    cd gnu/gcc-*/gcc/doc || exit 1
    $SED -i "s/[^^]@\(\(tex\)\|\(end\)\)/\n@\1/g" gcc.texi || exit 1
    cd -

    # copy stubify programs
    cp -p $PREFIX/bin/${TARGET}-stubify $BUILDDIR/tmpinst/bin/stubify

    cd $BUILDDIR/

    # download mpc/gmp/mpfr/isl libraries
    echo "Downloading gcc dependencies"
    cd gnu/gcc-${GCC_VERSION_SHORT}
    PATH="${BUILDDIR}/tmpinst/bin:${BASE}/build/tmpinst/:$PATH" \
      ./contrib/download_prerequisites
    cd -

    touch gcc-unpacked
  else
    echo "gcc already unpacked, skipping."
  fi

  echo "Building gcc"

  mkdir -p djcross || exit 1
  cd djcross

  TEMP_CFLAGS="$CFLAGS"
  export CFLAGS="$CFLAGS $GCC_EXTRA_CFLAGS"

  if [ ! -e gcc-configure-prefix ] || [ ! `cat gcc-configure-prefix` = "${PREFIX}" ]; then
    rm gcc-configure-prefix
    ${MAKE} distclean
    PATH="${BUILDDIR}/tmpinst/bin:${BASE}/build/tmpinst/:$PATH" \
      ../gnu/gcc-${GCC_VERSION_SHORT}/configure \
                                     --target=${TARGET} \
                                     --program-prefix=${TARGET}- \
                                     --prefix=$PREFIX \
                                     --disable-nls \
                                     --enable-libquadmath-support \
                                     --enable-version-specific-runtime-libs \
                                     --enable-languages=${ENABLE_LANGUAGES} \
                                     --enable-fat \
                                     ${GCC_CONFIGURE_OPTIONS} || exit 1
    echo ${PREFIX} > gcc-configure-prefix
  else
    echo "Note: gcc already configured. To force a rebuild, use: rm -rf $(pwd)"
    sleep 5
  fi

  ${MAKE} -j${MAKE_JOBS} PATH="${BUILDDIR}/tmpinst/bin:${BASE}/build/tmpinst/:$PATH" || exit 1
  ${MAKE} -j${MAKE_JOBS} install-strip || exit 1

  rm ${PREFIX}/${TARGET}/etc/gcc-*-installed
  touch ${PREFIX}/${TARGET}/etc/gcc-${GCC_VERSION}-installed

  export CFLAGS="$TEMP_CFLAGS"
fi

# gcc done

if [ ! -z ${DJGPP_VERSION} ]; then
  # build djlsr (for dxegen / exe2coff)
  cd ${BASE}/build/djgpp-${DJGPP_VERSION}
  if [ "$CC" == "gcc" ] && [ ! -z ${BUILD_DXEGEN} ]; then
    echo "Building DXE tools."
    cd src
    PATH=$PREFIX/bin/:$PATH ${MAKE} || exit 1
    cd dxe
    cp -p dxegen  $PREFIX/bin/${TARGET}-dxegen || exit 1
    cp -p dxe3gen $PREFIX/bin/${TARGET}-dxe3gen || exit 1
    cp -p dxe3res $PREFIX/bin/${TARGET}-dxe3res || exit 1
    cd ../..
    touch ${PREFIX}/${TARGET}/etc/dxegen-installed
  else
    echo "Building DXE tools requires gcc, skip."
  fi
  cd src/stub
  ${CC} -O2 ${CFLAGS} -o exe2coff exe2coff.c || exit 1
  cp -p exe2coff $PREFIX/bin/${TARGET}-exe2coff || exit 1

  # djlsr done
fi

cd ${BASE}/build

source script/build-gdb.sh

echo "Copy long name executables to short name."
(
  cd $PREFIX || exit 1
  SHORT_NAME_LIST="gcc g++ c++ addr2line c++filt cpp size strings dxegen dxe3gen dxe3res exe2coff stubify stubedit gdb"
  for SHORT_NAME in $SHORT_NAME_LIST; do
    if [ -f bin/${TARGET}-$SHORT_NAME ]; then
      cp -p bin/${TARGET}-$SHORT_NAME ${TARGET}/bin/$SHORT_NAME
    fi
  done
)

# copy setenv script
(cd ${BASE}/setenv/ && ./copyfile.sh $PREFIX) || exit 1

echo "Testing DJGPP."
cd ${BASE}/build
echo "Use DJGPP to build a test C program."
$PREFIX/bin/${TARGET}-gcc ../hello.c -o hello || echo "FAILED: C"

for x in $(echo $ENABLE_LANGUAGES | tr "," " ")
do
  case $x in
    c++)
      echo "Use DJGPP to build a test C++ program."
      $PREFIX/bin/${TARGET}-c++ ../hello-cpp.cpp -o hello-cpp || echo "FAILED: C++"
      ;;
  esac
done

echo "build-djgpp.sh done."
echo "To remove temporary build files, use: rm -rf build/"
echo "To remove downloaded source packages, use: rm -rf download/"
