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
  rake index            # same as index_codesearch
  rake index_codesearch
  rake index_milkode
End
end

task :all => [:mirror, :unpack, :index]

BASE_DIR = ENV['GEM_CODESEARCH_DIR'] || Dir.pwd
MIRROR_URL = ENV['GEM_CODESEARCH_URL'] || 'http://rubygems.org/'

MIRROR_DIR = "#{BASE_DIR}/mirror"
LATEST_DIR = "#{BASE_DIR}/latest-gem"
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
      clean_files("#{LATEST_DIR}/#{vname}")
    }
  }

end

task :index => :index_codesearch

INDEX_COMMAND = 'zoekt-index'
task :index_codesearch do
  FileUtils.rm_rf("zoekt-index")
  sh INDEX_COMMAND, "-index_dir", "zoekt-index", LATEST_DIR
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

def clean_files(dir)
  return unless File.exist? dir
  Find.find(dir) {|fn|
    st = File.lstat(fn)
    if st.file?
      if fn.end_with?('.ri')
        File.unlink fn
      end
    end
  }
end
