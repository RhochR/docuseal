<h1 align="center" style="border-bottom: none">
  <div>
    <img alt="DocuSeal" src="https://github.com/user-attachments/assets/38b45682-ffa4-4919-abde-d2d422325c44" width="80" />
    <br>
    DocuSeal (Fork)
  </div>
</h1>
<h3 align="center">
  Open source document filling and signing
</h3>

> [!WARNING]
> **Hinweis (Deutsch)**
>
> Dieses Repository ist ein Fork von [DocuSeal](https://github.com/docusealco/docuseal). Die Änderungen gegenüber dem Original wurden mit Hilfe eines KI-Assistenten geschrieben. Es ist ein Experiment und kein ernst gemeintes Projekt: Es gibt keinen Support und keine Gewähr, und es ist nicht für den produktiven Einsatz, für sensible oder rechtlich bindende Dokumente gedacht. Nutzung auf eigene Verantwortung.
>
> Der Fork hat nichts mit DocuSeal LLC zu tun, wird nicht mit dem Originalprojekt zusammengeführt und ist kein offizielles Produkt.
>
> **Notice (English)**
>
> This repository is a fork of [DocuSeal](https://github.com/docusealco/docuseal). The changes compared to the original were written with the help of an AI assistant. It is an experiment and not a serious project: there is no support and no warranty, and it is not meant for production use or for sensitive or legally binding documents. Use it at your own risk.
>
> The fork is not affiliated with DocuSeal LLC, it will not be merged back into the original project and it is not an official product.

## What this fork changes

Some features that the original project only offers in its commercial version are implemented here from scratch (no code of the commercial version is used):

- **Conditional fields**: show fields depending on the value of other fields.
- **Formula fields**: calculate number, date and text fields from other fields. The result is also computed on the server when the form is submitted.
- **Company logo**: shown on the signing pages, in emails, in the audit log and in the signature stamp.
- **HTML email templates**: write invitation, completed and documents copy emails as HTML, in the account settings, per template or per submission.
- **Bulk send from a spreadsheet**: import a CSV or XLSX file, map its columns to recipients and prefilled fields and create one submission per row.

Emails are sent from the address configured in the SMTP settings.

## Features of DocuSeal

- PDF form fields builder (WYSIWYG)
- 12 field types available (Signature, Date, File, Checkbox etc.)
- Multiple submitters per document
- Automated emails via SMTP
- Files storage on disk or AWS S3, Google Storage, Azure Cloud
- Automatic PDF eSignature
- PDF signature verification
- Users management
- Mobile-optimized
- 7 UI languages with signing available in 14 languages
- API and Webhooks for integrations

Not part of this fork (offered by the original project in its commercial version): user roles, automated reminders, invitation and identity verification via SMS, SSO / SAML, template creation from HTML, PDF or DOCX through the API, and the embedded signing form and form builder.

## Running it

By default the app uses an SQLite database. Set the `DATABASE_URL` environment variable to use PostgreSQL or MySQL instead.

A Docker image of this fork is built automatically from the `master` branch by GitHub Actions and published to the GitHub Container Registry as `ghcr.io/rhochr/docuseal` (tags: `latest`, `sha-<commit>` and the version for tags like `v1.2.3`). The images for `amd64` and `arm64` are one multi-platform image, so nothing has to be built locally:

```sh
docker run --name docuseal -p 3000:3000 -v "$PWD":/data ghcr.io/rhochr/docuseal:latest
```

The app is then available at http://localhost:3000. To use PostgreSQL with automatic HTTPS (Caddy), use the `docker-compose.yml` of this repository, which already points to this image:

```sh
sudo HOST=your-domain.example docker compose up
```

The Docker Hub image and the deploy buttons of the original project start the original DocuSeal, not this fork. The image runs the application as `root` inside the container, like the original image. Do not expose it directly to the internet without HTTPS, and keep the mounted data directory and the SMTP password private.

To build the image yourself, create a `.version` file (the `Dockerfile` copies it) and run `docker build`:

```sh
echo "fork" > .version
docker build -t docuseal-fork .
```

For development you need Ruby (see the `Gemfile` for the version), Node.js with Yarn and PostgreSQL. Run `bundle install`, `yarn install` and `bin/rails db:create db:migrate`, then `bundle exec foreman start -f Procfile.dev`. The tests run with `bundle exec rspec`.

## License

Distributed under the AGPLv3 License with Section 7(b) Additional Terms. See [LICENSE](LICENSE) and [LICENSE_ADDITIONAL_TERMS](LICENSE_ADDITIONAL_TERMS) for more information. The original DocuSeal attribution ("Powered by DocuSeal") stays in the user interface and in emails and can not be turned off.

Unless otherwise noted, all files © 2023-2026 DocuSeal LLC. Changes in this fork are published under the same license.
