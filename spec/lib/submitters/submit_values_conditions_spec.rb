# frozen_string_literal: true

RSpec.describe Submitters::SubmitValues do
  describe '.check_field_conditions' do
    let(:source) { { 'uuid' => 'source', 'type' => 'text', 'submitter_uuid' => 'sub' } }

    let(:middle) do
      {
        'uuid' => 'middle', 'type' => 'checkbox', 'submitter_uuid' => 'sub',
        'conditions' => [{ 'field_uuid' => 'source', 'action' => 'not_empty' }]
      }
    end

    let(:target) do
      {
        'uuid' => 'target', 'type' => 'text', 'submitter_uuid' => 'sub',
        'conditions' => [{ 'field_uuid' => 'middle', 'action' => 'checked' }]
      }
    end

    let(:index) { [source, middle, target].index_by { |f| f['uuid'] } }

    it 'hides a field when the field it depends on is hidden itself' do
      values = { 'middle' => true }

      expect(described_class.check_field_conditions(values, middle, index)).to be(false)
      expect(described_class.check_field_conditions(values, target, index)).to be(false)
    end

    it 'shows a field when the whole chain of conditions is met' do
      values = { 'source' => 'text', 'middle' => true }

      expect(described_class.check_field_conditions(values, middle, index)).to be(true)
      expect(described_class.check_field_conditions(values, target, index)).to be(true)
    end

    it 'keeps negative conditions on hidden fields working' do
      field = { 'uuid' => 'other', 'conditions' => [{ 'field_uuid' => 'middle', 'action' => 'unchecked' }] }

      expect(described_class.check_field_conditions({}, field, index.merge('other' => field))).to be(true)
    end

    it 'does not loop forever on circular conditions' do
      first = { 'uuid' => 'first', 'conditions' => [{ 'field_uuid' => 'second', 'action' => 'not_empty' }] }
      second = { 'uuid' => 'second', 'conditions' => [{ 'field_uuid' => 'first', 'action' => 'not_empty' }] }
      circular_index = { 'first' => first, 'second' => second }
      values = { 'first' => 'a', 'second' => 'b' }

      expect { described_class.check_field_conditions(values, first, circular_index) }.not_to raise_error
    end

    it 'checks long chains of conditions in linear time' do
      fields = Array.new(40) do |i|
        { 'uuid' => "f#{i}", 'type' => 'text',
          'conditions' => [{ 'field_uuid' => "f#{i + 1}", 'action' => 'not_empty' },
                           { 'field_uuid' => "f#{i + 1}", 'action' => 'not_empty', 'operation' => 'or' }] }
      end

      chain_index = fields.index_by { |f| f['uuid'] }
      values = { 'f40' => 'x' }

      Timeout.timeout(5) do
        expect(described_class.check_field_conditions(values, fields.first, chain_index)).to be(false)
      end
    end
  end
end
