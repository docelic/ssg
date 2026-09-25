require "option_parser"

module SSG
  module CLI
    USAGE = <<-TEXT
      Usage: ssg <command> [options]

      Commands:
        init DIR Create a new site skeleton in DIR
        build    Render the site into the output directory
        orphans  List output files that nothing in the site produces,
                 without building (-0: NUL-terminated, for xargs -0)
        serve    Build, serve locally, and rebuild on changes
                 (base_url defaults to the local address)
        hugo-convert [-w] FILE...
                 Translate Hugo shortcode calls to Jinja calls (stdout, or
                 with -w write FILE.j2 next to each FILE)
        version  Print version
      TEXT

    def self.run(argv = ARGV)
      root = Dir.current
      drafts = false
      clean = false
      touch = false
      base_url = nil
      nul = false
      port = 1313
      command = nil
      write = false
      files = [] of String

      parser = OptionParser.new do |p|
        p.banner = USAGE
        p.on("-s DIR", "--source DIR", "Site root (default: current directory)") { |d| root = File.expand_path(d) }
        p.on("-D", "--drafts", "Include draft pages") { drafts = true }
        p.on("--clean", "Remove the output directory before building") { clean = true }
        p.on("--touch", "Update the mtime of unchanged output files too") { touch = true }
        p.on("-b URL", "--base-url URL", "Override base_url from config") { |u| base_url = u }
        p.on("-0", "--null", "orphans: separate paths with NUL instead of newline") { nul = true }
        p.on("-p PORT", "--port PORT", "Port for serve (default 1313)") { |v| port = v.to_i }
        p.on("-w", "--write", "hugo-convert: write FILE.j2 instead of printing") { write = true }
        p.on("-h", "--help", "Show help") { puts p; exit }
        p.unknown_args { |args| command = args.first?; files = args.size > 1 ? args[1..] : [] of String }
        p.invalid_option { |o| abort "unknown option #{o}\n#{p}" }
      end
      parser.parse(argv)

      case command
      when "init"
        Init.run(files.first? || abort("init: directory required"))
      when "build"   then Builder.build(root, drafts: drafts, clean: clean, touch: touch, base_url: base_url)
      when "orphans" then Builder.print_orphans(Builder.orphans(root, drafts: drafts, base_url: base_url), STDOUT, nul)
      when "serve"   then Server.new(root, port, drafts, base_url).run
      when "hugo-convert"
        abort "hugo-convert: no files given" if files.empty?
        HugoConvert.run(files, write)
      when "version" then puts "ssg #{VERSION}"
      else                abort parser.to_s
      end
    rescue e : Error
      abort "error: #{e.message}"
    end
  end
end
