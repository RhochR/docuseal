# frozen_string_literal: true

RSpec.describe EmailHtml do
  let(:account) { create(:account) }
  let(:author) { create(:user, account:) }
  let(:folder) { create(:template_folder, account:) }
  let(:template) { create(:template, account:, author:, folder:) }
  let(:submission) { create(:submission, :with_submitters, template:, created_by_user: author) }
  let(:submitter) { submission.submitters.first }
  let(:attribution) { '<p>---</p><p>Sent using <a href="https://www.docuseal.com/open">DocuSeal</a></p>' }

  def render(html, **)
    Nokogiri::HTML5(described_class.call(html, submitter:, attribution_html: attribution, **))
  end

  it 'keeps the layout of the template, including the style block and inline styles' do
    html = <<~HTML
      <!DOCTYPE html><html><head><style>.box { padding: 12px; color: #333 }</style></head>
      <body style="margin:0"><table width="100%"><tr><td class="box" style="padding: 8px; color: red">Hello</td></tr></table></body></html>
    HTML

    document = render(html)

    expect(document.at_css('style').text).to include('.box { padding: 12px; color: #333 }')
    expect(document.at_css('td')['style']).to eq('padding: 8px; color: red')
    expect(document.at_css('body')['style']).to start_with('margin:0;')
  end

  it 'replaces variables and escapes the values' do
    submitter.update!(name: '<script>alert(1)</script>Bob')

    document = render('<html><body><p>Hi {{submitter.name}}, please sign {{template.name}}</p></body></html>')

    expect(document.at_css('p').text).to eq("Hi <script>alert(1)</script>Bob, please sign #{template.name}")
    expect(document.css('script')).to be_empty
  end

  it 'removes scripts, frames, forms and event handlers' do
    html = <<~HTML
      <html><body onload="steal()">
        <script>alert(1)</script><iframe src="https://example.com"></iframe>
        <form action="https://example.com"><input name="x"><button>go</button></form>
        <object data="x"></object><svg onload="x()"></svg>
        <p onclick="steal()" class="ok">Text</p>
      </body></html>
    HTML

    document = render(html)

    expect(document.css('script, iframe, form, input, button, object, svg')).to be_empty
    expect(document.at_css('body')['onload']).to be_nil
    expect(document.at_css('p.ok')['onclick']).to be_nil
    expect(document.at_css('p.ok').text).to eq('Text')
  end

  it 'only allows safe link and image addresses' do
    html = <<~HTML
      <html><body>
        <a id="js" href="javascript:alert(1)">x</a>
        <a id="js2" href=" JaVa&#x0A;script:alert(1)">x</a>
        <a id="data" href="data:text/html;base64,PHNjcmlwdD4=">x</a>
        <a id="ok" href="https://example.com/a?b=1">x</a>
        <a id="mail" href="mailto:me@example.com">x</a>
        <img id="img" src="https://example.com/logo.png" alt="Logo">
        <img id="inline" src="data:image/png;base64,iVBORw0KGgo=" alt="">
        <img id="bad" src="javascript:alert(1)">
      </body></html>
    HTML

    document = render(html)

    %w[js js2 data].each { |id| expect(document.at_css("##{id}")['href']).to be_nil }
    expect(document.at_css('#ok')['href']).to eq('https://example.com/a?b=1')
    expect(document.at_css('#mail')['href']).to eq('mailto:me@example.com')
    expect(document.at_css('#img')['src']).to eq('https://example.com/logo.png')
    expect(document.at_css('#inline')['src']).to start_with('data:image/png')
    expect(document.at_css('#bad')['src']).to be_nil
  end

  it 'drops dangerous CSS' do
    html = <<~HTML
      <html><head><style>@import url(https://evil.example/x.css); p { color: red }</style></head>
      <body><p style="background: url(https://evil.example/track.gif); width: expression(alert(1)); color: blue">x</p>
      <div style="background-image: url('https://evil.example/a.png'); padding: 4px">y</div></body></html>
    HTML

    document = render(html)

    expect(document.at_css('style')&.text.to_s).not_to include('evil.example')
    expect(document.at_css('p')['style']).to eq('background: none; color: blue')
    expect(document.at_css('div')['style']).to eq('background-image: none; padding: 4px')
  end

  it 'always appends the attribution once, with styles a template can not override' do
    html = '<html><head><style>[data-attribution], p { display: none !important }</style></head>' \
           '<body><p>Hi</p></body></html>'

    document = render(html)
    attribution_node = document.at_css('[data-attribution]')

    expect(document.css('[data-attribution]').size).to eq(1)
    expect(attribution_node.text).to include('Sent using DocuSeal')
    expect(attribution_node['style']).to include('display: block !important')
    expect(document.at_css('body').element_children.last).to eq(attribution_node)
  end

  it 'adds the fallback link before the attribution' do
    document = render('<html><body><p>Hi</p></body></html>', link_url: 'https://example.com/s/abc?t=1&x=2')

    link = document.at_css('body > p:nth-of-type(2) a')

    expect(link['href']).to eq('https://example.com/s/abc?t=1&x=2')
    expect(document.at_css('body').element_children.map(&:name)).to eq(%w[p p div])
  end

  it 'wraps fragments into a document' do
    document = render('<p>Hi</p>')

    expect(document.at_css('html > body > p').text).to eq('Hi')
  end

  describe 'tags that are not allowed' do
    it 'cleans the content of an unknown wrapper element' do
      html = '<html><body><article><script>alert(1)</script><a href="javascript:alert(1)" onclick="x()">x</a>' \
             '<img src="x" onerror="alert(1)"><form action="https://evil.example"><input name="p"></form></article>' \
             '<foo><svg><script>alert(1)</script></svg><base href="https://evil.example/"></foo></body></html>'

      document = render(html)

      expect(document.css('script, form, input, svg, base')).to be_empty
      expect(document.at_css('a')['href']).to be_nil
      expect(document.at_css('a')['onclick']).to be_nil
      expect(document.at_css('img')['onerror']).to be_nil
      expect(document.at_css('a').text).to eq('x')
    end

    it 'cleans deeply nested wrappers' do
      html = "<html><body>#{'<section>' * 20}<a href=\"javascript:alert(1)\">x</a>#{'</section>' * 20}</body></html>"

      expect(render(html).at_css('a')['href']).to be_nil
    end
  end

  describe 'comments' do
    it 'removes comments, including conditional comments for Outlook' do
      html = '<html><body><!--[if mso]><div style="display:none"><a href="javascript:alert(1)">x</a><![endif]-->' \
             '<p>Hi</p><!-- note --></body></html>'

      result = described_class.call(html, submitter:, attribution_html: attribution)

      expect(result).not_to include('<!--')
      expect(result).not_to include('javascript:')
      expect(result).to include('Hi')
    end
  end

  describe 'attribution' do
    it 'can not be hidden with a style block, on the body or on its container' do
      html = '<html><head><style>[data-attribution], [data-attribution] * { position: absolute !important; ' \
             'left: -9999px !important; visibility: hidden !important; font-size: 1px !important } ' \
             'body { max-height: 0 !important; overflow: hidden !important; display: none !important }</style></head>' \
             '<body style="height: 0; overflow: hidden"><p>Hi</p></body></html>'

      document = render(html)
      attribution_node = document.at_css('[data-attribution]')

      expect(attribution_node['style']).to include('position: static !important')
      expect(attribution_node['style']).to include('visibility: visible !important')
      expect(attribution_node.css('*').pluck('style')).to all(include('visibility: visible !important'))
      expect(document.at_css('body')['style']).to include('overflow: visible !important')
      expect(document.at_css('body')['style']).to include('display: block !important')
      expect(document.at_css('html')['style']).to include('max-height: none !important')
    end

    it 'is added even when the template has no body' do
      document = render('<html><frameset><frame src="https://example.com"></frameset></html>')

      expect(document.css('frameset, frame')).to be_empty
      expect(document.at_css('body [data-attribution]')).to be_present
    end
  end

  describe '.default_template' do
    it 'is an HTML document that links to the given variable' do
      html = described_class.default_template(variables: %w[template.name submitter.link account.name])

      expect(EmailMessages.html_body?(html)).to be(true)
      expect(html).to include('href="{{submitter.link}}"')
    end

    it 'comes through the cleaning unchanged in structure' do
      html = described_class.default_template(variables: %w[submission.link])
      document = render(html)

      expect(document.at_css("a[href*='/submissions/']")).to be_present
      expect(document.css('table').size).to eq(2)
    end
  end
end
