{
  lib,
  stdenv,
  fetchFromGitHub,
  fetchpatch,
  cmake,
  ninja,
  bzip2,
  lz4,
  snappy,
  zlib,
  zstd,
  windows,
  # only enable jemalloc for non-windows platforms
  # see: https://github.com/NixOS/nixpkgs/issues/216479
  enableJemalloc ? !stdenv.hostPlatform.isWindows && !stdenv.hostPlatform.isStatic,
  jemalloc,
  enableShared ? !stdenv.hostPlatform.isStatic,
  sse42Support ? stdenv.hostPlatform.sse4_2Support,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "rocksdb";
  version = "9.11.2";

  src = fetchFromGitHub {
    owner = "facebook";
    repo = finalAttrs.pname;
    rev = "v${finalAttrs.version}";
    hash = "sha256-D/FZJw1zwDXvCRHxCxyNxarHlDi5xtt8MddUOr4Pv2c=";
  };

  nativeBuildInputs = [
    cmake
    ninja
  ];

  propagatedBuildInputs = [
    bzip2
    lz4
    snappy
    zlib
    zstd
  ];

  buildInputs =
    lib.optional enableJemalloc jemalloc
    ++ lib.optional stdenv.hostPlatform.isMinGW windows.mingw_w64_pthreads;

  outputs = [
    "out"
    "tools"
  ];

  env.NIX_CFLAGS_COMPILE = toString (lib.optionals stdenv.cc.isClang [ "-faligned-allocation" ]);

  cmakeFlags = [
    "-DPORTABLE=1"
    "-DWITH_JEMALLOC=${if enableJemalloc then "1" else "0"}"
    "-DWITH_JNI=0"
    "-DWITH_BENCHMARK_TOOLS=0"
    "-DWITH_TESTS=1"
    "-DWITH_TOOLS=0"
    "-DWITH_CORE_TOOLS=1"
    "-DWITH_BZ2=1"
    "-DWITH_LZ4=1"
    "-DWITH_SNAPPY=1"
    "-DWITH_ZLIB=1"
    "-DWITH_ZSTD=1"
    "-DWITH_GFLAGS=0"
    "-DUSE_RTTI=1"
    "-DROCKSDB_INSTALL_ON_WINDOWS=YES" # harmless elsewhere
    (lib.optional sse42Support "-DFORCE_SSE42=1")
    "-DFAIL_ON_WARNINGS=NO"
  ] ++ lib.optional (!enableShared) "-DROCKSDB_BUILD_SHARED=0";

  # otherwise "cc1: error: -Wformat-security ignored without -Wformat [-Werror=format-security]"
  hardeningDisable = lib.optional stdenv.hostPlatform.isWindows "format";

  postPatch =
    lib.optionalString (lib.versionOlder finalAttrs.version "9") ''
      # Fix gcc-13 build failures due to missing <cstdint> and
      # <system_error> includes, fixed upstream since 9.x
      sed -e '1i #include <cstdint>' -i options/offpeak_time_info.h
    ''
    + lib.optionalString (lib.versionOlder finalAttrs.version "8") ''
      # Fix gcc-13 build failures due to missing <cstdint> and
      # <system_error> includes, fixed upstream since 8.x
      sed -e '1i #include <cstdint>' -i db/compaction/compaction_iteration_stats.h
      sed -e '1i #include <cstdint>' -i table/block_based/data_block_hash_index.h
      sed -e '1i #include <cstdint>' -i util/string_util.h
      sed -e '1i #include <cstdint>' -i include/rocksdb/utilities/checkpoint.h
    ''
    + lib.optionalString (lib.versionOlder finalAttrs.version "7") ''
      # Fix gcc-13 build failures due to missing <cstdint> and
      # <system_error> includes, fixed upstream since 7.x
      sed -e '1i #include <system_error>' -i third-party/folly/folly/synchronization/detail/ProxyLockable-inl.h
    ''
    + ''
      # fixed in https://github.com/facebook/rocksdb/pull/12309
      sed -e 's/ZSTD_INCLUDE_DIRS/zstd_INCLUDE_DIRS/' -i cmake/modules/Findzstd.cmake
      sed -e 's/ZSTD_INCLUDE_DIRS/zstd_INCLUDE_DIRS/' -i CMakeLists.txt
    '';

  preInstall =
    ''
      mkdir -p $tools/bin
      cp tools/{ldb,sst_dump}${stdenv.hostPlatform.extensions.executable} $tools/bin/
    ''
    + lib.optionalString stdenv.isDarwin ''
      ls -1 $tools/bin/* | xargs -I{} ${stdenv.cc.bintools.targetPrefix}install_name_tool -change "@rpath/librocksdb.${lib.versions.major finalAttrs.version}.dylib" $out/lib/librocksdb.dylib {}
    ''
    + lib.optionalString (stdenv.isLinux && enableShared) ''
      ls -1 $tools/bin/* | xargs -I{} patchelf --set-rpath $out/lib:${stdenv.cc.cc.lib}/lib {}
    '';

  # Old version doesn't ship the .pc file, new version puts wrong paths in there.
  postFixup =
    ''
      if [ -f "$out"/lib/pkgconfig/rocksdb.pc ]; then
        substituteInPlace "$out"/lib/pkgconfig/rocksdb.pc \
          --replace '="''${prefix}//' '="/'
      fi
    ''
    + lib.optionalString stdenv.isDarwin ''
      ${stdenv.cc.targetPrefix}install_name_tool -change "@rpath/libsnappy.1.dylib" "${snappy}/lib/libsnappy.1.dylib" $out/lib/librocksdb.dylib
      ${stdenv.cc.targetPrefix}install_name_tool -change "@rpath/librocksdb.${lib.versions.major finalAttrs.version}.dylib" "$out/lib/librocksdb.${lib.versions.major finalAttrs.version}.dylib" $out/lib/librocksdb.dylib
    '';

  meta = with lib; {
    homepage = "https://rocksdb.org";
    description = "A library that provides an embeddable, persistent key-value store for fast storage";
    changelog = "https://github.com/facebook/rocksdb/raw/v${finalAttrs.version}/HISTORY.md";
    license = licenses.asl20;
    platforms = platforms.all;
    maintainers = with maintainers; [
      adev
      magenbluten
    ];
  };
})
