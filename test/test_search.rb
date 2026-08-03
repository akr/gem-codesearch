require 'test/unit'
require 'tmpdir'
require 'fileutils'
require 'rbconfig'
require 'rubygems/package'

topdir = File.dirname(File.dirname(File.realpath(__FILE__)))
GEM_CODESEARCH_COMMAND = topdir + "/bin/gem-codesearch"

class TestGemCodesearchSearch < Test::Unit::TestCase
  def setup
    @workdir = Dir.mktmpdir('gem-codesearch')
    FileUtils.mkpath "#{@workdir}/csearchindexes"
    File.write("#{@workdir}/csearchindexes/_", "")
    File.write("#{@workdir}/csearchindexes/a", "")
    FileUtils.mkpath "#{@workdir}/mirror/gems"
    write_gem_file("#{@workdir}/mirror/gems/foo-1.0.gem", "date: 2024-01-02")
    write_gem_file("#{@workdir}/mirror/gems/bar-2.0.gem", "date: 2023-05-06")
    @csearch = "#{@workdir}/csearch"
    write_csearch(<<"End")
#!/bin/sh
case "$CSEARCHINDEX" in
*/_)
  echo "#{@workdir}/latest-gem/bar-2.0/lib/x.rb:use bar"
  ;;
*/a)
  echo "#{@workdir}/latest-gem/foo-1.0/lib/a.rb:def bar"
  echo "#{@workdir}/latest-gem/foo-1.0/lib/b.rb:bar again"
  ;;
esac
End
  end

  def write_csearch(script)
    File.write(@csearch, script)
    File.chmod(0755, @csearch)
  end

  def write_gem_file(path, metadata)
    File.open(path, "wb") {|io|
      Gem::Package::TarWriter.new(io) {|tar|
        tar.add_file("metadata", 0644) {|f| f.write metadata }
      }
    }
  end

  def run_search(args = [], extra_env = {})
    env = {
      'GEM_CODESEARCH_DIR' => @workdir,
      'GEM_CODESEARCH_CSEARCH' => @csearch,
    }.merge(extra_env)
    IO.popen([env, RbConfig.ruby, GEM_CODESEARCH_COMMAND, *args, 'bar']) {|io| io.read }
  end

  def test_prefix_removed
    assert_equal(<<"End", run_search)
2023-05-06 bar-2.0/lib/x.rb:use bar
2024-01-02 foo-1.0/lib/a.rb:def bar
2024-01-02 foo-1.0/lib/b.rb:bar again
End
  end

  def test_prefix_removed_with_gem_dir
    write_csearch(<<"End")
#!/bin/sh
case "$CSEARCHINDEX" in
*/_)
  echo "/srv/gems/foo-1.0/lib/foo.rb:def bar"
  ;;
esac
End
    output = run_search([], 'GEM_CODESEARCH_GEM_DIR' => '/srv/gems')
    assert_equal("2024-01-02 foo-1.0/lib/foo.rb:def bar\n", output)
  end

  def test_summary
    assert_equal(<<"End", run_search(['--summary']))
2024-01-02 foo-1.0 2 lib/a.rb
2023-05-06 bar-2.0 1 lib/x.rb
End
  end

  def teardown
    FileUtils.rmtree @workdir
  end
end
