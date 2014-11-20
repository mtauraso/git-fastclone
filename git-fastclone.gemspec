Gem::Specification.new do |s|
  s.name = "git-fastclone"
  s.version = "0.0.0"
  s.date = "2014-11-19"
  s.summary = "git-clone --recursive on steroids!"
  s.description = "A git command that uses reference repositories and multithreading to quickly and recursively clone repositories with many nested submodules"
  s.authors = ["Michael Tauraso"]
  s.email = "mtauraso@gmail.com"
  s.executables = [
    "git-fastclone"
  ]
  s.files = [
    "lib/execution.rb",
    "lib/git-fastclone.rb",
    "bin/git-fastclone"
  ]
  s.homepage = "https://rubygems.org/gems/git-fastclone"
  s.license = "MIT"
end


