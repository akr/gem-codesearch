require 'rbconfig'
require 'fileutils'
require 'find'
require 'pp'

task :default => :help

task :help do
  puts <<'End'
Usage:
  rake help
  rake all              # mirror, unpack, index
  rake mirror
  rake unpack
  rake index            # same as index_zoekt
  rake index_zoekt
  rake index_codesearch # same as index_zoekt (for compatibility)
  rake index_milkode
  rake index_csearch
  rake clean_vendored   # remove vendored files from unpacked gems
  rake clean_files      # remove non-Ruby files from unpacked gems
End
end

task :all => [:mirror, :unpack, :index]

BASE_DIR = ENV['GEM_CODESEARCH_DIR'] || Dir.pwd
MIRROR_URL = ENV['GEM_CODESEARCH_URL'] || 'http://rubygems.org/'

MIRROR_DIR = "#{BASE_DIR}/mirror"
LATEST_DIR = ENV['GEM_CODESEARCH_GEM_DIR'] || "#{BASE_DIR}/latest-gem"
LOG_DIR = "#{BASE_DIR}/log"

GEM_COMMAND = "#{RbConfig::CONFIG["bindir"]}/gem"
MILK_COMMAND = "#{RbConfig::CONFIG["bindir"]}/milk"

file "#{BASE_DIR}/.gem/.mirrorrc" do |t|
  FileUtils.mkpath File.dirname(t.name)
  File.write(t.name, <<"End")
---
- from: #{MIRROR_URL}
  to: #{MIRROR_DIR}
  delete: true
End
end

task :mirror => "#{BASE_DIR}/.gem/.mirrorrc" do
  FileUtils.mkpath MIRROR_DIR
  # HOME is set because gem mirror reads $HOME/.gem/.mirrorrc.
  env = {"HOME"=>BASE_DIR}
  sh env, GEM_COMMAND, "mirror", "--verbose"
end

task :unpack do
  FileUtils.mkpath LOG_DIR

  available_gems = {}
  Dir.foreach("#{MIRROR_DIR}/gems") {|filename|
    next if /\.gem\z/ !~ filename
    available_gems[filename] = true
  }
  FileUtils.mkpath LATEST_DIR
  all_specs = File.open("#{MIRROR_DIR}/specs.4.8") {|f| Marshal.load(f) }
  all_specs = all_specs.reject {|name,version,platform|
    /\A\./ =~ name ||
    /\A[0-9a-zA-Z._-]+\z/ !~ name ||
    /\A[0-9a-zA-Z._-]+\z/ !~ version.to_s ||
    platform != 'ruby' ||
    !available_gems["#{name}-#{version}.gem"]
  }

  #all_specs = all_specs.reject {|name,version,platform| /\Afoo-/ !~ name }

  latest_vnames = []
  h = all_specs.group_by {|name,version| name }
  h.each {|name, list|
    list = list.sort_by {|name,version| version }
    vnames = list.map {|name,version| "#{name}-#{version}" }
    latest_vnames << vnames.pop
  }

  already_unpacked = Dir.entries(LATEST_DIR)
  already_unpacked = already_unpacked - %w[. ..]
  (already_unpacked - latest_vnames).each {|vname|
    puts "remove: #{vname}"
    FileUtils.rmtree("#{LATEST_DIR}/#{vname}")
  }

  File.open("#{LOG_DIR}/unpack.log.#{Time.now.strftime '%Y%m%dT%H%M%S%z'}", "a") {|log|
    (latest_vnames - already_unpacked).each {|vname|
      puts "unpack: #{vname}"
      system GEM_COMMAND, 'unpack', "#{MIRROR_DIR}/gems/#{vname}.gem", :chdir => LATEST_DIR, :out => log
      if !$?.success?
        puts "failed to unpack #{vname}"
      end
      fix_permission("#{LATEST_DIR}/#{vname}")
      clean_files("#{LATEST_DIR}/#{vname}", log)
      remove_vendored_dirs("#{LATEST_DIR}/#{vname}", log)
    }
  }

end

task :clean_vendored do
  FileUtils.mkpath LOG_DIR
  File.open("#{LOG_DIR}/clean_vendored.log.#{Time.now.strftime '%Y%m%dT%H%M%S%z'}", "a") {|log|
    vnames = Dir.entries(LATEST_DIR) - %w[. ..]
    vnames.sort.each {|vname|
      remove_vendored_dirs("#{LATEST_DIR}/#{vname}", log)
    }
  }
end

task :clean_files do
  FileUtils.mkpath LOG_DIR
  File.open("#{LOG_DIR}/clean_files.log.#{Time.now.strftime '%Y%m%dT%H%M%S%z'}", "a") {|log|
    vnames = Dir.entries(LATEST_DIR) - %w[. ..]
    vnames.sort.each {|vname|
      clean_files("#{LATEST_DIR}/#{vname}", log)
    }
  }
