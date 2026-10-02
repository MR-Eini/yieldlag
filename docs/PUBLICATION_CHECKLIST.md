# Release checklist

For each release:

- Confirm DESCRIPTION, NEWS.md, CITATION.cff, and inst/CITATION agree.
- Review data terms separately from the MIT code license.
- Run tests, build vignettes, check the archive, and install in an isolated library.
- Scan the public Git tree for credentials, machine paths, old outputs, and
  third-party scripts with different licenses.
- Require the GitHub matrix to pass before publishing the release.
- Tag the verified commit, publish its source tarball and SHA-256, and verify
  installation from the downloaded asset.

A software release does not require a new scientific experiment. A manuscript
claim about superiority does: see VALIDATION.md. Report failures, season
assumptions, metric uncertainty, and information available at each forecast origin.
