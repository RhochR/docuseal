# frozen_string_literal: true

RSpec.describe Spreadsheets do
  def tempfile(content, extension)
    Tempfile.new(['sheet', extension], binmode: true).tap do |file|
      file.write(content)
      file.rewind
    end
  end

  def build_xlsx(sheets)
    io = StringIO.new

    Xlsxtream::Workbook.open(io) do |workbook|
      sheets.each do |name, rows|
        workbook.write_worksheet(name) { |sheet| rows.each { |row| sheet << row } }
      end
    end

    io.string
  end

  def parse(content, filename)
    file = tempfile(content, File.extname(filename))

    described_class.parse(file, filename:)
  end

  describe 'CSV' do
    it 'reads a comma separated file' do
      expect(parse("Name,Email\nJohn,john@example.com\nAnna,anna@example.com\n", 'people.csv'))
        .to eq([['people', [%w[Name Email], %w[John john@example.com], %w[Anna anna@example.com]]]])
    end

    it 'detects semicolons and tabs' do
      expect(parse("Name;Email\nJohn;john@example.com\n",
                   'a.csv').first.last).to eq([%w[Name Email], %w[John john@example.com]])
      expect(parse("Name\tEmail\nJohn\tjohn@example.com\n",
                   'a.csv').first.last).to eq([%w[Name Email], %w[John john@example.com]])
    end

    it 'handles quoted values with separators and line breaks' do
      rows = parse(%(Name,Note\n"Doe, John","line 1\nline 2"\n), 'a.csv').first.last

      expect(rows.last).to eq(['Doe, John', 'line 1 line 2'])
    end

    it 'removes a byte order mark and reads Windows-1252 files' do
      utf8 = "﻿Name,City\nJörg,München\n"
      windows = "Name,City\nJ\xF6rg,M\xFCnchen\n".b

      expect(parse(utf8, 'a.csv').first.last.first).to eq(%w[Name City])
      expect(parse(windows, 'a.csv').first.last.last).to eq(%w[Jörg München])
    end

    it 'skips empty rows and trailing empty columns and turns blanks into nil' do
      rows = parse("Name,Email,,\nJohn,,,\n,,,\n\nAnna,a@example.com,,\n", 'a.csv').first.last

      expect(rows).to eq([%w[Name Email], ['John', nil], ['Anna', 'a@example.com']])
    end

    it 'rejects files without data' do
      expect { parse("Name,Email\n", 'a.csv') }.to raise_error(described_class::Error, 'The spreadsheet is empty.')
    end

    it 'rejects files with too many rows' do
      csv = "Email\n#{Array.new(described_class::MAX_ROWS + 1) { |i| "u#{i}@example.com" }.join("\n")}\n"

      expect { parse(csv, 'a.csv') }.to raise_error(described_class::Error, /too many rows/)
    end

    it 'rejects files that are too large' do
      csv = "Email\n#{'a' * described_class::MAX_FILE_SIZE}"

      expect { parse(csv, 'a.csv') }.to raise_error(described_class::Error, /too large/)
    end
  end

  describe 'XLSX' do
    it 'reads every visible worksheet' do
      xlsx = build_xlsx('First' => [%w[Name Email], %w[John john@example.com]],
                        'Second' => [%w[City], %w[Berlin]])

      expect(parse(xlsx, 'a.xlsx')).to eq([['First', [%w[Name Email], %w[John john@example.com]]],
                                           ['Second', [%w[City], %w[Berlin]]]])
    end

    it 'turns numbers and dates into clean strings' do
      xlsx = build_xlsx('Data' => [%w[Amount Count Rate Due], [12.5, 3, 4_915_112_345_678.0, Date.new(2026, 2, 3)]])

      expect(parse(xlsx, 'a.xlsx').first.last.last).to eq(['12.5', '3', '4915112345678', '2026-02-03'])
    end

    it 'skips empty worksheets' do
      xlsx = build_xlsx('Empty' => [], 'Data' => [%w[Email], %w[a@example.com]])

      expect(parse(xlsx, 'a.xlsx').map(&:first)).to eq(['Data'])
    end

    it 'rejects a file that is not a spreadsheet' do
      expect { parse('not a zip file', 'a.xlsx') }.to raise_error(described_class::Error, /could not be read/)
    end
  end

  it 'rejects other file types' do
    expect { parse('x', 'a.xls') }.to raise_error(described_class::Error, /Unsupported file/)
    expect { parse('x', 'a.pdf') }.to raise_error(described_class::Error, /Unsupported file/)
  end
end
