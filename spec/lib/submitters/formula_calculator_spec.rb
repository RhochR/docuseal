# frozen_string_literal: true

RSpec.describe Submitters::FormulaCalculator do
  let(:account) { Struct.new(:timezone).new('UTC') }
  let(:submission_class) { Struct.new(:fields_uuid_index, :account) }

  let(:fields) do
    [
      { 'uuid' => 'a', 'type' => 'number' },
      { 'uuid' => 'b', 'type' => 'number' },
      { 'uuid' => 'start', 'type' => 'date' },
      { 'uuid' => 'finish', 'type' => 'date' },
      { 'uuid' => 'name', 'type' => 'text' }
    ]
  end

  let(:submission) { submission_class.new(fields.index_by { |f| f['uuid'] }, account) }

  describe '.calculate' do
    {
      '2 + 3 * 4' => 14,
      '(2 + 3) * 4' => 20,
      'round(10 / 3, 2)' => 3.33,
      'round(2.5)' => 3,
      'round(-2.5)' => -2,
      'roundup(2.1)' => 3,
      'rounddown(-2.9)' => -3,
      'roundup(-2.1)' => -2,
      '50%' => 0.5,
      'abs(-4) + max(1, 7, 3)' => 11,
      'if(3 > 2, 10, 20)' => 10,
      'pow(2, 10) + floor(1.9) + ceil(1.1)' => 1027,
      'sum(1, 2, 3) + avg(2, 4)' => 9,
      '{{a}} * {{b}}' => 12,
      '{{a}} - {{b}}' => -1
    }.each do |formula, expected|
      it "evaluates #{formula} to #{expected}" do
        result = described_class.calculate(formula, { 'a' => '3', 'b' => '4' }, submission)

        expect(result).to eq(expected)
        expect(result).to be_a(expected.is_a?(Integer) ? Integer : Float)
      end
    end

    it 'treats empty and non numeric values as zero' do
      expect(described_class.calculate('{{a}} + {{b}}', { 'a' => '', 'b' => 'oops' }, submission)).to eq(0)
    end

    it 'handles negative and decimal values' do
      expect(described_class.calculate('{{a}} * {{b}}', { 'a' => '-2.5', 'b' => '4' }, submission)).to eq(-10)
    end

    it 'returns nil when dividing by zero' do
      expect(described_class.calculate('{{a}} / 0', { 'a' => '3' }, submission)).to be_nil
    end

    it 'returns nil for an invalid expression' do
      expect(described_class.calculate('1 +', {}, submission)).to be_nil
    end

    it 'can not be tricked into evaluating submitted text' do
      result = described_class.calculate('{{a}} + 1', { 'a' => '1) + (100' }, submission)

      expect(result).to eq(1)
    end
  end

  describe '.calculate_date' do
    it 'returns an ISO date for a date formula' do
      result = described_class.calculate_date('{{start}} + 30', { 'start' => '2026-01-15' }, submission)

      expect(result).to eq('2026-02-14')
    end

    it 'returns nil for an empty date' do
      expect(described_class.calculate_date('{{start}} + 30', {}, submission)).to be_nil
    end
  end

  describe 'date functions' do
    let(:values) { { 'start' => '2020-03-15', 'finish' => '2026-03-14' } }

    it 'counts days, months and complete years with datedif' do
      expect(described_class.calculate('datedif({{start}}, {{finish}}, "d")', values, submission)).to eq(2190)
      expect(described_class.calculate('datedif({{start}}, {{finish}}, "m")', values, submission)).to eq(71)
      expect(described_class.calculate('datedif({{start}}, {{finish}}, "y")', values, submission)).to eq(5)
    end

    it 'returns nil for datedif with an empty date' do
      expect(described_class.calculate('datedif({{start}}, {{finish}}, "y")', { 'start' => '' }, submission)).to be_nil
    end

    it 'supports today() in the account time zone' do
      travel_to = Time.utc(2026, 6, 1, 23, 30)

      allow(Time).to receive(:current).and_return(travel_to)
      account.timezone = 'Tokyo'

      today = described_class.calculate_date('today()', {}, submission)

      expect(today).to eq('2026-06-02')
    end

    it 'uses today() for the {{date}} placeholder' do
      allow(Time).to receive(:current).and_return(Time.utc(2026, 6, 1, 12))

      result = described_class.calculate_date('{{start}} + 1', { 'start' => '{{date}}' }, submission)

      expect(result).to eq('2026-06-02')
    end
  end

  describe '.eval_text' do
    it 'interpolates field values' do
      expect(described_class.eval_text('Hi {{name}}, total {{a}}', { 'name' => 'Ann', 'a' => '5' }, submission))
        .to eq('Hi Ann, total 5')
    end

    it 'joins multiple values' do
      expect(described_class.eval_text('{{name}}', { 'name' => %w[x y] }, submission)).to eq('x, y')
    end

    it 'evaluates formulas of referenced fields' do
      fields << { 'uuid' => 'sum', 'type' => 'number', 'preferences' => { 'formula' => '{{a}} + {{b}}' } }
      submission.fields_uuid_index = fields.index_by { |f| f['uuid'] }

      expect(described_class.eval_text('Sum: {{sum}}', { 'a' => '1', 'b' => '2' }, submission)).to eq('Sum: 3')
    end
  end

  describe 'protection against expensive input' do
    def within_seconds(seconds, &)
      Timeout.timeout(seconds, &)
    end

    it 'does not hang on huge exponents' do
      within_seconds(5) do
        expect(described_class.calculate('9 ^ 999999999', {}, submission)).to be_nil
        expect(described_class.calculate('(1.0000001) ^ (99999999)', {}, submission)).to be_within(0.01).of(22_026.45)
        expect(described_class.calculate('{{a}} ^ {{b}}', { 'a' => '9.0', 'b' => '999999999.0' }, submission)).to be_nil
      end
    end

    it 'still calculates normal powers' do
      expect(described_class.calculate('2 ^ 10', {}, submission)).to eq(1024)
      expect(described_class.calculate('{{a}} ^ 2', { 'a' => '1.5' }, submission)).to eq(2.25)
    end

    it 'limits bit shifts' do
      within_seconds(5) do
        expect(described_class.calculate('1 << 999999999', {}, submission)).to be_nil
      end

      expect(described_class.calculate('1 << 3', {}, submission)).to eq(8)
    end

    it 'treats very long numbers as zero' do
      expect(described_class.calculate('{{a}} + 1', { 'a' => "1#{'0' * 40}" }, submission)).to eq(1)
    end

    it 'does not blow up for text formulas that reference themselves' do
      reference = '{{loop}}' * 10
      fields << { 'uuid' => 'loop', 'type' => 'text', 'preferences' => { 'formula' => reference } }
      submission.fields_uuid_index = fields.index_by { |f| f['uuid'] }

      within_seconds(5) do
        expect(described_class.eval_text("x#{reference}", {}, submission)).to eq('x')
      end
    end

    it 'limits the work for text formulas that fan out' do
      fields << { 'uuid' => 'a1', 'type' => 'text', 'preferences' => { 'formula' => '{{a2}}{{a2}}{{a2}}{{a2}}' } }
      fields << { 'uuid' => 'a2', 'type' => 'text', 'preferences' => { 'formula' => '{{a3}}{{a3}}{{a3}}{{a3}}' } }
      fields << { 'uuid' => 'a3', 'type' => 'text', 'preferences' => { 'formula' => '{{a4}}{{a4}}{{a4}}{{a4}}' } }
      fields << { 'uuid' => 'a4', 'type' => 'text', 'preferences' => { 'formula' => '{{a5}}{{a5}}{{a5}}{{a5}}' } }
      fields << { 'uuid' => 'a5', 'type' => 'text', 'preferences' => { 'formula' => '{{a6}}{{a6}}{{a6}}{{a6}}' } }
      fields << { 'uuid' => 'a6', 'type' => 'text', 'preferences' => { 'formula' => 'x' } }
      submission.fields_uuid_index = fields.index_by { |f| f['uuid'] }

      within_seconds(5) { described_class.eval_text('{{a1}}', {}, submission) }
    end
  end
end
