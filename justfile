# Modules

mod tf 'terraform/tf.just'

set dotenv-load := true

# Alias

alias t := mise-tools

# Check current AWS identity
@aws-check:
    aws sts get-caller-identity

# List mise tools installed in current directory
@mise-tools:
    mise ls --json | jq -r --arg pwd "$(pwd)" 'to_entries[] | select(.value[].source.path != null and (.value[].source.path | contains($pwd))) | .key'

# Terraform recipes

# Initialize terraform (download providers, modules, and initialize backend)
@init:
    terraform init

# Create a plan and save it to a file
# Usage: just plan "-var-file=tfvars/dev.tfvars"
@plan *var:
    terraform plan -out plan {{ var }}

# Apply the saved plan
@apply:
    terraform apply plan

# Create a destroy plan and apply it
# Usage: just destroy "-var-file=tfvars/dev.tfvars"
@destroy *var:
    terraform plan -destroy -out destroy {{ var }}
    terraform apply destroy

# Format terraform files (write changes in place)
@lint:
    terraform fmt -write=true -recursive

# Validate terraform configuration
@validate:
    terraform validate

# Generate/update terraform documentation
@docs:
    terraform-docs markdown table --output-file=README.md --output-mode=replace .

# terraform recipes for manages state

# Show terraform state
@show:
    terraform show

# List terraform state resources
@list:
    terraform state list

@refresh:
    terraform refresh
