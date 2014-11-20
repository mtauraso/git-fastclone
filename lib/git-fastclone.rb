require 'optparse'
require 'fileutils'
require_relative 'execution'

class GitFastClone
  def initialize()
    # Prefetch reference repos for submodules we've seen before
    # Keep our own reference accounting of module dependencies.
    @prefetch_submodules = true

    # Thread-level locking for reference repos
    # TODO: Add flock-based locking if we want to do more than one build on a given slave
    @reference_mutex = Hash.new { |hash, key| hash[key] = Mutex.new() }

    # Only update each reference repo once per run.
    # TODO: May want to update this if we're doing more than one build on a given slave.
    #       Perhaps a last-updated-time and a timeout per reference repo.
    @reference_updated = Hash.new { |hash, key| hash[key] = false }
  end

  def run()
    @reference_dir = ENV['REFERENCE_REPO_DIR'] || "/var/tmp/git-fastclone/reference"

    FileUtils.mkdir_p(@reference_dir)

    # One option --branch=<branch>  We're not as brittle as clone. That branch can be a sha or tag and we're still okay.
    @options = {}
    OptionParser.new do |opts|
      @options[:branch] = nil
      opts.on("-b", "--branch BRANCH", "Checkout this branch rather than the default") do |branch|
        @options[:branch] = branch
      end
      # TODO: add --verbose option that turns on and off printing of sub-commands
      # TODO: Add help text.
    end.parse!

    puts ARGV

    # Remaining two positional args are url and optional path
    url = ARGV[0]
    path = ARGV[1] || path_from_git_url(url)

    # Do a checkout with reference repositories for main and submodules
    clone(url, @options[:branch], File.join(Dir.pwd, path))
  end

  def path_from_git_url(url)
    # Get the checkout path from tail-end of the url.
    File.join(Dir.pwd, url.match(/([^\/]*)\.git$/)[1])
  end

  # Checkout to SOURCE_DIR. Update all submodules recursively. Use reference repos everywhere for speed.
  def clone(url, rev, src_dir)
    initial_time = Time.now()

    with_git_mirror(url) do |mirror|
      fail_on_error("git", "clone", "--reference", mirror, url, src_dir)
    end

    # Only checkout if we're changing branches to a non-default branch
    unless rev.nil? then
      fail_on_error("git", "checkout", rev, :chdir=>src_dir)
    end

    update_submodules(src_dir, url)

    final_time = Time.now()
    puts "Checkout of #{url} took #{final_time-initial_time}s"
  end

  # Update all submodules in current directory recursively
  # Use a reference repository for speed.
  # Use a separate thread for each submodule.
  def update_submodules (pwd, url)
    # Skip if there's no submodules defined
    if File.exist?(File.join(pwd,".gitmodules")) then

      # Update each submodule on a different thread.
      threads = []
      submodule_url_list = []

      # Init outputs all the info we need to run the update commands.
      # Parse its output directly to save time.
      fail_on_error("git", "submodule", "init", :chdir=>pwd).split("\n").each do |line|
        # Submodule path (not name) is in between single quotes '' at the end of the line
        submodule_path = File.join(pwd, line.strip.match(/'([^']*)'$/)[1])
        # URL is in between parentheses ()
        submodule_url = line.strip.match(/\(([^)]*)\)/)[1]
        submodule_url_list << submodule_url

        # Each update happens on a separate thread for speed.
        threads << Thread.new do
          with_git_mirror(submodule_url) do |mirror|
            fail_on_error("git", "submodule", "update", "--reference", mirror, submodule_path, :chdir=>pwd)
          end
          # Recurse into the submodule directory
          update_submodules(submodule_path, submodule_url)
        end
      end
      update_submodule_reference(url, submodule_url_list)
      threads.each {|t| t.join}
    end
  end

  def reference_repo_name(url)
    # Derive a unique directory name from the git url.
    url.gsub(/^.*:\/\//, "").gsub(/^[^@]*@/, "").gsub("/","-").gsub(":","-")
  end

  def reference_repo_dir(url)
    File.join(@reference_dir, reference_repo_name(url))
  end

  def reference_repo_submodule_file(url)
    # ':' is never a valid char in a reference repo dir, so this
    # uniquely maps to a particular reference repo.
    "#{reference_repo_dir(url)}:submodules.txt"
  end

  def with_reference_repo_lock(url)
    @reference_mutex[reference_repo_name(url)].synchronize do
      yield
    end
  end

  def update_submodule_reference(url, submodule_url_list)
    if submodule_url_list != [] and @prefetch_submodules then
      with_reference_repo_lock(url) do

        # Write the dependency file using submodule list
        File.open(reference_repo_submodule_file(url), 'w') do |f|
          submodule_url_list.each do |submodule_url|
            f.write("#{submodule_url}\n")
          end
        end

      end
    end
  end

  def update_reference_repo(url)
    repo_name = reference_repo_name(url)
    mirror = reference_repo_dir(url)

    with_reference_repo_lock(url) do
      submodule_file = reference_repo_submodule_file(url)
      if File.exist?(submodule_file) and @prefetch_submodules then
        File.readlines(submodule_file).each do |line|
          # We don't join these threads explicitly
          Thread.new { update_reference_repo(line.strip) }
        end
      end

      if !@reference_updated[repo_name] then
        if !Dir.exist?(mirror)
          fail_on_error("git", "clone", "--mirror", url, mirror)
        end
        fail_on_error("git", "remote", "update", :chdir=> mirror)
        @reference_updated[repo_name] = true
      end
    end
  end

  # Executes a block passing in the directory of an up-to-date local git mirror
  # for the given url. This will speed up most git commands that ask for data
  # over the network after the mirror is cloned initially.
  #
  # This command will create and bring the mirror up-to-date on-demand,
  # blocking any code passed in while the mirror is brought up-to-date
  #
  # In future we may need to synchronize with flock here if we run multiple builds
  # at once against the same reference repos. One build per slave at the moment means
  # we only need to synchronize our own threads in case a single submodule url is
  # included twice via multiple dependency paths
  def with_git_mirror(url)
    update_reference_repo(url)

    # May want to lock the reference repo for this, but don't need to for how we use this.
    yield reference_repo_dir(url)
  end
end