end

task :index => :index_zoekt
task :index_codesearch => :index_zoekt # for compatibility

INDEX_COMMAND = 'zoekt-index'
task :index_zoekt do
  FileUtils.rm_rf("zoekt-index")
  sh INDEX_COMMAND, "-index", "zoekt-index", LATEST_DIR
end

CSEARCH_COMMAND = 'cindex'
task :index_csearch do
  dir = File.join(BASE_DIR, "csearchindexes")
  FileUtils.mkpath dir
  [nil, *?a..?z].each do |prefix|
    env = { "CSEARCHINDEX" => File.join(dir, prefix || '_') }
    paths = Dir.glob(File.join(LATEST_DIR, ((prefix || '[ -_]') + "*"))).sort
    sh env, CSEARCH_COMMAND, "-reset", *paths
  end
end

task :index_milkode do
  # Assume default database for milkode is already created.
  # If not, do it as follows:
  #   milk init --default
  milkode_package_list = IO.popen([MILK_COMMAND, 'list']) {|f| f.read }
  package_name = File.basename(LATEST_DIR)
  if /^#{Regexp.escape package_name}$/ !~ milkode_package_list
    sh MILK_COMMAND, 'add', '--verbose', LATEST_DIR
  else
    sh MILK_COMMAND, 'update', '--verbose', package_name
  end
end

def fix_permission(dir)
  return unless File.exist? dir
  Find.find(dir) {|fn|
    st = File.lstat(fn)
    if st.file?
      if !st.readable?
        File.chmod(0644, fn)
      end
    elsif st.directory?
      if !st.readable? || !st.executable?
        File.chmod(0755, fn)
      end
    end
  }
end

# A directory named "gems" or "specifications" may be the gem's own code
# (e.g. Narnach-gems-0.3.0/lib/gems), so the name alone is not enough to
# judge it as a copy of a gem installation tree.
def vname_like?(name)
  /\A[A-Za-z0-9._-]+-\d+(\.\d+)*/ =~ name ? true : false
end

def vendored_dir?(dir)
  entries = Dir.entries(dir) - %w[. ..]
  case File.basename(dir)
  when "vendor", "node_modules", ".bundle"
    true
  when "gems"
    !entries.empty? && entries.all? {|e|
      File.directory?("#{dir}/#{e}") && vname_like?(e)
    }
  when "specifications"
    !entries.empty? && entries.all? {|e|
      e == "default" || (/\.gemspec\z/ =~ e && vname_like?(e))
    }
  else
    false
  end
end

def remove_vendored_dirs(dir, log)
  return unless File.exist? dir
  Find.find(dir) {|fn|
    next unless File.lstat(fn).directory?
    if vendored_dir?(fn)
      log.puts "remove vendored: #{fn}"
      FileUtils.rmtree(fn)
      Find.prune
    end
  }
end

# The corpus exists to search Ruby code (including the C code of native
# extensions and Ruby embedded in templates), so keep files by allowlist
# and remove everything else: other languages, docs, images, archives and
# binaries.
KEEP_EXTS = %w[
  .rb .rake .gemspec .ru .thor .gemfile .rbs .rbi
  .c .h .cpp .hpp .cc .hh .cxx .hxx .y .rl
  .erb .rhtml .haml .slim .builder .jbuilder .rabl .arb .mab
]
KEEP_BASENAMES = %w[
  Rakefile Gemfile Gemfile.lock Guardfile Capfile Vagrantfile Berksfile
  Thorfile Appraisals Dangerfile Fastfile Podfile Steepfile
]

def ruby_shebang?(fn)
  head = File.open(fn, "rb") {|f| f.gets("\n", 1024) }
  head ? /\A#!.*ruby/.match?(head) : false
rescue SystemCallError
  false
end

def keep_file?(fn)
  base = File.basename(fn)
  return true if KEEP_BASENAMES.include?(base)
  # Filenames may contain bytes that are not valid UTF-8, which makes
  # String#downcase raise ArgumentError.  Downcase as binary instead.
  ext = File.extname(base).b.downcase
  return KEEP_EXTS.include?(ext) unless ext.empty?
  ruby_shebang?(fn)
end

def clean_files(dir, log)
  return unless File.exist? dir
  dirs = []
  Find.find(dir) {|fn|
    st = File.lstat(fn)
    if st.directory?
      dirs << fn
    elsif st.file?
      if !keep_file?(fn)
        log.puts "remove file: #{fn}"
        File.unlink fn
      end
    else
      # symlinks (possibly dangling after cleanup), sockets, etc.
      log.puts "remove file: #{fn}"
      File.unlink fn
    end
  }
  # Remove directories emptied by the cleanup, but keep the gem's top
  # directory itself so the unpack task does not unpack the gem again.
  dirs.drop(1).reverse_each {|d|
    Dir.rmdir(d) if Dir.empty?(d)
  }
end
