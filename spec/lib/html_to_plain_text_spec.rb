# frozen_string_literal: true

RSpec.describe HtmlToPlainText do
  it 'leaves out styles, the head and the title of a complete document' do
    html = '<html><head><title>Subject</title><style>p { color: red }</style></head><body><p>Hello</p></body></html>'

    expect(described_class.call(html)).to eq('Hello')
  end

  it 'puts table rows on separate lines' do
    html = '<table><tr><td>Name</td><td>Bob</td></tr><tr><td>Role</td><td>Signer</td></tr></table>'

    expect(described_class.call(html)).to eq("Name  Bob\nRole  Signer")
  end

  it 'keeps links and paragraphs' do
    html = '<p>Sign <a href="https://example.com/s/1">here</a></p><p>Thanks</p>'

    expect(described_class.call(html)).to eq("Sign here ( https://example.com/s/1 )\n\nThanks")
  end
end
