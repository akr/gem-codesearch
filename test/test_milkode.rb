require 'test/unit'
require 'tmpdir'
require 'fileutils'
require 'rbconfig'
require 'socket'
require 'pty'
require 'io/console'

GEM_COMMAND = "#{RbConfig::CONFIG["bindir"]}/gem"
MILK_COMMAND = "#{RbConfig::CONFIG["bindir"]}/milk"
RAKE_COMMAND = "#{RbConfig::CONFIG["bindir"]}/rake"

topdir = File.dirname(File.dirname(File.realpath(__FILE__)))
RAKEFILE = topdir + "/Rakefile"

class TestGemCodesearch < Test::Unit::TestCase
  def setup
    @workdir = Dir.mktmpdir('gem-codesearch')
    ENV['MILKODE_DEFAULT_DIR'] = "#{@workdir}/milkode"
  end

  def test_milk_init
    assert(!File.exist?("#{@workdir}/milkode"))
    system(MILK_COMMAND, 'init', '--default', :out => IO::NULL)
    assert($?.success?)
    assert(File.exist?("#{@workdir}/milkode"))
  end

  def start_gem_server
    gem_server_command = [GEM_COMMAND, 'server', '-b', '127.0.0.1', '-p', '0']
    pid = nil
    PTY.open {|m, s|
      s.raw!
      pid = spawn(*gem_server_command, :out => s, :err => IO::NULL)
      line = m.gets
      unless %r{Server started at (http:\S+)} =~ line
        flunk "unexpected 'gem server' message: #{line.inspect}"
      end
      url = $1
      yield [pid, url]
    }
  ensure
    if pid
      Process.kill :TERM, pid
      Process.wait pid
    end
  end

  def test_gem_server
    start_gem_server {|pid, url| }
  end

  def test_all
    start_gem_server {|pid, url|
      ENV['GEM_CODESEARCH_URL'] = url
      ENV['GEM_CODESEARCH_DIR'] = @workdir
      system(MILK_COMMAND, 'init', '--default', :out => IO::NULL)
      system(RAKE_COMMAND, '-f', RAKEFILE, 'all', [:out, :err] => IO::NULL)
    }
  end

  def teardown
    FileUtils.rmtree @workdir
    ENV['MILKODE_DEFAULT_DIR'] = nil
    ENV['GEM_CODESEARCH_URL'] = nil
    ENV['GEM_CODESEARCH_DIR'] = nil
  end
end
