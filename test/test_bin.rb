require 'test/unit'
require 'rbconfig'

RUBY_COMMAND = RbConfig.ruby

topdir = File.dirname(File.dirname(File.realpath(__FILE__)))
GEM_CODESEARCH_SETUP_COMMAND = topdir + "/bin/gem-codesearch-setup"

class TestGemCodesearch < Test::Unit::TestCase
  def test_setup_help
    command = [RUBY_COMMAND, GEM_CODESEARCH_SETUP_COMMAND, 'help']
    message = IO.popen(command) {|io|
      io.read
    }
    assert_match(/rake help/, message)
    assert_match(/rake all/, message)
  end
end
