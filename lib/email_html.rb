# frozen_string_literal: true

# Prepares a custom HTML email: fills in the variables, removes everything that could be dangerous in a mail
# client and always appends the attribution, so it can not be edited away in a template.
module EmailHtml
  DANGEROUS_TAGS = %w[
    script iframe frame frameset object embed applet form input button select textarea option link base svg math
    noscript template audio video source track canvas dialog
  ].freeze

  ALLOWED_TAGS = %w[
    html head body title style meta a abbr address b big blockquote br caption center cite code col colgroup dd div dl
    dt em font h1 h2 h3 h4 h5 h6 hr i img li ol p pre s small span strike strong sub sup table tbody td tfoot th thead
    tr u ul
  ].freeze

  GLOBAL_ATTRIBUTES = %w[
    style class id dir lang title align valign width height bgcolor color background border cellpadding cellspacing
    colspan rowspan role nowrap
  ].freeze

  TAG_ATTRIBUTES = {
    'a' => %w[href target rel name],
    'img' => %w[src alt],
    'font' => %w[face size],
    'meta' => %w[charset name content],
    'ol' => %w[start type],
    'ul' => %w[type]
  }.freeze

  URL_ATTRIBUTES = %w[href src background].freeze
  LINK_PROTOCOLS = %w[http https mailto tel].freeze
  IMAGE_PROTOCOLS = %w[http https cid].freeze
  DATA_IMAGE_REGEXP = %r{\Adata:image/(?:png|jpe?g|gif|webp);base64,[A-Za-z0-9+/=\s]+\z}i
  DANGEROUS_CSS_REGEXP = %r{expression\s*\(|javascript:|vbscript:|behavior\s*:|binding\s*:|@import|\\|/\*|<|>}i
  CSS_URL_REGEXP = /url\s*\([^)]*\)/i

  ATTRIBUTION_STYLE = 'display: block !important; visibility: visible !important; opacity: 1 !important; ' \
                      'height: auto !important; max-height: none !important; overflow: visible !important; ' \
                      'font-size: 13px !important; line-height: 1.4 !important; margin: 24px 0 0 !important; ' \
                      'text-indent: 0 !important; color: #6b7280 !important;'

  LINK_VARIABLES = %w[submitter.link submission.link documents.link].freeze

  DEFAULT_BUTTON = '<p style="margin: 24px 0;"><a href="{{__LINK__}}" style="display: inline-block; ' \
                   'padding: 12px 24px; border-radius: 6px; background-color: #1f2937; color: #ffffff; ' \
                   'text-decoration: none;">{{template.name}}</a></p>'
  DEFAULT_TEXT = '<p style="margin: 24px 0;"><strong>{{template.name}}</strong></p>'

  DEFAULT_TEMPLATE = <<~HTML
    <!DOCTYPE html>
    <html>
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
      </head>
      <body style="margin: 0; padding: 24px; background-color: #f5f5f5; font-family: Arial, Helvetica, sans-serif; color: #1f2937;">
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0">
          <tr>
            <td align="center">
              <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width: 560px; background-color: #ffffff; border-radius: 8px;">
                <tr>
                  <td style="padding: 32px; font-size: 16px; line-height: 1.5;">
                    <p style="margin: 0 0 16px;">__GREETING__,</p>
                    __BUTTON__
                    <p style="margin: 0;">__THANKS__,<br>{{account.name}}</p>
                  </td>
                </tr>
              </table>
            </td>
          </tr>
        </table>
      </body>
    </html>
  HTML

  module_function

  # Starting point shown when someone switches an email template from text to HTML.
  def default_template(variables: [])
    link_variable = (LINK_VARIABLES & variables.to_a).first
    button = link_variable ? DEFAULT_BUTTON.sub('__LINK__') { link_variable } : DEFAULT_TEXT

    DEFAULT_TEMPLATE.sub('__GREETING__') { ERB::Util.html_escape(I18n.t(:hi_there)) }
                    .sub('__BUTTON__') { button }
                    .sub('__THANKS__') { ERB::Util.html_escape(I18n.t(:thanks)) }
  end

  def call(html, submitter:, sig: nil, link_url: nil, attribution_html: nil)
    html = ReplaceEmailVariables.call(html, submitter:, sig:, html_escape: true)

    document = sanitize(html)
    body = document.at_css('body')

    body.add_child(build_link_paragraph(document, link_url)) if link_url.present?
    body.add_child(build_attribution(document, attribution_html)) if attribution_html.present?

    document.to_html
  end

  def sanitize(html)
    document = Loofah.html5_document(html)

    document.scrub!(Loofah::Scrubber.new { |node| scrub_node(node) if node.element? })

    document
  end

  def scrub_node(node)
    name = node.name.downcase

    if DANGEROUS_TAGS.include?(name)
      node.remove
    elsif ALLOWED_TAGS.exclude?(name)
      node.before(node.children)
      node.remove
    elsif name == 'style'
      node.content = scrub_stylesheet(node.content)
    else
      scrub_attributes(node, name)
    end

    nil
  end

  def scrub_attributes(node, tag_name)
    allowed = GLOBAL_ATTRIBUTES + TAG_ATTRIBUTES.fetch(tag_name, [])

    node.attribute_nodes.each do |attribute|
      name = attribute.name.downcase

      if allowed.exclude?(name) || (URL_ATTRIBUTES.include?(name) && !safe_url?(attribute.value, tag_name))
        attribute.remove
      elsif name == 'style'
        attribute.value = scrub_declarations(attribute.value)
      end
    end

    node.remove if tag_name == 'meta' && node['charset'].blank? && node['name'].blank?
  end

  def safe_url?(value, tag_name)
    value = value.to_s.gsub(/[[:space:][:cntrl:]]/, '')

    return true if value.start_with?('#') || (value.start_with?('/') && !value.start_with?('//'))
    return true if tag_name == 'img' && value.match?(DATA_IMAGE_REGEXP)

    protocol = value[/\A([a-z][a-z0-9+.-]*):/i, 1]&.downcase

    return false if protocol.nil? && value.include?(':')

    allowed = tag_name == 'img' ? IMAGE_PROTOCOLS : LINK_PROTOCOLS

    protocol.nil? || allowed.include?(protocol)
  end

  def scrub_declarations(css)
    css.to_s.split(';').filter_map do |declaration|
      next if declaration.blank? || declaration.match?(DANGEROUS_CSS_REGEXP)

      declaration.gsub(CSS_URL_REGEXP, 'none').strip
    end.join('; ')
  end

  def scrub_stylesheet(css)
    return '' if css.match?(DANGEROUS_CSS_REGEXP)

    css.gsub(CSS_URL_REGEXP, 'none')
  end

  def build_link_paragraph(document, url)
    paragraph = Nokogiri::XML::Node.new('p', document)
    link = Nokogiri::XML::Node.new('a', document)

    link['href'] = url
    link.content = url
    paragraph.add_child(link)

    paragraph
  end

  def build_attribution(document, attribution_html)
    container = Nokogiri::XML::Node.new('div', document)

    container['style'] = ATTRIBUTION_STYLE
    container['data-attribution'] = 'true'
    container.inner_html = attribution_html

    container.css('p').each do |paragraph|
      paragraph['style'] = 'display: block !important; margin: 0 0 4px !important;'
    end

    container
  end
end
