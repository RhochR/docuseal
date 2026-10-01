# frozen_string_literal: true

# Reads the CSV or XLSX file uploaded for a bulk send into [[sheet_name, [[header, ...], [cell, ...], ...]], ...].
# Every cell is a String or nil, dates are ISO 8601 strings.
module Spreadsheets
  Error = Class.new(StandardError)

  MAX_FILE_SIZE = 5.megabytes
  MAX_UNCOMPRESSED_SIZE = 100.megabytes
  MAX_ROWS = ENV.fetch('BULK_SEND_MAX_ROWS', '1000').to_i
  MAX_COLUMNS = 100
  CSV_SEPARATORS = [',', ';', "\t"].freeze
  BOM = '﻿'

  module_function

  def parse(file, filename:)
    size = file.size

    raise Error, I18n.t(:spreadsheet_too_large, size: MAX_FILE_SIZE / 1.megabyte) if size > MAX_FILE_SIZE

    sheets =
      case File.extname(filename.to_s).downcase
      when '.csv' then [[File.basename(filename.to_s, '.*'), parse_csv(file.read)]]
      when '.xlsx' then parse_xlsx(file)
      else raise Error, I18n.t(:spreadsheet_unsupported_file)
      end

    sheets = sheets.select { |_, rows| rows.size > 1 }.presence

    raise Error, I18n.t(:spreadsheet_is_empty) unless sheets

    sheets.each { |sheet| validate_size!(sheet.last) }

    sheets
  end

  def parse_csv(data)
    text = decode(data)
    separator = detect_separator(text)

    rows = CSV.parse(text, col_sep: separator, liberal_parsing: true).map do |row|
      row.first(MAX_COLUMNS + 1).map { |value| normalize_value(value) }
    end

    finalize_rows(rows)
  rescue CSV::MalformedCSVError
    raise Error, I18n.t(:spreadsheet_could_not_be_read)
  end

  def parse_xlsx(file)
    validate_archive!(file)

    workbook = Roo::Excelx.new(file.path, extension: :xlsx, only_visible_sheets: true)

    workbook.sheets.map do |name|
      rows = []

      workbook.sheet(name).each_row_streaming(pad_cells: true, max_rows: MAX_ROWS + 2) do |row|
        rows << row.first(MAX_COLUMNS + 1).map { |cell| normalize_value(cell&.value) }
      end

      [name, finalize_rows(rows)]
    end
  rescue Zip::Error, Roo::HeaderRowNotFoundError, Nokogiri::XML::SyntaxError, ArgumentError, IOError, RangeError
    raise Error, I18n.t(:spreadsheet_could_not_be_read)
  end

  # An XLSX is a ZIP archive, refuse archives that would unpack into something huge.
  def validate_archive!(file)
    total = 0

    Zip::File.open(file.path) do |zip|
      zip.each do |entry|
        total += entry.size

        raise Error, I18n.t(:spreadsheet_could_not_be_read) if total > MAX_UNCOMPRESSED_SIZE
      end
    end
  end

  def decode(data)
    text = data.to_s.b
    text = text.delete_prefix(BOM.b) if text.start_with?(BOM.b)
    text = text.dup.force_encoding(Encoding::UTF_8)

    if text.valid_encoding?
      text
    else
      text.dup.force_encoding(Encoding::Windows_1252).encode(Encoding::UTF_8,
                                                             undef: :replace)
    end
  end

  def detect_separator(text)
    header = text.lines.first.to_s

    CSV_SEPARATORS.max_by { |separator| header.count(separator) }
  end

  def normalize_value(value)
    case value
    when nil then nil
    when true, false, Integer then value.to_s
    when Float, BigDecimal then format_number(value)
    when DateTime, Time then format_time(value)
    when Date then value.iso8601
    else value.to_s.gsub(/[[:space:]]+/, ' ').strip.presence
    end
  end

  def format_number(value)
    return value.to_s unless value.to_f.finite?

    BigDecimal(value.to_s).to_s('F').delete_suffix('.0')
  end

  def format_time(value)
    value.hour.zero? && value.min.zero? && value.sec.zero? ? value.to_date.iso8601 : value.iso8601
  end

  # Drops empty rows and trailing empty columns, so the header row and the data rows line up.
  def finalize_rows(rows)
    rows = rows.reject { |row| row.all?(&:nil?) }

    width = rows.map { |row| row.rindex { |value| !value.nil? } || -1 }.max.to_i + 1

    rows.map { |row| row.first(width).then { |cells| cells + Array.new(width - cells.size) } }
  end

  def validate_size!(rows)
    raise Error, I18n.t(:spreadsheet_too_many_rows, count: MAX_ROWS) if rows.size - 1 > MAX_ROWS
    raise Error, I18n.t(:spreadsheet_too_many_columns, count: MAX_COLUMNS) if rows.first.size > MAX_COLUMNS
  end
end
