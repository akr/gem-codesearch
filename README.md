# gem-codesearch

gem-codesearch sets up a full text code search engine on mirror of rubygems.
It use rubygems-mirror to mirror rubygems and codesearch for search engine.

400GB of free disk space is required to store the rubygems mirror,
unpacked gems and codesearch index at 2016-01.
It will be larger in future.

## Usage

This creates "latest-gem" package in zoekt index.

    # Install zoekt from GitHub repository: https://github.com/google/zoekt 
    % gem install gem-codesearch
    % mkdir $HOME/gem-codesearch        # Make a some directory
    % cd $HOME/gem-codesearch
    % gem-codesearch-setup all >& setup.log # It may take several days or more

If "gem-codesearch-setup all" fails due to network or server errors,
try again to continue.

After the index is created, enjoy code search.

    % zoekt -index_dir $HOME/gem-codesearch/zoekt-index sort_by

You can search without `-index_dir` option after creating the symlink
named `.zoekt` to HOME directory

## Usage without install

    % sudo aptitude install codesearch  # https://github.com/google/codesearch
    % gem install rubygems-mirror
    % cd $HOME
    % git clone https://github.com/akr/gem-codesearch.git
    % cd gem-codesearch
    % rake all >& setup.log             # It may take several days or more

## Use milkode instead of zoekt

    % gem install milkode
    % milk init --default               # If you use milkode first time
    % rake mirror unpack index_milkode >& setup.log

## Use codesearch instead of zoekt

    $ rake mirror unpack index_csearch

This creates a set of indexes for csearch in gem-codesearch/csearchindexes.
Use the gem-codesearch command to search them:

    % GEM_CODESEARCH_DIR=$HOME/gem-codesearch gem-codesearch PATTERN

It runs csearch over all the indexes and prints each hit prefixed with
the release date of the gem:

    YYYY-MM-DD GEMNAME-VERSION/PATH:MATCHED_LINE

The path is relative to the unpack directory.
Set GEM_CODESEARCH_GEM_DIR if the unpack directory is not
GEM_CODESEARCH_DIR/latest-gem.

The --summary option prints one line per gem instead of individual
hits, sorted by the number of matched lines:

    YYYY-MM-DD GEMNAME-VERSION COUNT FIRST_PATH

Other arguments are passed to csearch as usual.  With csearch's -l
option COUNT means the number of files instead of matched lines.

## File filtering

The corpus is intended for searching Ruby code, so the unpack task keeps
only Ruby-related files and removes everything else (other languages,
docs, images, archives and binaries).  Kept files are: Ruby sources and
DSLs (.rb, .rake, .gemspec, .ru, .thor, .gemfile, .rbs, .rbi and
well-known names such as Rakefile, Gemfile and Gemfile.lock), C/C++
sources of native extensions (.c, .h, .cpp, .hpp, .cc, .hh, .cxx, .hxx,
.y, .rl), templates that embed Ruby (.erb, .rhtml, .haml, .slim,
.builder, .jbuilder, .rabl, .arb, .mab), and extensionless files whose
shebang line mentions ruby.

Use "rake clean_files" to apply the policy to already unpacked gems.

## MCP server

The csearch indexes can be exposed to MCP clients over the Streamable
HTTP transport.  This repository provides only a Rack application that
requires Bearer token authentication.  It serves plain HTTP and does
not handle TLS.  Run it behind an HTTPS reverse proxy (nginx, Caddy,
etc.) that terminates TLS.  The reverse proxy configuration,
certificates and service management are out of scope for this
repository.

The application needs the mcp and rack gems and a Rack server.
`StreamableHTTPTransport` keeps no cross-request state here (stateless
mode), but keep the deployment simple with a single process bound to
localhost:

    % gem install mcp rack puma
    % cd $HOME/gem-codesearch-src   # checkout of this repository
    % GEM_CODESEARCH_DIR=$HOME/gem-codesearch \
      GEM_CODESEARCH_MCP_TOKEN=SECRET \
      puma -b tcp://127.0.0.1:9292 config.ru

Every request must carry `Authorization: Bearer SECRET`; anything else
gets 401.  The server refuses to boot without
GEM_CODESEARCH_MCP_TOKEN.  Host/Origin validation is disabled in the
Rack application because the reverse proxy in front is expected to
route only its own virtual host.

The server exposes a single `search` tool which runs the
gem-codesearch command described above.  Arguments: `pattern`
(required RE2 regexp), `file_pattern` (csearch -f), `ignore_case`
(csearch -i), `summary` (--summary) and `max_lines`.  Each search is
killed after GEM_CODESEARCH_MCP_TIMEOUT seconds (default 30) and the
output is capped at GEM_CODESEARCH_MCP_MAX_LINES lines (default 200,
also an upper bound for `max_lines`).

Register it in Claude Code with:

    % claude mcp add --transport http gem-codesearch \
        https://HOST/ --header "Authorization: Bearer SECRET"

## Links

- https://github.com/akr/gem-codesearch
- https://rubygems.org/gems/gem-codesearch

## Author

Tanaka Akira
akr@fsij.org

