# gem-codesearch

gem-codesearch sets up a full text code search engine on mirror of rubygems.
It use rubygems-mirror to mirror rubygems and milkode for search engine.

## Usage

This creates "latest-gem" package in milkode index.

    % gem install gem-codesearch
    % milk init --default               # If you use milkode first time
    % mkdir $HOME/gem-codesearch        # Make a some directory
    % cd $HOME/gem-codesearch
    % gem-codesearch-setup all >& setup.log # It may take several days or more

If "gem-codesearch-setup all" fails due to network or server errors,
try again.

After the index is created, enjoy code search.

    % gmilk -p latest-gem sort_by

## Usage without install

    % gem install rubygems-mirror milkode
    % milk init --default               # If you use milkode first time
    % cd $HOME
    % git clone https://github.com/akr/gem-codesearch.git
    % cd gem-codesearch
    % rake all >& setup.log             # It may take several days or more

## Author

Tanaka Akira
akr@fsij.org

