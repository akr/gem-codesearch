require_relative "lib/gem_codesearch/mcp_app"

run GemCodesearch.mcp_app(token: ENV.fetch("GEM_CODESEARCH_MCP_TOKEN"))
