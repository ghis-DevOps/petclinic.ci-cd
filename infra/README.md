# PetClinic infra

Terraform for deploying PetClinic to AWS: ECS Fargate behind an ALB, CloudFront in front of the ALB, RDS Postgres, ECR, and a GitHub Actions OIDC role for CI/CD.

## Architecture

- **VPC** — public subnets (ALB, NAT) + private subnets (ECS tasks, RDS).
- **ECR** — image repository for the app.
- **ECS (Fargate)** — cluster, task definition, service. DB credentials are injected via Secrets Manager, not env vars.
- **RDS (Postgres)** — private, credentials generated with `random_password` and stored in Secrets Manager (never in tfvars or state you'd commit).
- **ALB** — routes to the ECS service.
- **CloudFront** — sits in front of the ALB. Works two ways:
  - `domain_name = ""` (default): app is served at the CloudFront default domain (`*.cloudfront.net`), ALB origin over plain HTTP.
  - `domain_name` set to an existing Route53 hosted zone: Terraform issues ACM certs (regional + us-east-1 for CloudFront), adds `<subdomain>.<domain_name>` as a CloudFront alias, and terminates TLS on the ALB.
- **GitHub OIDC** — an IAM role (`github_actions_deploy`) that GitHub Actions assumes via OIDC to push to ECR and deploy to ECS. Reuses an existing OIDC provider if one is already in the account (`create_github_oidc_provider = false`).

## Usage

### Recovering the database secret

Secrets Manager rejects `CreateSecret` when the same name is still scheduled for deletion. If Terraform reports that `petclinic/prod/db` already exists or is scheduled for deletion, restore it first if needed. The temporary `import` block in `rds.tf` adopts the existing secret into Terraform state:

```bash
aws secretsmanager restore-secret --secret-id petclinic/prod/db --region us-east-1
terraform -chdir=infra plan
terraform -chdir=infra apply
```

Skip the restore command if the secret already exists and is no longer pending deletion. After Terraform has successfully adopted it, remove the temporary `import` block from `rds.tf` and apply again. Importing only reconciles Terraform state; it does not rotate the database password. The secret resource uses a 7-day recovery window for future Terraform deletions.

```bash
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

Configure inputs in `terraform.tfvars` (already filled in with working defaults for this project — adjust as needed).

Key variables:

| Variable | Purpose |
|---|---|
| `domain_name` / `subdomain` | Custom domain, optional (see above) |
| `github_org` / `github_repo` | Repo allowed to assume the CI deploy role |
| `create_github_oidc_provider` | Set `false` if the account already has a GitHub OIDC provider |
| `db_*` | RDS sizing/engine version |
| `task_cpu` / `task_memory` / `desired_count` | ECS Fargate sizing |

## Outputs → GitHub secrets

`app_url`, `cloudfront_domain_name`, `ecr_repository_name`, `aws_region`, `ecs_cluster_name`, `ecs_service_name`, and `github_actions_role_arn` map directly to the secrets `.github/workflows/pipeline.yml` expects (`ECR_REPOSITORY`, `AWS_REGION`, `ECS_CLUSTER`, `ECS_SERVICE`, `AWS_ROLE_ARN`).

## Do not commit

`.gitignore` excludes `.terraform/`, `*.tfstate*`, and plan files (`tfplan`, `*.tfplan`) — **never commit a saved `terraform plan -out=...` file or `terraform.tfstate`**. Both can contain secrets (e.g. the RDS password) in plaintext even though the CLI redacts sensitive values in its own output.
