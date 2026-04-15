# How to Contribute

This document describes the automated CI/CD pipeline implemented in GitHub Actions for Salesforce metadata deployment. It is triggered by specific branch patterns and events, ensuring that changes are validated and deployed to the appropriate Salesforce orgs (QA, UAT, PreProd, Production) in a controlled manner.

## Overview
The pipeline uses Salesforce CLI to validate and deploy metadata. It supports four environments:

1. QA (Development / Integration)
2. UAT (User Acceptance Testing)
3. PreProd (Pre-production staging)
4. Production

Depending on the branch and event type, the pipeline either performs a validation (check-only deploy) or an actual deployment to the target org.

<hr>

## Branch Naming Conventions

To map a branch to the correct environment, you must follow these naming patterns:

| Environment | Branch Pattern        | Example                       |
|------------|----------------------|---------------------------------|
| QA         | feature/QADIR/*      | feature/QADIR/new-page          |
| QA         | develop              | develop                         |
| UAT        | release/uat/*        | release/uat/v1.2.0              |
| PreProd    | release/preprod/*    | release/preprod/v1.2.0          |
| Production | release/prod/*       | release/prod/v1.2.0             |


Any branch that does not match these patterns will be rejected by the pipeline.

<hr>

## Triggers

The workflow runs on the following GitHub events:

1. Create – when a new branch or tag is created (used for release branches).
2. Push – to branches matching feature/QADIR/*.
3. Pull Request – opened, synchronized, reopened, or closed against develop or feature/QADIR/* branches.

⚠️ Note: Deployment to an environment happens only on specific events – see the Deployment Jobs section for details.

<hr>

## Workflow Jobs

**Setup Job:** Determines target environment (QA/UAT/PreProd/Prod) and test level based on branch name.

**Validation Jobs:** For each environment, perform a check-only deployment (sf project deploy validate) on pushes, PRs, or branch creation.

**Deployment Jobs:** If validation succeeds, run actual deployment (sf project deploy start) triggered by specific events (e.g., branch creation, PR merge).

**Authentication:** All jobs use JWT bearer flow with secrets (client ID, username, private key) for each environment.

**Salesforce CLI Commands:** Validate or deploy metadata using source (force-app/) or manifest files, with defined test levels and wait times.

> **PreProd** uses a manifest file (`manifest/packageDIR.xml`) to select specific components.

> **Production** uses a manifest (`manifest/package.xml`) to deploy a controlled set of metadata.

<hr>

## How to Contribute

### Feature Development (QA)

Create a feature branch from develop following the pattern:

> feature/QADIR/short-description

1. Push your changes to this branch.
2. This will trigger a validation against the QA org. Check the GitHub Actions run to see if your changes are valid.
3. Open a Pull Request against the develop branch.
4. The PR will again trigger a validation against QA. The pipeline will not deploy until the PR is merged.
5. Merge the PR into develop.
6. After a successful merge, the pipeline will deploy your changes to the QA org automatically.
7. ✅ The QA environment is updated only after code is merged to develop. Feature branches themselves are not deployed – only validated.

<hr>

### Release to Higher Environments (Authority to only Authorized entity)

To promote code to UAT, PreProd, or Production, you must create the appropriate release branch:

1. Ensure all desired changes are already merged into develop (or the previous environment's branch).
2. Create a new branch from the commit you want to release, following the pattern:
    
      `release/uat/<version> for UAT`
   
      `release/preprod/<version> for PreProd`

      `release/prod/<version> for Production`

4. Push the branch.
5. The pipeline will validate and then deploy automatically (validation must succeed before deployment).
