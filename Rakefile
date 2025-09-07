load 'lib/tasks/llvm.rake'

task default: :spec

desc 'Build project'
task build: ['build/lib.ll']

desc 'Run specs'
task spec: :build do
  require 'minitest/fail_fast' if ENV['TESTOPTS'] == '--fail-fast'
  require_relative 'spec/all'
end

desc 'Watch for file changes and run specs'
task :watch do
  files = Dir['**/*.rb', 'src/*.c']
  sh %(ls #{files.join(' ')} | entr -c -s 'TESTOPTS="--fail-fast" bundle exec rake spec')
end

desc 'Run specs in a Docker container'
task :docker_spec do
  sh 'docker build -t mya . && docker run mya bundle exec rake spec'
end

file 'build/lib.ll' => 'src/lib.c' do
  mkdir_p 'build'
  sh 'clang -o build/lib.ll -S -emit-llvm src/lib.c'
end

desc 'Format code'
task :format do
  sh 'stree write **/*.rb'
  sh 'clang-format -i src/lib.c'
end

desc 'Run lint (syntax-check only for now)'
task :lint do
  sh 'stree check **/*.rb'
  sh 'clang-format --dry-run --Werror src/lib.c'
end

desc 'Run lint in a Docker container'
task :docker_lint do
  sh 'docker build -t mya . && docker run mya bundle exec rake lint'
end
