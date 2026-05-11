set dotenv-load := true

# ============================================================================
# Aliases principais
# ============================================================================
alias t := mise-tools
alias sts := aws-check

# Simple aliases for terraform recipes
alias p := tf-plan
alias apply := tf-apply
alias destroy := tf-destroy
alias fmt := tf-lint
alias validate := tf-check
alias docs := tf-docs
alias init := tf-init
alias list := tf-list
alias show := tf-show
alias refresh := tf-refresh

# ============================================================================
# AWS e ferramentas
# ============================================================================

# Check current AWS identity
@aws-check:
    aws sts get-caller-identity

# List mise tools installed in current directory
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
