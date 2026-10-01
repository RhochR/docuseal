# frozen_string_literal: true

RSpec.describe 'Personalization Settings', :js do
  let!(:account) { create(:account) }
  let!(:user) { create(:user, account:) }

  before do
    sign_in(user)
    visit settings_personalization_path
  end

  it 'shows the notifications settings page' do
    expect(page).to have_content('Email Templates')
    expect(page).to have_content('Company Logo')
    expect(page).to have_content('Submission Form')
  end

  it 'uploads and removes the company logo' do
    account.update_column(:name, 'Acme Corp')
    visit settings_personalization_path

    attach_file('logo_file', Rails.root.join('spec/fixtures/sample-image.png'), make_visible: true)

    expect(page).to have_content('Logo has been uploaded.')
    expect(page).to have_css("img[alt='#{account.name}']")
    expect(account.reload.logo).to be_attached

    accept_confirm { click_button 'Remove' }

    expect(page).to have_content('Logo has been removed.')
    expect(account.reload.logo).not_to be_attached
  end
end
