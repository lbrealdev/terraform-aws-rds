set dotenv-load := true

# Alias

alias t := mise-tools
alias sts := aws-check

# Check current AWS identity
@aws-check:
    aws sts get-caller-identity

# List mise tools installed in current directory
@mise-tools:
    mise ls --json | jq -r --arg pwd "$(pwd)" 'to_entries[] | select(.value[].source.path != null and (.value[].source.path | contains($pwd))) | .key'

# Terraform recipes

# Initialize terraform (download providers, modules, and initialize backend)
@tf-init:
    terraform init

# Create a plan and save it to a file
# Usage: just plan "-var-file=tfvars/dev.tfvars"
@tf-plan *var:
    terraform plan -out plan {{ var }}

# Apply the saved plan
@tf-apply:
    terraform apply plan

# Create a destroy plan and apply it
# Usage: just destroy "-var-file=tfvars/dev.tfvars"
@tf-destroy *var:
    terraform plan -destroy -out destroy {{ var }}
    terraform apply destroy

# Format terraform files (write changes in place)
@tf-lint:
    terraform fmt -write=true -recursive

# Validate terraform configuration
@tf-check:
    terraform validate

# Generate/update terraform documentation
@tf-docs:
    terraform-docs markdown table --output-file=README.md --output-mode=replace .

# terraform recipes for manages state

# Show terraform state
@tf-show:
    terraform show

# List terraform state resources
@tf-list:
    terraform state list

@tf-refresh:
    terraform refresh
