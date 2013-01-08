require "vise/shell_tools"
require 'thor'
require 'fileutils'
require 'tmpdir'
require 'uri'

module Hammer
  class CLI < Thor
    include Vise::ShellTools

    desc "new PROJECT_NAME", "generate a new binary project"
    def new(name)
      puts "Creating buildpack skeleton..."
      puts "#{name}/"
      FileUtils.mkdir(name)

      Dir.chdir(name) do
        puts "#{name}/bin"
        FileUtils.mkdir("bin")
        puts "#{name}/bin/detect"
        puts "#{name}/bin/release"
        puts "#{name}/bin/compile"
        FileUtils.cp_r(File.join(vendor_dir, "bin"), ".")
        puts "#{name}/bundle/"
        FileUtils.cp_r(File.join(vendor_dir, "bundle"), ".")
        puts "#{name}/Gemfile"
        FileUtils.cp(File.join(vendor_dir, "Gemfile"), ".")
        puts "#{name}/Gemfile.lock"
        FileUtils.cp(File.join(vendor_dir, "Gemfile.lock"), ".")
      end
    end

    desc "build", "builds the binary"
    method_option :local, :type => :boolean, :default => false,
      :desc => "flag to do a local build"
    method_option :debug, :type => :boolean, :default => false,
      :desc => "set build to be debugged"
    method_option :build, :type => :string, :default => ".",
      :desc => "path to the build scripts"
    method_option :env, :type => :hash,
      :desc => "build environment to pass to the build script"
    def build
      env = {:DEBUG => options[:debug]}
      cmd = ""
      if env.values.any?
        cmd << "env "
        env.each do |key, value|
          cmd << "#{key}=#{value}" if value
        end
        cmd << " "
      end

      if options[:local]
        tmpdir    = Dir.mktmpdir
        build_dir = "#{tmpdir}/build"
        cache_dir = "#{tmpdir}/cache"
        FileUtils.mkdir_p build_dir
        FileUtils.mkdir_p cache_dir

        puts "Building..."
        cmd << "bin/compile #{build_dir} #{cache_dir}"
        pipe cmd
        puts "Done."

        require 'digest/sha1'
        package_name = Digest::SHA1.hexdigest(rand.to_s)
        Dir.chdir(build_dir) do
          puts "Packaging..."
          pipe "tar cvf ../#{package_name}.tgz ."
        end
        FileUtils.mv("#{tmpdir}/#{package_name}.tgz", ".")
        puts "tarball here: ./#{package_name}.tgz"
      else
        require 'anvil/engine'
        slug_url = nil
        pwd      = Dir.pwd

        Dir.mktmpdir do |dir|
          system("cp -rf #{options[:build]}/* #{dir}")

          Dir.chdir(dir) do
            FileUtils.cp_r(File.join(vendor_dir, "bin"), ".")
            FileUtils.cp_r(File.join(vendor_dir, "bundle"), ".")
            FileUtils.cp(File.join(vendor_dir, "Gemfile"), ".")
            FileUtils.cp(File.join(vendor_dir, "Gemfile.lock"), ".")

            if options[:env]
              File.open('env', 'wb') do |file|
                options[:env].each {|k, v| file.puts "#{k}=#{v}" }
              end
            end

            slug_url = Anvil::Engine.build(".", :buildpack => ".")
          end
        end

        Dir.mktmpdir do |dir|
          filename = URI.parse(slug_url).path.sub("/slugs/", "")

          Dir.chdir(dir) do
            system("curl -O #{slug_url}")
            system("tar zxf #{filename}")
            system("rm -rf #{filename} .profile.d .bundle Procfile .gitignore")
            system("tar czf #{filename} *")
            system("mv #{filename} #{pwd}")
          end
        end
      end
    ensure
      if options[:local]
        if env[:DEBUG]
          puts "Build artifacts here: #{tmpdir}"
        else
          FileUtils.rm_rf(tmpdir)
        end
      end
    end

    private
    def write_bin_file(name, contents)
      File.open(name, 'wb') do |file|
        file.chmod(0755)
        file.puts contents
      end
    end

    def vendor_dir
      File.join(File.dirname(__FILE__), "vendor")
    end

    def read_bin_file(name)
      File.read(File.join(vendor_dir, "bin/#{name}"))
    end
  end
end
