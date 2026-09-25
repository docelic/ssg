require "./spec_helper"

# Stand-in for a real pdf converter: proves the mechanism without a backend.
class FakePdf < SSG::Chain::Converter
  def from : String
    "html"
  end

  def to : String
    "pdf"
  end

  def call(input : Bytes, ctx : SSG::Chain::Context) : Bytes
    ("%PDF-fake\n" + String.new(input)).to_slice
  end
end

describe SSG::Chain::Registry do
  registry = SSG::Processors.default_registry.register(FakePdf.new)

  # {filename, base, output name, format, steps in run order}
  cases = [
    {"test.html.j2", "test", "test.html", "html", ["j2"]},
    {"post.md", "post", "post.html", "html", ["md -> html"]},
    {"post.md.j2", "post", "post.html", "html", ["j2", "md -> html"]},
    {"post.html.md", "post", "post.html", "html", ["md -> html"]},
    {"post.html.md.j2", "post", "post.html", "html", ["j2", "md -> html"]},
    {"post.j2.md", "post", "post.html", "html", ["md -> html", "j2"]},
    {"notes.txt.md", "notes", "notes.txt", "txt", ["md -> html", "html -> txt"]},
    {"report.pdf.html.md", "report", "report.pdf", "pdf", ["md -> html", "html -> pdf"]},
    {"report.pdf.md", "report", "report.pdf", "pdf", ["md -> html", "html -> pdf"]},
    {"report.pdf.html.j2", "report", "report.pdf", "pdf", ["j2", "html -> pdf"]},
    {"report.pdf.html", "report", "report.pdf", "pdf", ["html -> pdf"]},
    {"report.txt.pdf.html", "report.txt", "report.txt.pdf", "pdf", ["html -> pdf"]}, # no pdf -> txt
    {"archive.tar.gz", "archive.tar", "archive.tar.gz", "gz", [] of String},
    {"sitemap.xml.j2", "sitemap", "sitemap.xml", "xml", ["j2"]},
    {"style.scss", "style", "style.css", "css", ["scss -> css"]},
    {"style.css.scss", "style", "style.css", "css", ["scss -> css"]},
    {"style.css.scss.j2", "style", "style.css", "css", ["j2", "scss -> css"]},
    {"style.sass", "style", "style.css", "css", ["sass -> css"]},
    {"sitemap.xml", "sitemap", "sitemap.xml", "xml", [] of String},
    {"logo.png", "logo", "logo.png", "png", [] of String},
    {"README", "README", "README", nil, [] of String},
    {"Makefile.j2", "Makefile", "Makefile", nil, ["j2"]},
    {".htaccess.j2", "", ".htaccess", "htaccess", ["j2"]},
    {"my.notes.html.j2", "my.notes", "my.notes.html", "html", ["j2"]},
    {"my.notes.md", "my.notes", "my.notes.html", "html", ["md -> html"]},
    {"index.xml.j2", "index", "index.xml", "xml", ["j2"]},
    {"index.pdf.md", "index", "index.pdf", "pdf", ["md -> html", "html -> pdf"]},
  ]

  cases.each do |name, base, output, format, steps|
    it "resolves #{name} -> #{output} (#{format || "no format"})" do
      r = registry.resolve(name)
      r.base.should eq base
      r.output_name.should eq output
      r.format.should eq format
      r.steps.map(&.describe).should eq steps
      r.passthrough?.should eq steps.empty?
    end
  end

  it "runs steps in order, processors then converters" do
    site = load_fixture("classify")
    env = SSG::TemplateEnv.build(site)
    ctx = SSG::Chain::Context.new(site, env, site.home)

    html = registry.process("# {{ site.title }} {{ L(\"u\", \"t\") }}", registry.resolve("x.md.j2"), ctx)
    String.new(html).should contain %(<a href="u">t</a>)
    html = registry.process("# {{ site.title }}", registry.resolve("x.md.j2"), ctx)
    String.new(html).strip.should eq %(<h1 id="classify">Classify</h1>)

    txt = registry.process("# {{ site.title }}\n\nHi &amp; bye", registry.resolve("x.txt.md.j2"), ctx)
    String.new(txt).should eq "Classify\n\nHi & bye\n"

    pdf = registry.process("<b>x</b>", registry.resolve("x.pdf.html"), ctx)
    String.new(pdf).should start_with "%PDF-fake"
  end
end
