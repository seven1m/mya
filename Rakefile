task :spec do
  require_relative 'spec/all'
end

task :docker_spec do
  sh "docker build -t mya . && docker run mya bundle exec rake spec"
end

task default: :spec
