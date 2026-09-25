require "http/server"

module SSG
  # Development server: serves the output directory (index.html for
  # directories), rebuilds when a source file changes, and reloads open
  # browser tabs after each rebuild via a small injected script.
  class Server
    @generation = 0

    def initialize(@root : String, @port : Int32 = 1313, @drafts : Bool = false, @base_url : String? = nil)
    end

    def run
      config = Config.load(@root)
      outdir = config.output_dir
      rebuild

      handler = Handler.new(outdir, ->{ @generation })
      server = HTTP::Server.new([HTTP::LogHandler.new, handler])
      address = server.bind_tcp("127.0.0.1", @port)
      STDERR.puts "serving #{outdir} at http://#{address}"
      spawn watch(config)
      server.listen
    end

    private def rebuild
      Builder.build(@root, drafts: @drafts, base_url: @base_url || "http://127.0.0.1:#{@port}/")
      @generation += 1
    rescue e : Error
      STDERR.puts "build failed: #{e.message}"
    end

    private def watch(config : Config)
      last = fingerprint(config)
      loop do
        sleep 1.second
        now = fingerprint(config)
        next if now == last
        last = now
        STDERR.puts "change detected, rebuilding"
        rebuild
      end
    end

    private def fingerprint(config : Config) : UInt64
      h = 0_u64
      dirs = [config.content_dir] + config.layout_dirs + config.static_dirs + config.data_dirs
      files = [File.join(@root, "config.yml")]
      dirs.each { |d| files.concat(Dir.glob(File.join(d, "**", "*"))) if Dir.exists?(d) }
      files.each do |f|
        info = File.info?(f) || next
        h = h &* 31 &+ f.hash &+ info.modification_time.to_unix_ns.to_u64! &+ info.size
      end
      h
    end

    class Handler
      include HTTP::Handler

      RELOAD_PATH = "/__ssg/generation"

      def initialize(@dir : String, @generation : -> Int32)
      end

      def call(context)
        req = context.request.path
        if req == RELOAD_PATH
          context.response.content_type = "text/plain"
          context.response.print @generation.call
          return
        end

        rel = URI.decode(req).lchop('/')
        path = File.expand_path(rel, @dir)
        unless path.starts_with?(@dir)
          context.response.respond_with_status(:forbidden)
          return
        end
        if File.directory?(path)
          unless req.ends_with?('/')
            context.response.redirect(req + "/")
            return
          end
          path = File.join(path, "index.html")
        end
        unless File.file?(path)
          context.response.respond_with_status(:not_found)
          return
        end
        context.response.content_type = MIME.from_filename(path, "application/octet-stream")
        if path.ends_with?(".html")
          context.response.print inject(File.read(path))
        else
          File.open(path) { |f| IO.copy(f, context.response) }
        end
      end

      private def inject(html : String) : String
        script = <<-HTML
          <script>
          (function () {
            var g0 = "#{@generation.call}";
            setInterval(function () {
              fetch("#{RELOAD_PATH}", {cache: "no-store"}).then(function (r) { return r.text(); })
                .then(function (g) { if (g !== g0) location.reload(); }).catch(function () {});
            }, 1000);
          })();
          </script>
          HTML
        if i = html.rindex("</body>")
          html[0...i] + script + html[i..]
        else
          html + script
        end
      end
    end
  end
end
