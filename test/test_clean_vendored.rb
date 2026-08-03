require 'test/unit'
require 'tmpdir'
require 'fileutils'
require 'rbconfig'

topdir = File.dirname(File.dirname(File.realpath(__FILE__)))
CLEAN_VENDORED_RAKEFILE = topdir + "/Rakefile"

class TestCleanVendored < Test::Unit::TestCase
  def setup
    @workdir = Dir.mktmpdir('gem-codesearch')
    @latest = "#{@workdir}/latest-gem"
  end

  def put_file(relpath)
    path = "#{@latest}/#{relpath}"
    FileUtils.mkpath File.dirname(path)
    File.write(path, "")
  end

  def run_clean_vendored
    env = { 'GEM_CODESEARCH_DIR' => @workdir }
    system(env, RbConfig.ruby, '-S', 'rake', '-f', CLEAN_VENDORED_RAKEFILE,
           'clean_vendored', [:out, :err] => IO::NULL)
    assert($?.success?)
  end

  def test_removes_vendored_dirs
    put_file "foo-1.0/lib/foo.rb"
    put_file "foo-1.0/vendor/bundle/ruby/2.3.0/gems/rails-4.2.0/lib/rails.rb"
    put_file "foo-1.0/lib/node_modules/through2/index.js"
    put_file "foo-1.0/.bundle/config"
    run_clean_vendored
    assert(File.exist?("#{@latest}/foo-1.0/lib/foo.rb"))
    assert(!File.exist?("#{@latest}/foo-1.0/vendor"))
    assert(!File.exist?("#{@latest}/foo-1.0/lib/node_modules"))
    assert(!File.exist?("#{@latest}/foo-1.0/.bundle"))
  end

  def test_removes_embedded_gem_tree
    put_file "bar-2.0/lib/ruby/gems/2.2.0/gems/rake-10.4.2/lib/rake.rb"
    put_file "bar-2.0/lib/ruby/gems/2.2.0/specifications/rake-10.4.2.gemspec"
    put_file "bar-2.0/lib/ruby/gems/2.2.0/specifications/default/json-1.8.1.gemspec"
    run_clean_vendored
    assert(File.exist?("#{@latest}/bar-2.0/lib/ruby/gems/2.2.0"))
    assert(!File.exist?("#{@latest}/bar-2.0/lib/ruby/gems/2.2.0/gems"))
    assert(!File.exist?("#{@latest}/bar-2.0/lib/ruby/gems/2.2.0/specifications"))
  end

  def test_keeps_own_code_named_gems
    put_file "Narnach-gems-0.3.0/lib/gems/base.rb"
    put_file "baz-1.0/lib/gems/README"
    run_clean_vendored
    assert(File.exist?("#{@latest}/Narnach-gems-0.3.0/lib/gems/base.rb"))
    assert(File.exist?("#{@latest}/baz-1.0/lib/gems/README"))
  end

  def test_keeps_mixed_gems_dir
    put_file "qux-1.0/lib/gems/rake-10.4.2/lib/rake.rb"
    put_file "qux-1.0/lib/gems/helper.rb"
    run_clean_vendored
    assert(File.exist?("#{@latest}/qux-1.0/lib/gems/helper.rb"))
  end

  def test_logs_removed_paths
    put_file "foo-1.0/vendor/x.rb"
    run_clean_vendored
    logs = Dir.glob("#{@workdir}/log/clean_vendored.log.*")
    assert_equal(1, logs.size)
    assert_match(%r{remove vendored: .*/foo-1\.0/vendor$}, File.read(logs[0]))
  end

  def teardown
    FileUtils.rmtree @workdir
  end
end
