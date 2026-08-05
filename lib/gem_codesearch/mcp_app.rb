require "json"
require "rbconfig"
require "timeout"
require "rack"
require "mcp"

module GemCodesearch
  DEFAULT_TIMEOUT = 30
  DEFAULT_MAX_LINES = 200

  def self.search_command
    ENV["GEM_CODESEARCH_COMMAND"] || File.expand_path("../../bin/gem-codesearch", __dir__)
  end

  def self.gem_dir
    base = ENV["GEM_CODESEARCH_DIR"] || Dir.pwd
    File.expand_path(ENV["GEM_CODESEARCH_GEM_DIR"] || "#{base}/latest-gem")
  end

  def self.max_lines
    (ENV["GEM_CODESEARCH_MCP_MAX_LINES"] || DEFAULT_MAX_LINES).to_i
  end

  # Runs bin/gem-codesearch and returns [output, total_lines, timed_out, status].
  # The process group is killed on timeout so csearch children do not survive.
  def self.run_search(argv, timeout:, max_lines:)
    r, w = IO.pipe
    pid = spawn(RbConfig.ruby, search_command, *argv, out: w, err: w, pgroup: true)
    w.close
    lines = []
    total = 0
    reader = Thread.new do
      while line = r.gets
        total += 1
        lines << line if lines.size < max_lines
      end
    end
    timed_out = false
    begin
      Timeout.timeout(timeout) { Process.wait(pid) }
    rescue Timeout::Error
      timed_out = true
      begin
        Process.kill(:KILL, -pid)
      rescue Errno::ESRCH
      end
      Process.wait(pid)
    end
    reader.join
    r.close
    [lines.join, total, timed_out, $?]
  end

  class SearchTool < MCP::Tool
    tool_name "search"
    description <<~DESC
      Search the source code of the latest version of every gem published on
      rubygems.org with an RE2 regular expression.  Each hit line is
      "YYYY-MM-DD GEMNAME-VERSION/PATH:MATCHED_LINE" where the date is the
      release date of the gem.  The corpus contains only Ruby-related files.
    DESC
    input_schema(
      properties: {
        pattern: {
          type: "string",
          description: "RE2 regular expression matched against source lines",
        },
        file_pattern: {
          type: "string",
          description: "only report files whose path matches this regular expression",
        },
        ignore_case: {
          type: "boolean",
          description: "case-insensitive match",
        },
        summary: {
          type: "boolean",
          description: "print one line per gem (date, gem-version, match count, first path) sorted by match count, instead of individual hits",
        },
        max_lines: {
          type: "integer",
          description: "maximum number of output lines (capped by the server)",
        },
      },
      required: ["pattern"],
    )

    class << self
      def call(pattern:, file_pattern: nil, ignore_case: false, summary: false, max_lines: nil, server_context: nil)
        argv = []
        argv << "--summary" if summary
        argv << "-i" if ignore_case
        argv.push("-f", file_pattern) if file_pattern
        argv << pattern

        cap = GemCodesearch.max_lines
        limit = max_lines && max_lines > 0 ? [max_lines, cap].min : cap
        timeout = (ENV["GEM_CODESEARCH_MCP_TIMEOUT"] || DEFAULT_TIMEOUT).to_f

        output, total, timed_out, status = GemCodesearch.run_search(argv, timeout: timeout, max_lines: limit)

        if timed_out
          return error_response("search timed out after #{timeout}s; use a more selective pattern or summary:true")
        end
        unless status.success?
          return error_response("search failed:\n#{output}")
        end
        return text_response("no matches") if total == 0

        text = output
        if total > limit
          text += "\n(truncated: showing #{limit} of #{total} lines; refine the pattern, use file_pattern, or set summary:true)"
        end
        text_response(text)
      end

      private

      def text_response(text)
        MCP::Tool::Response.new([{ type: "text", text: text }])
      end

      def error_response(text)
        MCP::Tool::Response.new([{ type: "text", text: text }], error: true)
      end
    end
  end

  class ReadFileTool < MCP::Tool
    tool_name "read_file"
    description <<~DESC
      Read a file from the unpacked gem corpus.  Use the path exactly as
      reported by the search tool: "GEMNAME-VERSION/PATH", e.g.
      "rack-3.2.6/lib/rack.rb".  Each returned line is prefixed with its
      line number.
    DESC
    input_schema(
      properties: {
        path: {
          type: "string",
          description: "file path as reported by search, e.g. rack-3.2.6/lib/rack.rb",
        },
        start_line: {
          type: "integer",
          description: "first line to return (1-based, default 1)",
        },
        end_line: {
          type: "integer",
          description: "last line to return (inclusive, default: end of file, capped by the server)",
        },
      },
      required: ["path"],
    )

    class << self
      def call(path:, start_line: nil, end_line: nil, server_context: nil)
        base = GemCodesearch.gem_dir
        full = File.expand_path(path, base)
        unless full.start_with?(base + "/")
          return error_response("path is outside the corpus: #{path}")
        end
        unless File.file?(full)
          return error_response("no such file: #{path}")
        end
        full = File.realpath(full)
        unless full.start_with?(File.realpath(base) + "/")
          return error_response("path is outside the corpus: #{path}")
        end

        lines = File.readlines(full)
        return text_response("(empty file)") if lines.empty?

        first = start_line && start_line > 0 ? start_line : 1
        return error_response("start_line #{first} is beyond the end of the file (#{lines.size} lines)") if first > lines.size
        last = end_line && end_line >= first ? [end_line, lines.size].min : lines.size

        cap = GemCodesearch.max_lines
        truncated = last - first + 1 > cap
        last = first + cap - 1 if truncated

        width = last.to_s.size
        text = (first..last).map {|n| "%*d: %s\n" % [width, n, lines[n - 1].chomp.scrub] }.join
        if truncated
          text += "(truncated: showing lines #{first}-#{last} of #{lines.size}; request a narrower range)"
        end
        text_response(text)
      end

      private

      def text_response(text)
        MCP::Tool::Response.new([{ type: "text", text: text }])
      end

      def error_response(text)
        MCP::Tool::Response.new([{ type: "text", text: text }], error: true)
      end
    end
  end

  class TokenAuth
    def initialize(app, token)
      @app = app
      @token = token
    end

    def call(env)
      header = env["HTTP_AUTHORIZATION"].to_s
      if Rack::Utils.secure_compare(header, "Bearer #{@token}")
        @app.call(env)
      else
        [401, { "content-type" => "text/plain" }, ["unauthorized\n"]]
      end
    end
  end

  def self.mcp_app(token:)
    raise ArgumentError, "token must not be empty" if token.nil? || token.empty?
    server = MCP::Server.new(name: "gem-codesearch", tools: [SearchTool, ReadFileTool])
    # Host/Origin validation is left to the HTTPS reverse proxy in front of
    # this app; the Bearer token protects direct access.
    transport = MCP::Server::Transports::StreamableHTTPTransport.new(
      server,
      stateless: true,
      enable_json_response: true,
      dns_rebinding_protection: false,
    )
    TokenAuth.new(transport, token)
  end
end
