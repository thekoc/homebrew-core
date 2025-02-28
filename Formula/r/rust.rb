class Rust < Formula
  desc "Safe, concurrent, practical language"
  homepage "https://www.rust-lang.org/"
  license any_of: ["Apache-2.0", "MIT"]

  stable do
    url "https://static.rust-lang.org/dist/rustc-1.74.0-src.tar.gz"
    sha256 "882b584bc321c5dcfe77cdaa69f277906b936255ef7808fcd5c7492925cf1049"

    # From https://github.com/rust-lang/rust/tree/#{version}/src/tools
    resource "cargo" do
      url "https://github.com/rust-lang/cargo/archive/refs/tags/0.75.0.tar.gz"
      sha256 "d6b9512bca4b4d692a242188bfe83e1b696c44903007b7b48a56b287d01c063b"
    end
  end

  bottle do
    sha256 cellar: :any,                 arm64_sonoma:   "4b21da961caf6a07da1a060289a9582bbffc10dcd64f68e2e4e4e1af2e057c06"
    sha256 cellar: :any,                 arm64_ventura:  "6e1f064619902bec9e5dfb26ac55b5e287372b62ce6e234b31c4c807c00dbe52"
    sha256 cellar: :any,                 arm64_monterey: "058460f7f14b2aec5fd0324fcda09f1b59635514513ba4f3240d298e1752be75"
    sha256 cellar: :any,                 sonoma:         "ab812c8acc40ebf09c615acd8c5c9db351916e02ae2dab18e79faf71e17c85ca"
    sha256 cellar: :any,                 ventura:        "7f1acd1ed3ce57ca0b1c7fff889fa6665273a34b28cd16dccc3db3e51f5d2420"
    sha256 cellar: :any,                 monterey:       "7173f18b220068bfb3693087999e37f0394b03932607a1a6e5d3a3f4082a85e6"
    sha256 cellar: :any_skip_relocation, x86_64_linux:   "262c9474e64e64b89a87d086f141993a46992fb3be348454944a16c0695ac43a"
  end

  head do
    url "https://github.com/rust-lang/rust.git", branch: "master"

    resource "cargo" do
      url "https://github.com/rust-lang/cargo.git", branch: "master"
    end
  end

  depends_on "libgit2"
  depends_on "libssh2"
  depends_on "llvm"
  depends_on macos: :sierra
  depends_on "openssl@3"
  depends_on "pkg-config"

  uses_from_macos "python" => :build
  uses_from_macos "curl"
  uses_from_macos "zlib"

  # From https://github.com/rust-lang/rust/blob/#{version}/src/stage0.json
  resource "cargobootstrap" do
    on_macos do
      on_arm do
        url "https://static.rust-lang.org/dist/2023-10-05/cargo-1.73.0-aarch64-apple-darwin.tar.xz"
        sha256 "caa855d28ade0ecb70567d886048d392b3b90f15a7751f9733d4c189ce67bb71"
      end
      on_intel do
        url "https://static.rust-lang.org/dist/2023-10-05/cargo-1.73.0-x86_64-apple-darwin.tar.xz"
        sha256 "94f9eb5836fe59a3ef1d1d4c99623d602b0cec48964c5676453be4205df3b28a"
      end
    end

    on_linux do
      on_arm do
        url "https://static.rust-lang.org/dist/2023-10-05/cargo-1.73.0-aarch64-unknown-linux-gnu.tar.xz"
        sha256 "1195a1d37280802574d729cf00e0dadc63a7c9312a9ae3ef2cf99645f7be0a77"
      end
      on_intel do
        url "https://static.rust-lang.org/dist/2023-10-05/cargo-1.73.0-x86_64-unknown-linux-gnu.tar.xz"
        sha256 "7c3ce5738d570eaea97dd3d213ea73c8beda4f0c61e7486f95e497b7b10c4e2d"
      end
    end
  end

  # Fixes 'could not read dir ".../codegen-backends"' on 12-arm64.
  # See https://github.com/Homebrew/homebrew-core/pull/154526#issuecomment-1814795860
  patch :DATA

  def install
    # Ensure that the `openssl` crate picks up the intended library.
    # https://docs.rs/openssl/latest/openssl/#manual
    ENV["OPENSSL_DIR"] = Formula["openssl@3"].opt_prefix

    ENV["LIBGIT2_NO_VENDOR"] = "1"
    ENV["LIBSSH2_SYS_USE_PKG_CONFIG"] = "1"

    if OS.mac?
      # Requires the CLT to be the active developer directory if Xcode is installed
      ENV["SDKROOT"] = MacOS.sdk_path
      # Fix build failure for compiler_builtins "error: invalid deployment target
      # for -stdlib=libc++ (requires OS X 10.7 or later)"
      ENV["MACOSX_DEPLOYMENT_TARGET"] = MacOS.version
    end

    resource("cargobootstrap").stage do
      system "./install.sh", "--prefix=#{buildpath}/cargobootstrap"
    end
    ENV.prepend_path "PATH", buildpath/"cargobootstrap/bin"

    cargo_src_path = buildpath/"src/tools/cargo"
    cargo_src_path.rmtree
    resource("cargo").stage cargo_src_path
    if OS.mac?
      inreplace cargo_src_path/"Cargo.toml",
                /^curl\s*=\s*"(.+)"$/,
                'curl = { version = "\\1", features = ["force-system-lib-on-osx"] }'
    end

    # rustfmt and rust-analyzer are available in their own formulae.
    tools = %w[
      analysis
      cargo
      clippy
      rustdoc
      rust-demangler
      src
    ]
    args = %W[
      --prefix=#{prefix}
      --sysconfdir=#{etc}
      --tools=#{tools.join(",")}
      --llvm-root=#{Formula["llvm"].opt_prefix}
      --enable-llvm-link-shared
      --enable-vendor
      --disable-cargo-native-static
      --set=rust.jemalloc
      --release-description=#{tap.user}
    ]
    if build.head?
      args << "--disable-rpath"
      args << "--release-channel=nightly"
    else
      args << "--release-channel=stable"
    end

    system "./configure", *args
    system "make"
    system "make", "install"

    (lib/"rustlib/src/rust").install "library"
    rm_f [
      bin.glob("*.old"),
      lib/"rustlib/install.log",
      lib/"rustlib/uninstall.sh",
      (lib/"rustlib").glob("manifest-*"),
    ]
  end

  def post_install
    Dir["#{lib}/rustlib/**/*.dylib"].each do |dylib|
      chmod 0664, dylib
      MachO::Tools.change_dylib_id(dylib, "@rpath/#{File.basename(dylib)}")
      MachO.codesign!(dylib) if Hardware::CPU.arm?
      chmod 0444, dylib
    end
  end

  def check_binary_linkage(binary, library)
    binary.dynamically_linked_libraries.any? do |dll|
      next false unless dll.start_with?(HOMEBREW_PREFIX.to_s)

      File.realpath(dll) == File.realpath(library)
    end
  end

  test do
    system bin/"rustdoc", "-h"
    (testpath/"hello.rs").write <<~EOS
      fn main() {
        println!("Hello World!");
      }
    EOS
    system bin/"rustc", "hello.rs"
    assert_equal "Hello World!\n", shell_output("./hello")
    system bin/"cargo", "new", "hello_world", "--bin"
    assert_equal "Hello, world!", cd("hello_world") { shell_output("#{bin}/cargo run").split("\n").last }

    # We only check the tools' linkage here. No need to check rustc.
    expected_linkage = {
      bin/"cargo" => [
        Formula["libgit2"].opt_lib/shared_library("libgit2"),
        Formula["libssh2"].opt_lib/shared_library("libssh2"),
        Formula["openssl@3"].opt_lib/shared_library("libcrypto"),
        Formula["openssl@3"].opt_lib/shared_library("libssl"),
      ],
    }
    unless OS.mac?
      expected_linkage[bin/"cargo"] += [
        Formula["curl"].opt_lib/shared_library("libcurl"),
        Formula["zlib"].opt_lib/shared_library("libz"),
      ]
    end
    missing_linkage = []
    expected_linkage.each do |binary, dylibs|
      dylibs.each do |dylib|
        next if check_binary_linkage(binary, dylib)

        missing_linkage << "#{binary} => #{dylib}"
      end
    end
    assert missing_linkage.empty?, "Missing linkage: #{missing_linkage.join(", ")}"
  end
end

__END__
diff --git a/src/bootstrap/compile.rs b/src/bootstrap/compile.rs
index 292ccc5780f..7266badf501 100644
--- a/src/bootstrap/compile.rs
+++ b/src/bootstrap/compile.rs
@@ -546,7 +546,9 @@ fn run(self, builder: &Builder<'_>) {
                 .join("stage0/lib/rustlib")
                 .join(&host)
                 .join("codegen-backends");
-            builder.cp_r(&stage0_codegen_backends, &sysroot_codegen_backends);
+            if stage0_codegen_backends.exists() {
+                builder.cp_r(&stage0_codegen_backends, &sysroot_codegen_backends);
+            }
         }
     }
 }
