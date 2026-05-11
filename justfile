set dotenv-load := true

# ============================================================================
# Aliases principais
# ============================================================================
alias t := mise-tools
alias sts := aws-check

# Simple aliases for terraform recipes
alias check := aws-check      # tf-check alias
alias p := tf-plan             # tf-plan alias
alias apply := tf-apply        # tf-apply alias
alias destroy := tf-destroy    # tf-destroy alias
alias fmt := tf-lint           # tf-lint alias
alias validate := tf-check     # tf-check alias
alias docs := tf-docs          # tf-docs alias
alias init := tf-init          # tf-init alias
alias list := tf-list          # tf-list alias
alias show := tf-show          # tf-show alias
alias refresh := tf-refresh    # tf-refresh alias

# ============================================================================
# AWS e ferramentas
# ============================================================================

# Check current AWS identity [alias: sts, check]
@aws-check:
    aws sts get-caller-identity

# List mise tools installed in current directory [alias: t]
@mise-tools:
    mise ls --json | jq -r --arg pwd "$(pwd)" 'to_entries[] | select(.value[].source.path != null and (.value[].source.path | contains($pwd))) | .key'

# ============================================================================
# Terraform Recipes
# ============================================================================

# Initialize terraform (download providers, modules, and initialize backend) [alias: init]
@tf-init:
    terraform init

# Create a plan and save it to a file [alias: p, plan]
@tf-plan *var:
    terraform plan -out plan {{ var }}

# Apply the saved plan [alias: apply]
@tf-apply:
    terraform apply plan

# Create a destroy plan and apply it [alias: destroy]
@tf-destroy *var:
    terraform plan -destroy -out destroy {{ var }}
    just _tf-destroy

# Prompt de confirmação para destroy
[confirm("Are you sure you want to destroy all Terraform resources? This action cannot be undone.")]
@_tf-destroy:
    terraform apply destroy

# Format terraform files (write changes in place) [alias: fmt]
@tf-lint:
    terraform fmt -write=true -recursive

# Validate terraform configuration [alias: validate, check]
@tf-check:
    terraform validate

# Generate/update terraform documentation [alias: docs]
@tf-docs:
    terraform-docs markdown table --output-file=README.md --output-mode=replace .

# Terraform state management

# Show terraform state [alias: show]
@tf-show:
    terraform show

# List terraform state resources [alias: list]
@tf-list:
    terraform state list

# Refresh terraform state [alias: refresh]
@tf-refresh:
    terraform refresh