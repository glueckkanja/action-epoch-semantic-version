This file should be used to describe your reusable workflow. Please fill all of these pre-defined topics and add more content if there's more to describe.
!PLEASE KEEP IN MIND TO CONFIGURE SUITABLE BRANCHING AND PROTECTION RULES!

## Name of The Workflow

Describe or summarize the functionality of the workflow here.

### Calling the action

This example yaml code block should show the usage of you workflow in very detail. Within this code block all variables should be visible so that all functionalities will be understandable.

```yaml
# actions.yml in a consumer repository
name: Any Example Workflow

on:
  push:
    branches:
      - main

jobs:
  example-workflow-run:
    runs-on: ubuntu-latest
    steps:
      - name: Run Example of Workflow
        uses: organization/example-workflow-repository@sha-hash # v1.2.3
        with:
          any-var: "any-value"
```

### Permissions

- if the workflow is in need of any declared permission, describe them here

### Inputs

- `any-variable` _(string, required)_ – describe input variables like this and list all of them

### Outputs

- `any-output` – show and list all values that may be provided by your workflow here

### Any Other Important Topics

If there's anything else you want to bring up feel free to create a more detailed description by creating more sub-headings
