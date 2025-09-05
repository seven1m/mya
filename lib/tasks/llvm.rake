namespace :llvm do
  LLVM_VERSION = '20.1.7'
  VENDOR_DIR = File.expand_path('../../vendor', __dir__)
  LLVM_PROJECT_DIR = "#{VENDOR_DIR}/llvm-project-#{LLVM_VERSION}"
  LLVM_BUILD_DIR = "#{LLVM_PROJECT_DIR}/build"
  LLVM_INSTALL_DIR = "#{VENDOR_DIR}/llvm-install"

  desc "Download and compile LLVM #{LLVM_VERSION}"
  task :install do
    FileUtils.mkdir_p(VENDOR_DIR)

    unless File.exist?("#{LLVM_PROJECT_DIR}/llvm/CMakeLists.txt")
      puts "Downloading LLVM project #{LLVM_VERSION}..."
      sh "curl -L https://github.com/llvm/llvm-project/releases/download/llvmorg-#{LLVM_VERSION}/llvm-project-#{LLVM_VERSION}.src.tar.xz | tar -xJ -C #{VENDOR_DIR}"
      FileUtils.mv("#{VENDOR_DIR}/llvm-project-#{LLVM_VERSION}.src", LLVM_PROJECT_DIR)
    end

    unless File.exist?("#{LLVM_INSTALL_DIR}/bin/llvm-config")
      puts "Building LLVM #{LLVM_VERSION}..."
      FileUtils.mkdir_p(LLVM_BUILD_DIR)

      Dir.chdir(LLVM_BUILD_DIR) do
        sh "cmake ../llvm -DCMAKE_INSTALL_PREFIX=#{LLVM_INSTALL_DIR} -DCMAKE_BUILD_TYPE=Release -DLLVM_ENABLE_RTTI=ON -DLLVM_BUILD_SHARED_LIBS=OFF -DLLVM_LINK_LLVM_DYLIB=ON -DLLVM_DYLIB_COMPONENTS=all -DLLVM_TARGETS_TO_BUILD=host"
        sh "make -j#{`nproc`.strip}"
        sh 'make install'
      end
    end

    puts "LLVM installed to: #{LLVM_INSTALL_DIR}"
  end

  desc 'Clean LLVM build files'
  task :clean do
    FileUtils.rm_rf(LLVM_PROJECT_DIR)
    FileUtils.rm_rf(LLVM_INSTALL_DIR)
  end
end
