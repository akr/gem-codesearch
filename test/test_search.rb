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
    FileUtils.mkpath "#{@workdir}/mirror/gems"
    write_gem_file("#{@workdir}/mirror/gems/foo-1.0.gem", "date: 2024-01-02")
    @csearch = "#{@workdir}/csearch"
    File.write(@csearch, <<"End")
#!/bin/sh
echo "#{@workdir}/latest-gem/foo-1.0/lib/foo.rb:def bar"
End
    File.chmod(0755, @csearch)
  end

  def write_gem_file(path, metadata)
    File.open(path, "wb") {|io|
      Gem::Package::TarWriter.new(io) {|tar|
        tar.add_file("metadata", 0644) {|f| f.write metadata }
      }
    }
  end

  def run_search(extra_env = {})
    env = {
      'GEM_CODESEARCH_DIR' => @workdir,
      'GEM_CODESEARCH_CSEARCH' => @csearch,
    }.merge(extra_env)
    IO.popen([env, RbConfig.ruby, GEM_CODESEARCH_COMMAND, 'bar']) {|io| io.read }
  end

  def test_prefix_removed
    assert_equal("2024-01-02 foo-1.0/lib/foo.rb:def bar\n", run_search)
  end

  def test_prefix_removed_with_gem_dir
    FileUtils.mv "#{@workdir}/csearch", "#{@workdir}/csearch.orig"
    File.write("#{@workdir}/csearch", <<"End")
#!/bin/sh
echo "/srv/gems/foo-1.0/lib/foo.rb:def bar"
End
    File.chmod(0755, "#{@workdir}/csearch")
    output = run_search('GEM_CODESEARCH_GEM_DIR' => '/srv/gems')
    assert_equal("2024-01-02 foo-1.0/lib/foo.rb:def bar\n", output)
  end

  def teardown
    FileUtils.rmtree @workdir
  end
end
