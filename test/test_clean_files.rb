require 'test/unit'
require 'tmpdir'
require 'fileutils'
require 'rbconfig'

topdir = File.dirname(File.dirname(File.realpath(__FILE__)))
CLEAN_FILES_RAKEFILE = topdir + "/Rakefile"

class TestCleanFiles < Test::Unit::TestCase
  def setup
    @workdir = Dir.mktmpdir('gem-codesearch')
    @latest = "#{@workdir}/latest-gem"
  end

  def put_file(relpath, content="")
    path = "#{@latest}/#{relpath}"
    FileUtils.mkpath File.dirname(path)
    File.write(path, content)
  end

  def run_clean_files
    env = { 'GEM_CODESEARCH_DIR' => @workdir }
    system(env, RbConfig.ruby, '-S', 'rake', '-f', CLEAN_FILES_RAKEFILE,
           'clean_files', [:out, :err] => IO::NULL)
    assert($?.success?)
  end

  def test_keeps_ruby_and_c_and_templates
    %w[
      lib/foo.rb
      Rakefile
      Gemfile
      Gemfile.lock
      foo.gemspec
      config.ru
      sig/foo.rbs
      rbi/foo.rbi
      tasks/foo.rake
      ext/foo/extconf.rb
      ext/foo/foo.c
      ext/foo/foo.h
      ext/foo/bar.cpp
      ext/foo/parser.y
      ext/foo/scanner.rl
      app/views/index.html.erb
      app/views/show.haml
      app/views/edit.slim
      app/views/feed.builder
    ].each {|relpath| put_file "foo-1.0/#{relpath}" }
    run_clean_files
    %w[
      lib/foo.rb Rakefile Gemfile Gemfile.lock foo.gemspec config.ru
      sig/foo.rbs rbi/foo.rbi tasks/foo.rake
      ext/foo/extconf.rb ext/foo/foo.c ext/foo/foo.h ext/foo/bar.cpp
      ext/foo/parser.y ext/foo/scanner.rl
      app/views/index.html.erb app/views/show.haml app/views/edit.slim
      app/views/feed.builder
    ].each {|relpath|
      assert(File.exist?("#{@latest}/foo-1.0/#{relpath}"), relpath)
    }
  end

  def test_removes_non_ruby_files
    %w[
      lib/foo.rb
      README.md
      LICENSE.txt
      doc/index.html
      app/assets/app.js
      java/foo.jar
      log/test.log
      cache/bar-1.0.gem
      images/logo.png
      lib/foo.so
    ].each {|relpath| put_file "foo-1.0/#{relpath}" }
    run_clean_files
    assert(File.exist?("#{@latest}/foo-1.0/lib/foo.rb"))
    %w[
      README.md LICENSE.txt doc/index.html app/assets/app.js java/foo.jar
      log/test.log cache/bar-1.0.gem images/logo.png lib/foo.so
    ].each {|relpath|
      assert(!File.exist?("#{@latest}/foo-1.0/#{relpath}"), relpath)
    }
  end

  def test_extensionless_files_kept_by_ruby_shebang
    put_file "foo-1.0/bin/foo", "#!/usr/bin/env ruby\nputs :foo\n"
    put_file "foo-1.0/bin/foo2", "#!/usr/local/bin/ruby -w\nputs :foo\n"
    put_file "foo-1.0/bin/wkhtmltopdf", "\x7fELF\x02\x01\x01\x00".b
    put_file "foo-1.0/LICENSE", "MIT License\n"
    run_clean_files
    assert(File.exist?("#{@latest}/foo-1.0/bin/foo"))
    assert(File.exist?("#{@latest}/foo-1.0/bin/foo2"))
    assert(!File.exist?("#{@latest}/foo-1.0/bin/wkhtmltopdf"))
    assert(!File.exist?("#{@latest}/foo-1.0/LICENSE"))
  end

  def test_removes_symlinks
    put_file "foo-1.0/lib/foo.rb"
    File.symlink("foo.rb", "#{@latest}/foo-1.0/lib/link.rb")
    File.symlink("missing", "#{@latest}/foo-1.0/lib/dangling")
    run_clean_files
    assert(File.exist?("#{@latest}/foo-1.0/lib/foo.rb"))
    assert(!File.symlink?("#{@latest}/foo-1.0/lib/link.rb"))
    assert(!File.symlink?("#{@latest}/foo-1.0/lib/dangling"))
  end

  def test_removes_emptied_dirs_but_keeps_gem_dir
    put_file "foo-1.0/images/logo.png"
    run_clean_files
    assert(!File.exist?("#{@latest}/foo-1.0/images"))
    assert(File.directory?("#{@latest}/foo-1.0"))
  end

  def test_logs_removed_paths
    put_file "foo-1.0/app.js"
    run_clean_files
    logs = Dir.glob("#{@workdir}/log/clean_files.log.*")
    assert_equal(1, logs.size)
    assert_match(%r{remove file: .*/foo-1\.0/app\.js$}, File.read(logs[0]))
  end

  def teardown
    FileUtils.rmtree @workdir
  end
end
