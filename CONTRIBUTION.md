# Contribution Guideline

This repository follows the Secure Software Development Life Cycle (SSDLC) principles with a pragmatic approach. The SSDLC is a cyclical development process - `plan -> code -> test -> deploy -> maintain`.

## Code

### Commit Messages

Commit messages should follow the [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/) guideline to make it easier for others to understand what changes were made. The format of a commit message is as follows:

```bash
git commit -m '<type>(<scope>): <description>'
```

- `<type>`: The type of change being made. There are four main types: `feat` is for new features, `fix` is for bug fixes, `docs` is for updating documentation and `chore` is for other changes that do not affect the core functionality of the project.
- `<scope>`: The scope of the project. This is an optional field that adds context to the area where the change occured.
- `<description>`: A brief description of the change.

The `<type>` is important because it dictates which semantic version of the project should be incremented.

| type                  | semver | outcome        |
| --------------------- | ------ | -------------- |
| docs, chore           | -      | 0.0.1 -> 0.0.1 |
| fix                   | patch  | 0.0.1 -> 0.0.2 |
| feat                  | minor  | 0.0.1 -> 0.1.0 |
| !feat, !fix, BREAKING | major  | 0.0.1 -> 1.0.0 |

### Pull Requests

Pull request titles must also follow the convention commit format explained in the [commit messages](#commit-messages) section so that the merging process triggers the release please job in the [.github/workflows/cd.yaml](./.github/workflows/cd.yaml) workflow.

## Test

### Security

This repository scans for several security vulnerabilities that can be introduced dduring development using open source security scanning tools.

- [Trivy](https://trivy.dev/docs/latest/getting-started/) is used to scan for vulnerabl dependencies, configurations, and hard-coded credentials in the source code.

| Vulnerability                        | What is it?                               | Why is it bad?                                                                                                    | Tools             |
| ------------------------------------ | ----------------------------------------- | ----------------------------------------------------------------------------------------------------------------- | ----------------- |
| **Vulnerable Dependencies**          | Using outdated or flawed software parts.  | Allows attackers to exploit known weaknesses which can lead to system takeover, data theft, application crash.    | Trivy, Dependabot |
| **Hardcoded Credentials/Secrets**    | Storing passwords/keys directly in code.  | Makes it easy for attackers to find them which can lead to account hijacking, data breaches, unauthorized access. | Trivy             |
| **Misconfigured or Vulnerable Code** | Mistakes in how the application is built. | Creates entry points for attackers which can lead to data breaches, application crashes, remote control.          | Trivy             |

### Linting

This repo leverages several linters to ensure a coherent coding style and quality.

**CommitLint**:

[Commitlint](https://commitlint.js.org/) is used to ensure that the commit messages follow the conventional commit format as explained in the [commit messages](#commit-messages) section. The commitlint is configured in [.commitlintrc](./.commitlintrc) and the checks are triggered in the [.github/workflows/ci.yaml](./.github/workflows/ci.yaml) workflow.

### Testing

Write some tests so that you can sleep better at night.

## Deploy

### Releases

This repository uses the [release-please-action](https://github.com/googleapis/release-please-action) action to prepare a pull request with a summary of changes and title that looks like this - "Release vX.X.X". Once you are satisfied with all your changes, you can merge the pull request to create a release. This entire process is managed through the [.github/workflows/cd.yaml](./.github/workflows/cd.yaml) workflow which is triggered after changes are pushed to the `main` branch.
