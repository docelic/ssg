require "./spec_helper"

describe SSG::HugoConvert do
  it "converts single shortcodes with quoted, bare and named arguments" do
    SSG::HugoConvert.convert(%(a {{< L "https://x" "t" >}} b {{<L https://y Y>}} c {{% fig src="a.png" alt='it"s' %}}))
      .should eq %(a {{ L("https://x", "t") }} b {{ L("https://y", "Y") }} c {{ fig(src="a.png", alt="it\\"s") }})
  end

  it "converts paired shortcodes into call blocks" do
    SSG::HugoConvert.convert("x {{< bq cite=\"me\" >}}\nline\n{{< /bq >}} y")
      .should eq "x {% call bq(cite=\"me\") %}\nline\n{% endcall %} y"
  end

  it "leaves text without shortcodes alone and rejects stray closers" do
    SSG::HugoConvert.convert("plain {{ jinja }}").should eq "plain {{ jinja }}"
    expect_raises(SSG::Error, /unmatched/) { SSG::HugoConvert.convert("{{< /bq >}}") }
  end

  it "replaces the file when writing" do
    dir = File.expand_path("out/convert", __DIR__)
    FileUtils.rm_rf(dir)
    Dir.mkdir_p(dir)
    path = File.join(dir, "post.md")
    File.write(path, "x {{< L \"u\" >}}")
    SSG::HugoConvert.run([path], write: true)
    File.exists?(path).should be_false
    File.read(path + ".j2").should eq %(x {{ L("u") }})
  end

  it "handles the whole unix-history article" do
    source = File.read(File.join(EXAMPLE, "hugo-src", "unix-history.md"))
    converted = SSG::HugoConvert.convert(source)
    converted.scan(/\{\{[<%]/).size.should eq 0
    converted.scan(/\{\{ L\(/).size.should eq 545
    converted.scan(/\{\{ R\(/).size.should eq 2
  end
end
