task :spec do
  require_relative 'spec/all'
end

task :watch do
  files = Dir['**/*.rb']
  sh "ls #{files.join(' ')} | entr -c -s 'bundle exec rake spec'"
end

task :docker_spec do
  sh 'docker build -t mya . && docker run mya bundle exec rake spec'
end

task default: :spec
