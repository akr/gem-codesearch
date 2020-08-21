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

## Links

- https://github.com/akr/gem-codesearch
- https://rubygems.org/gems/gem-codesearch

## Author

Tanaka Akira
akr@fsij.org

