# gem-codesearch

gem-codesearch sets up a full text code search engine on mirror of rubygems.
It use rubygems-mirror to mirror rubygems and milkode for search engine.

## Usage

    % gem install gem-codesearch
    % milk init --default               # If you use milkode first time
    % mkdir $HOME/gem-codesearch        # Make a some directory
    % cd $HOME/gem-codesearch
    % gem-codesearch-setup all >& setup.log # It may take several days or more
    % gmilk -p latest-gem sort_by       # Enjoy code search

## Usage without install

    % gem install rubygems-mirror milkode
    % milk init --default               # If you use milkode first time
    % cd $HOME
    % git clone https://github.com/akr/gem-codesearch.git
    % cd gem-codesearch
    % rake all >& setup.log             # It may take several days or more
    % gmilk -p latest-gem sort_by       # Enjoy code search

## Author

Tanaka Akira
akr@fsij.org

