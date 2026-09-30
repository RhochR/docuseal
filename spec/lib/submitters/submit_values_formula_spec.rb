# frozen_string_literal: true

RSpec.describe Submitters::SubmitValues do
  describe '.build_formula_values' do
    let(:account) { create(:account) }
    let(:author) { create(:user, account:) }
    let(:folder) { create(:template_folder, account:) }
    let(:template) { create(:template, account:, author:, folder:) }
    let(:submitter_uuid) { template.submitters.first['uuid'] }

    let(:fields) do
      [
        { 'uuid' => 'price', 'name' => 'Price', 'type' => 'number', 'submitter_uuid' => submitter_uuid },
        { 'uuid' => 'qty', 'name' => 'Qty', 'type' => 'number', 'submitter_uuid' => submitter_uuid },
        { 'uuid' => 'total', 'name' => 'Total', 'type' => 'number', 'submitter_uuid' => submitter_uuid,
          'readonly' => true, 'preferences' => { 'formula' => '{{price}} * {{qty}}' } },
        { 'uuid' => 'with_tax', 'name' => 'With tax', 'type' => 'number', 'submitter_uuid' => submitter_uuid,
          'readonly' => true, 'preferences' => { 'formula' => 'round({{total}} * 1.2, 2)' } },
        { 'uuid' => 'due', 'name' => 'Due', 'type' => 'date', 'submitter_uuid' => submitter_uuid,
          'readonly' => true, 'preferences' => { 'formula' => '{{start}} + 14' } },
        { 'uuid' => 'start', 'name' => 'Start', 'type' => 'date', 'submitter_uuid' => submitter_uuid },
        { 'uuid' => 'summary', 'name' => 'Summary', 'type' => 'text', 'submitter_uuid' => submitter_uuid,
          'readonly' => true, 'preferences' => { 'formula' => '{{qty}} x {{price}} = {{total}}' } }
      ]
    end

    let(:submission) do
      template.update!(fields:)

      create(:submission, :with_submitters, template:, created_by_user: author)
    end

    let(:submitter) { submission.submitters.first }

    it 'computes number, nested, date and text formulas' do
      submitter.values = { 'price' => '10', 'qty' => '3', 'start' => '2026-01-01' }

      expect(described_class.build_formula_values(submitter)).to eq(
        'total' => 30, 'with_tax' => 36, 'due' => '2026-01-15', 'summary' => '3 x 10 = 30'
      )
    end

    it 'keeps zero results instead of dropping the formula field' do
      submitter.values = { 'price' => '0', 'qty' => '3' }

      expect(described_class.build_formula_values(submitter)).to include('total' => 0)
    end
  end
end
