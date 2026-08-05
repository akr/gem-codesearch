require 'test/unit'
require 'tmpdir'
require 'fileutils'
require 'json'
require 'rubygems/package'
require 'rack/mock_request'
require_relative '../lib/gem_codesearch/mcp_app'

class TestGemCodesearchMCPApp < Test::Unit::TestCase
  TOKEN = "test-token"

  def setup
    @workdir = Dir.mktmpdir('gem-codesearch')
    FileUtils.mkpath "#{@workdir}/csearchindexes"
    File.write("#{@workdir}/csearchindexes/a", "")
    FileUtils.mkpath "#{@workdir}/mirror/gems"
    write_gem_file("#{@workdir}/mirror/gems/foo-1.0.gem", "date: 2024-01-02")
    @csearch = "#{@workdir}/csearch"
    write_csearch(<<"End")
#!/bin/sh
echo "#{@workdir}/latest-gem/foo-1.0/lib/a.rb:def bar"
echo "#{@workdir}/latest-gem/foo-1.0/lib/b.rb:bar again"
echo "#{@workdir}/latest-gem/foo-1.0/lib/c.rb:bar the third"
End
    @saved_env = {}
    set_env('GEM_CODESEARCH_DIR', @workdir)
    set_env('GEM_CODESEARCH_CSEARCH', @csearch)
    @app = GemCodesearch.mcp_app(token: TOKEN)
  end

  def teardown
    @saved_env.each {|k, v| ENV[k] = v }
    FileUtils.rmtree @workdir
  end

  def set_env(key, value)
    @saved_env[key] = ENV[key] unless @saved_env.key?(key)
    ENV[key] = value
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

  def post_json(payload, token: TOKEN)
    headers = {
      "CONTENT_TYPE" => "application/json",
      "HTTP_ACCEPT" => "application/json, text/event-stream",
      :input => JSON.dump(payload),
    }
    headers["HTTP_AUTHORIZATION"] = "Bearer #{token}" if token
    Rack::MockRequest.new(@app).post("/", headers)
  end

  def call_search(arguments)
    res = post_json({
      jsonrpc: "2.0", id: 1, method: "tools/call",
      params: { name: "search", arguments: arguments },
    })
    assert_equal(200, res.status)
    JSON.parse(res.body)["result"]
  end

  def test_unauthorized_without_token
    res = post_json({ jsonrpc: "2.0", id: 1, method: "ping" }, token: nil)
    assert_equal(401, res.status)
  end

  def test_unauthorized_with_wrong_token
    res = post_json({ jsonrpc: "2.0", id: 1, method: "ping" }, token: "wrong")
    assert_equal(401, res.status)
  end

  def test_initialize
    res = post_json({
      jsonrpc: "2.0", id: 1, method: "initialize",
      params: {
        protocolVersion: "2025-03-26",
        capabilities: {},
        clientInfo: { name: "test", version: "0" },
      },
    })
    assert_equal(200, res.status)
    result = JSON.parse(res.body)["result"]
    assert_equal("gem-codesearch", result["serverInfo"]["name"])
  end

  def test_tools_list
    res = post_json({ jsonrpc: "2.0", id: 1, method: "tools/list" })
    assert_equal(200, res.status)
    tools = JSON.parse(res.body)["result"]["tools"]
    assert_equal(["search"], tools.map {|t| t["name"] })
    assert_equal(["pattern"], tools[0]["inputSchema"]["required"])
  end

  def test_search
    result = call_search({ pattern: "bar" })
    assert_equal(false, result["isError"])
    assert_equal(<<"End", result["content"][0]["text"])
2024-01-02 foo-1.0/lib/a.rb:def bar
2024-01-02 foo-1.0/lib/b.rb:bar again
2024-01-02 foo-1.0/lib/c.rb:bar the third
End
  end

  def test_search_summary
    result = call_search({ pattern: "bar", summary: true })
    assert_equal("2024-01-02 foo-1.0 3 lib/a.rb\n", result["content"][0]["text"])
  end

  def test_search_truncation
    result = call_search({ pattern: "bar", max_lines: 2 })
    text = result["content"][0]["text"]
    assert_include(text, "lib/b.rb")
    assert_not_include(text, "lib/c.rb")
    assert_include(text, "showing 2 of 3 lines")
  end

  def test_search_max_lines_capped_by_server
    set_env('GEM_CODESEARCH_MCP_MAX_LINES', "1")
    result = call_search({ pattern: "bar", max_lines: 100 })
    assert_include(result["content"][0]["text"], "showing 1 of 3 lines")
  end

  def test_search_no_matches
    write_csearch("#!/bin/sh\nexit 1\n")
    result = call_search({ pattern: "bar" })
    assert_equal("no matches", result["content"][0]["text"])
  end

  def test_search_timeout
    set_env('GEM_CODESEARCH_MCP_TIMEOUT', "1")
    write_csearch("#!/bin/sh\nsleep 30\n")
    result = call_search({ pattern: "bar" })
    assert_equal(true, result["isError"])
    assert_include(result["content"][0]["text"], "timed out")
  end

  def test_mcp_app_requires_token
    assert_raise(ArgumentError) { GemCodesearch.mcp_app(token: "") }
  end
end
