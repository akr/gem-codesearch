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
    FileUtils.mkpath "#{@workdir}/latest-gem/foo-1.0/lib"
    File.write("#{@workdir}/latest-gem/foo-1.0/lib/a.rb", (1..5).map {|n| "l#{n}\n" }.join)
    File.write("#{@workdir}/latest-gem/foo-1.0/foo.gemspec", "spec\n")
    File.write("#{@workdir}/outside.txt", "secret\n")
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

  def call_tool(name, arguments)
    res = post_json({
      jsonrpc: "2.0", id: 1, method: "tools/call",
      params: { name: name, arguments: arguments },
    })
    assert_equal(200, res.status)
    JSON.parse(res.body)["result"]
  end

  def call_search(arguments)
    call_tool("search", arguments)
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
    assert_equal(["search", "read_file", "list_files"], tools.map {|t| t["name"] })
    assert_equal(["pattern"], tools[0]["inputSchema"]["required"])
    assert_equal(["path"], tools[1]["inputSchema"]["required"])
    assert_equal(["path"], tools[2]["inputSchema"]["required"])
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

  def test_read_file
    result = call_tool("read_file", { path: "foo-1.0/lib/a.rb" })
    assert_equal(false, result["isError"])
    assert_equal(<<"End", result["content"][0]["text"])
1: l1
2: l2
3: l3
4: l4
5: l5
End
  end

  def test_read_file_range
    result = call_tool("read_file", { path: "foo-1.0/lib/a.rb", start_line: 2, end_line: 3 })
    assert_equal("2: l2\n3: l3\n", result["content"][0]["text"])
  end

  def test_read_file_capped_by_server
    set_env('GEM_CODESEARCH_MCP_MAX_LINES', "2")
    result = call_tool("read_file", { path: "foo-1.0/lib/a.rb" })
    text = result["content"][0]["text"]
    assert_include(text, "2: l2\n")
    assert_not_include(text, "3: l3")
    assert_include(text, "showing lines 1-2 of 5")
  end

  def test_read_file_start_line_beyond_eof
    result = call_tool("read_file", { path: "foo-1.0/lib/a.rb", start_line: 10 })
    assert_equal(true, result["isError"])
  end

  def test_read_file_missing
    result = call_tool("read_file", { path: "foo-1.0/lib/nonexistent.rb" })
    assert_equal(true, result["isError"])
    assert_include(result["content"][0]["text"], "no such file")
  end

  def test_read_file_traversal
    result = call_tool("read_file", { path: "../outside.txt" })
    assert_equal(true, result["isError"])
    assert_include(result["content"][0]["text"], "outside the corpus")
    assert_not_include(result["content"][0]["text"], "secret")
  end

  def test_read_file_symlink_escape
    File.symlink("#{@workdir}/outside.txt", "#{@workdir}/latest-gem/foo-1.0/link.rb")
    result = call_tool("read_file", { path: "foo-1.0/link.rb" })
    assert_equal(true, result["isError"])
    assert_include(result["content"][0]["text"], "outside the corpus")
  end

  def test_list_files
    result = call_tool("list_files", { path: "foo-1.0" })
    assert_equal(false, result["isError"])
    assert_equal("foo.gemspec\nlib/a.rb\n", result["content"][0]["text"])
  end

  def test_list_files_subdirectory
    result = call_tool("list_files", { path: "foo-1.0/lib" })
    assert_equal("a.rb\n", result["content"][0]["text"])
  end

  def test_list_files_capped_by_server
    set_env('GEM_CODESEARCH_MCP_MAX_LINES', "1")
    result = call_tool("list_files", { path: "foo-1.0" })
    text = result["content"][0]["text"]
    assert_include(text, "foo.gemspec\n")
    assert_not_include(text, "lib/a.rb")
    assert_include(text, "showing 1 of 2 files")
  end

  def test_list_files_missing
    result = call_tool("list_files", { path: "nonexistent-1.0" })
    assert_equal(true, result["isError"])
    assert_include(result["content"][0]["text"], "no such directory")
  end

  def test_list_files_traversal
    result = call_tool("list_files", { path: ".." })
    assert_equal(true, result["isError"])
    assert_include(result["content"][0]["text"], "outside the corpus")
  end

  def test_list_files_symlink_escape
    FileUtils.mkpath "#{@workdir}/elsewhere"
    File.symlink("#{@workdir}/elsewhere", "#{@workdir}/latest-gem/foo-1.0/vendor")
    result = call_tool("list_files", { path: "foo-1.0/vendor" })
    assert_equal(true, result["isError"])
    assert_include(result["content"][0]["text"], "outside the corpus")
  end

  def test_mcp_app_requires_token
    assert_raise(ArgumentError) { GemCodesearch.mcp_app(token: "") }
  end
end
