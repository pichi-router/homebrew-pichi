class Pichi < Formula
  desc "Application Layer Proxy controlled via RESTful APIs"
  homepage "https://github.com/pichi-router/pichi"
  url "https://github.com/pichi-router/pichi/archive/1.3.0-rc.tar.gz"
  sha256 "69ce0bbf89bb693ab43cc8eb4a081dffb8ce7ae8bc765ce02de3b610c0f038f5"
  depends_on "cmake" => :build
  depends_on "rapidjson" => :build
  depends_on "boost"
  depends_on "libmaxminddb"
  depends_on "libsodium"
  depends_on "mbedtls"
  depends_on "openssl"

  def install
    cmake_args = *std_cmake_args
    cmake_args.delete_if { |opt| opt.start_with?("-DCMAKE_BUILD_TYPE") }
    cmake_args << "-DVERSION=1.2.1"
    cmake_args << "-DCMAKE_BUILD_TYPE=MinSizeRel"
    cmake_args << "-DBUILD_TEST=OFF"
    cmake_args << "-DSTATIC_LINK=OFF"
    cmake_args << "-DENABLE_TLS=ON"
    cmake_args << "-DINSTALL_HEADERS=ON"
    cmake_args << "-DOPENSSL_ROOT_DIR=" + Formula["openssl"].opt_prefix
    system "cmake", *cmake_args, "."
    system "cmake", "--build", buildpath.to_s, ENV.deparallelize
    system "cmake", "--build", buildpath.to_s, "--target", "install/strip"
    etc.install "server/pichi.json.default"
    libexec.install "test/geo.mmdb"
    (libexec/"sbin/run_pichi").write <<~EOS
      #!/bin/bash

      function get_pid()
      {
        ps -o "pid=" -p "$(cat ${1} 2>/dev/null)" 2>/dev/null
      }

      # Main
      set -o errexit

      prefix="#{HOMEBREW_PREFIX}"
      pichi="${prefix}/bin/pichi"
      pid="${prefix}/var/run/pichi.pid"
      log="${prefix}/var/log/pichi.log"

      # Run server
      "${pichi}" "$@" >>"${log}" 2>&1 &
      echo "$!" > "${pid}"
      if ! get_pid "${pid}" >/dev/null 2>&1; then
        echo "Failed to start pichi"
        exit 1
      fi
      trap "kill `cat ${pid}`" EXIT

      # Make server foreground
      wait
    EOS
    chmod 0555, (libexec/"sbin/run_pichi").to_s
  end

  plist_options :startup => true

  def plist; <<~EOS
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd";>
    <plist version="1.0">
      <dict>
        <key>Label</key>
        <string>#{plist_name}</string>
        <key>ProgramArguments</key>
        <array>
          <string>#{libexec}/sbin/run_pichi</string>
          <string>-p</string>
          <string>21127</string>
          <string>-l</string>
          <string>::1</string>
          <string>-g</string>
          <string>#{libexec}/geo.mmdb</string>
          <string>--json</string>
          <string>#{etc}/pichi.json</string>
        </array>
        <key>RunAtLoad</key>
        <true/>
        <key>HardResourceLimits</key>
        <dict>
          <key>NumberOfFiles</key>
          <integer>100000</integer>
        </dict>
        <key>SoftResourceLimits</key>
        <dict>
          <key>NumberOfFiles</key>
          <integer>100000</integer>
        </dict>
        <key>StandardOutPath</key>
        <string>#{var}/log/pichi.log</string>
        <key>StandardErrorPath</key>
        <string>#{var}/log/pichi.log</string>
      </dict>
    </plist>
  EOS
  end

  test do
    server = fork { exec bin/"pichi", "-p", "21127", "-g", libexec/"geo.mmdb" }
    sleep 3
    begin
      system "curl", "--noproxy", "localhost", "-f", "http://localhost:21127/ingresses"
      system "curl", "--noproxy", "localhost", "-f", "http://localhost:21127/egresses"
      system "curl", "--noproxy", "localhost", "-f", "http://localhost:21127/rules"
      system "curl", "--noproxy", "localhost", "-f", "http://localhost:21127/route"
    ensure
      Process.kill 15, server
      Process.wait server
    end
  end
end
