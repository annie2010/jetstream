require "fileutils"
require "open3"
require "thor"
require "yaml"

GITIGNORE_CONTENTS = <<GITIGNORE
.jet/
GITIGNORE

module JetCLI
  class Logger
    def self.error(s)
      puts s
    end

    def self.info(s)
      puts s
    end
  end

  class Shell
    def self.create_directory(path, overwrite=false)
      if self.directory_exists?(path)
        if overwrite
          return true
        else
          Logger::error "FAILED: directory #{path} already exists!"
          return false
        end
      else
        Logger::info " - creating directory #{path}"
        Dir.mkdir(path)
        return true
      end
    end

    def self.remove_directory!(path)
      if path == "/"
        Logger::error "You tried to `rm -rf /`, you fool!"
        exit 1
      end

      if self.directory_exists?(path)
        FileUtils.rm_rf(path)
      end

      return true
    end


    def self.create_file(path, contents, overwrite=false)
      if not overwrite and self.file_exists?(path)
        Logger::error "FAILED: file #{path} already exists!"
        return false
      else
        Logger::info " - creating file #{path}"
        file = File.new(path, "w")
        file.write(contents)
        file.close
        return true
      end
    end

    def self.directory_exists?(path)
      Dir.exists?(path)
    end

    def self.file_exists?(path)
      File.exists?(path)
    end

    def self.cmd(cmd, verbose=true)
      STDOUT.sync = true
      Open3.popen3(cmd) do |stdin, stdout, stderr, thread|
        while line=stdout.gets or line=stderr.gets
          if verbose then Logger::info line end
        end
      end
    end
  end

  class ConfigFile
    def self.read
      if not Shell::file_exists?("jetstream.yml")
        Logger::error "FAILED: Couldn't find a jetstream.yml file!"
        exit 1
      end

      return YAML::load_file("jetstream.yml")
    end

    def self.create_default!(name)
      default_config = {
        "name" => name,
        "description" => "an awesome package",
        "author" => "@you",
        "version" => "0.0.1",
        "dependencies" => [
          "base"
        ]
      }

      Shell::create_file(
        "#{name}/jetstream.yml",
        YAML::dump(default_config)
      ) or exit 1
    end
  end

  class Project < Thor
    desc "create [NAME]", "Create a jet project"
    def create(name)
      # TODO validate name [A-Za-z0-9_]+

      Logger::info("Creating project '#{name}'...")
      Shell::create_directory("#{name}/") or exit 1
      Shell::create_directory("#{name}/.jet/") or exit 1
      Shell::create_directory("#{name}/resources/") or exit 1

      Shell::create_file(
        "#{name}/.gitignore",
        GITIGNORE_CONTENTS
      ) or exit 1

      ConfigFile::create_default!(name)

      Logger::info("Done!")
    end
  end

  class Jet < Thor
    desc "compile", "Pull dependencies and compile resource templates into .jet"
    def compile
      if not in_project?
        Logger::error "FAILED: Couldn't find a jetstream project!"
        exit 1
      end

      config = ConfigFile::read

      puts config
    end

    desc "clean", "Remove all compiled files for current jet project."
    def clean
      if not in_project?
        Logger::error "FAILED: Couldn't find a jetstream project!"
        exit 1
      end

      Shell::remove_directory!(".jet/compiled")

      puts "Done!"
    end


    desc "configure", "Configure the current jet project"
    def configure
      if not in_project?
        Logger::error "FAILED: Couldn't find a jetstream project!"
        exit 1
      end

      access_key_id = ask("Access Key ID:")
      secret_access_key = ask("Secret Access Key:")

      provider_config = <<PROVIDER_CONFIG
provider "aws" {
  access_key = "#{access_key_id}"
  secret_key = "#{secret_access_key}"
  region = "us-east-1"
}
PROVIDER_CONFIG

      Shell::create_directory(
        ".jet/compiled",
        true
      ) or exit 1

      Shell::create_file(
        ".jet/compiled/provider.tf",
        provider_config,
        true
      ) or exit 1

      Logger::info("Done!")
    end

    desc "plan", "example task"
    def plan
      cmd = <<CMD
/usr/bin/terraform plan -input=false \
                        -state=/data/state/terraform.tfstate \
				        -var-file=/data/state/variables.tfvars \
                        -refresh=true \
                        /data/terraform
CMD
      Shell::cmd(cmd)
    end

    desc "apply", "example task"
    def apply
      cmd = <<CMD
/usr/bin/terraform apply -input=false \
                         -state=/data/state/terraform.tfstate \
				         -var-file=/data/state/variables.tfvars \
                         -refresh=true \
                         /data/terraform
CMD
      Shell::cmd(cmd)
    end

    desc "project <subcommand>", "Manage jet projects"
    subcommand "project", Project

    private

    def in_project?
      return Shell.directory_exists?("./.jet")
    end
  end

  Jet.start(ARGV)
end
