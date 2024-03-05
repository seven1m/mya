task default: :spec

task build: ['build/lib.ll']

task spec: :build do
  require 'minitest/fail_fast' if ENV['TESTOPTS'] == '--fail-fast'
  require_relative 'spec/all'
end

task :watch do
  files = Dir['**/*.rb', 'src/*.c']
  sh %(ls #{files.join(' ')} | entr -c -s 'TESTOPTS="--fail-fast" bundle exec rake spec')
end

task :docker_spec do
  sh 'docker build -t mya . && docker run mya bundle exec rake spec'
end

file 'build/lib.ll' => 'src/lib.c' do
  mkdir_p 'build'
  sh 'clang -o build/lib.ll -S -emit-llvm src/lib.c'
end
