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
    expect(document.at_css('body')['style']).to eq('margin:0')
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
end
