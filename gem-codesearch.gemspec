Gem::Specification.new do |s|
  s.name = 'gem-codesearch'
  s.version = '0.1'
  s.date = '2015-01-09'
  s.author = 'Tanaka Akira'
  s.email = 'akr@fsij.org'
  s.required_ruby_version = '>= 2.2.0'
  s.add_runtime_dependency 'rubygems-mirror', '~> 1.0', '>= 1.0.1'
  s.add_runtime_dependency 'milkode', '~> 1.8', '>= 1.8.6'
  s.add_runtime_dependency 'rake', '~> 10.4', '>= 10.4.2'
  s.executables << 'gem-codesearch-setup'
  s.files = %w[
    README.md
    Rakefile
    bin/gem-codesearch-setup
  ]
  s.homepage = 'https://github.com/akr/gem-codesearch'
  s.license = 'MIT'
  s.summary = 'Set up a full text code search engine for rubygems mirror'
  s.description = <<'End'
gem-codesearch sets up a full text code search engine for rubygems mirror.
It use rubygems-mirror to mirror rubygems and
milkode for search engine.
End
end
