Since you already have the S3 bucket terraform-remote-state26, we can make this a much better Jenkins/Terraform setup.

I recommend this flow:

                         GitHub
                           │
                           ▼
                        Jenkins
                           │
                 ┌─────────┴─────────┐
                 │                   │
              DEPLOY              DESTROY
                 │                   │
                 ▼                   ▼
          Terraform Plan       Terraform Destroy Plan
                 │                   │
                 ▼                   ▼
          Approval Gate        Approval Gate
                 │                   │
                 ▼                   ▼
          Terraform Apply      Terraform Apply
                 │                   │
                 └─────────┬─────────┘
                           ▼
                         AWS
                           │
                           ▼
                 S3 Remote Terraform State
                 terraform-remote-state26

Terraform's S3 backend now supports native S3 state locking with use_lockfile = true; DynamoDB locking is deprecated in current Terraform documentation. HashiCorp also recommends enabling S3 bucket versioning for state recovery.

1. Change your Terraform code

In your Day-1 directory, create a file:

backend.tf

Put this in it:

terraform {
  backend "s3" {
    bucket       = "terraform-remote-state26"
    key          = "terratest/day-1/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}

Your repository should now look like:

Day-1/
├── .gitignore
├── backend.tf
├── Jenkinsfile
├── main.tf
└── readme.md
Why this key?

Your state will be stored as:

s3://terraform-remote-state26/terratest/day-1/terraform.tfstate

This is better than putting terraform.tfstate directly at the root of the bucket.

Later you can have:

terratest/
├── day-1/terraform.tfstate
├── day-2/terraform.tfstate
├── day-3/terraform.tfstate
└── production/terraform.tfstate
2. Make sure the S3 bucket is properly configured

Because this bucket contains Terraform state, I recommend:

Block public access
Enable versioning
Enable server-side encryption
Don't manually edit the Terraform state
Give Jenkins only the permissions it needs

HashiCorp specifically recommends S3 bucket versioning for recovery from accidental deletion or human error.

You can check versioning with AWS CLI:

aws s3api get-bucket-versioning --bucket terraform-remote-state26

Ideally you should see:

{
    "Status": "Enabled"
}

If it isn't enabled:

aws s3api put-bucket-versioning `
  --bucket terraform-remote-state26 `
  --versioning-configuration Status=Enabled
3. Jenkins credentials

Keep your existing Jenkins credential:

Credential ID:
aws-terraform

with:

Username = AWS Access Key ID
Password = AWS Secret Access Key

The same credentials will be used for:

S3 backend
Terraform state locking
AWS infrastructure

Don't put AWS credentials in main.tf, backend.tf, or GitHub.

4. Production-style Jenkinsfile

Now replace your current Jenkinsfile with this.

pipeline {

    agent any

    options {
        disableConcurrentBuilds()
        timestamps()
        timeout(time: 30, unit: 'MINUTES')
        skipDefaultCheckout(true)
    }

    parameters {
        choice(
            name: 'ACTION',
            choices: ['DEPLOY', 'DESTROY'],
            description: 'Select DEPLOY to create/update infrastructure or DESTROY to remove infrastructure.'
        )
    }

    environment {
        AWS_DEFAULT_REGION = 'us-east-1'
        TF_IN_AUTOMATION = 'true'
        TF_INPUT = 'false'
    }

    stages {

        stage('Checkout') {
            steps {
                deleteDir()

                echo 'Checking out Terraform code...'

                checkout scm
            }
        }

        stage('Terraform Version') {
            steps {
                bat 'terraform version'
            }
        }

        stage('Terraform Init') {
            steps {

                echo 'Initializing Terraform with S3 remote backend...'

                withCredentials([
                    usernamePassword(
                        credentialsId: 'aws-terraform',
                        usernameVariable: 'AWS_ACCESS_KEY_ID',
                        passwordVariable: 'AWS_SECRET_ACCESS_KEY'
                    )
                ]) {

                    bat 'terraform init -input=false'
                }
            }
        }

        stage('Terraform Format') {
            when {
                expression {
                    params.ACTION == 'DEPLOY'
                }
            }

            steps {

                echo 'Formatting Terraform configuration...'

                bat 'terraform fmt -recursive'

                bat 'terraform fmt -check -recursive'
            }
        }

        stage('Terraform Validate') {
            steps {

                echo 'Validating Terraform configuration...'

                withCredentials([
                    usernamePassword(
                        credentialsId: 'aws-terraform',
                        usernameVariable: 'AWS_ACCESS_KEY_ID',
                        passwordVariable: 'AWS_SECRET_ACCESS_KEY'
                    )
                ]) {

                    bat 'terraform validate'
                }
            }
        }

        stage('Terraform Plan - Deploy') {
            when {
                expression {
                    params.ACTION == 'DEPLOY'
                }
            }

            steps {

                echo 'Creating Terraform deployment plan...'

                withCredentials([
                    usernamePassword(
                        credentialsId: 'aws-terraform',
                        usernameVariable: 'AWS_ACCESS_KEY_ID',
                        passwordVariable: 'AWS_SECRET_ACCESS_KEY'
                    )
                ]) {

                    bat 'terraform plan -input=false -out=tfplan'
                }
            }
        }

        stage('Terraform Plan - Destroy') {
            when {
                expression {
                    params.ACTION == 'DESTROY'
                }
            }

            steps {

                echo 'Creating Terraform destroy plan...'

                withCredentials([
                    usernamePassword(
                        credentialsId: 'aws-terraform',
                        usernameVariable: 'AWS_ACCESS_KEY_ID',
                        passwordVariable: 'AWS_SECRET_ACCESS_KEY'
                    )
                ]) {

                    bat 'terraform plan -destroy -input=false -out=tfplan'
                }
            }
        }

        stage('Approval - Deploy') {
            when {
                expression {
                    params.ACTION == 'DEPLOY'
                }
            }

            steps {

                input(
                    message: 'Terraform deployment plan is ready. Do you approve DEPLOY to AWS?',
                    ok: 'APPROVE DEPLOY',
                    cancel: 'REJECT'
                )
            }
        }

        stage('Approval - Destroy') {
            when {
                expression {
                    params.ACTION == 'DESTROY'
                }
            }

            steps {

                input(
                    message: 'WARNING: This will DESTROY Terraform-managed AWS infrastructure. Do you approve?',
                    ok: 'APPROVE DESTROY',
                    cancel: 'CANCEL DESTROY'
                )
            }
        }

        stage('Terraform Apply') {
            steps {

                echo "Executing Terraform action: ${params.ACTION}"

                withCredentials([
                    usernamePassword(
                        credentialsId: 'aws-terraform',
                        usernameVariable: 'AWS_ACCESS_KEY_ID',
                        passwordVariable: 'AWS_SECRET_ACCESS_KEY'
                    )
                ]) {

                    bat 'terraform apply -input=false -auto-approve tfplan'
                }
            }
        }
    }

    post {

        success {
            echo "Terraform ${params.ACTION} completed successfully."
        }

        failure {
            echo "Terraform ${params.ACTION} failed."
        }

        aborted {
            echo "Terraform ${params.ACTION} was aborted/rejected."
        }

        always {
            echo 'Cleaning temporary Terraform plan files...'

            bat 'if exist tfplan del /f /q tfplan'
        }
    }
}

Jenkins' input step pauses the pipeline for human approval and supports custom approve/abort buttons, which is exactly what we're using for the deployment and destruction gates.

5. How you will use it

When you click:

Jenkins → Terraform → Build with Parameters

you will get:

ACTION

▼ DEPLOY
  DESTROY
If you select DEPLOY

Jenkins does:

Checkout
   ↓
Terraform Init
   ↓
Terraform Format
   ↓
Terraform Validate
   ↓
Terraform Plan
   ↓
⏸ APPROVAL
   ↓
Terraform Apply

The approval screen will say:

Terraform deployment plan is ready.
Do you approve DEPLOY to AWS?

[ APPROVE DEPLOY ] [ REJECT ]

If you reject it:

Plan
 ↓
REJECT
 ↓
Pipeline stops

Nothing is deployed.

6. If you select DESTROY

Jenkins does:

Checkout
   ↓
Terraform Init
   ↓
Terraform Validate
   ↓
Terraform Destroy Plan
   ↓
⏸ APPROVAL
   ↓
Terraform Apply

The plan is generated using:

terraform plan -destroy -out=tfplan

Then you get:

WARNING:

This will DESTROY Terraform-managed AWS infrastructure.

[ APPROVE DESTROY ] [ CANCEL DESTROY ]

Only after approval:

terraform apply -auto-approve tfplan

runs.

7. Very important: why disableConcurrentBuilds()

I deliberately added:

options {
    disableConcurrentBuilds()
}

Suppose you accidentally start:

Build #10 → DEPLOY
Build #11 → DESTROY

at the same time.

That is dangerous when they use the same Terraform state.

Terraform's state locking prevents simultaneous state writers when the backend supports locking, but we should also prevent Jenkins from intentionally running competing operations against the same environment.

So Jenkins will allow only one build of this job at a time.

8. Your S3 state is now remote

After the first successful:

terraform init

you should see something like:

Initializing the backend...

Successfully configured the backend "s3"!

Then your state will be in:

terraform-remote-state26
        │
        └── terratest/
              └── day-1/
                    └── terraform.tfstate

You should not see:

terraform.tfstate

in your GitHub repository.

Your .gitignore should continue to have:

.terraform/
*.tfstate
*.tfstate.*
*.tfplan
crash.log
crash.*.log

And keep:

.terraform.lock.hcl

in Git.

9. One thing I recommend changing in main.tf

Your current code uses:

provider "aws" {
  region = "us-east-1"
}

That's fine, but since Jenkins already sets:

AWS_DEFAULT_REGION = 'us-east-1'

I'd make the Terraform code:

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

Then your infrastructure becomes easier to promote later:

dev     → us-east-1
staging → us-east-1
prod    → us-east-2

We don't have to do that immediately, though.

10. One more production concern: IAM

For your learning environment, the Jenkins AWS user can have the required S3 + EC2 permissions.

But don't give Jenkins AdministratorAccess in a real production account.

At minimum, the Jenkins role/user needs access to the Terraform state:

S3 bucket:
terraform-remote-state26

Permissions:
s3:ListBucket
s3:GetObject
s3:PutObject
s3:GetObject
s3:DeleteObject       ← lock file

For the lock file specifically, Terraform documents the need for GetObject, PutObject, and DeleteObject on the .tflock object when use_lockfile is enabled.

Then separately give it only the AWS resource permissions Terraform actually needs.

Final architecture

With these changes, your lab is now approaching a real CI/CD implementation:

                  ┌──────────────┐
                  │    GitHub    │
                  │    develop   │
                  └──────┬───────┘
                         │
                         ▼
                  ┌──────────────┐
                  │    Jenkins   │
                  └──────┬───────┘
                         │
               Build with Parameters
                         │
                  ┌──────┴──────┐
                  │             │
                DEPLOY        DESTROY
                  │             │
                  ▼             ▼
                PLAN          PLAN
                  │             │
                  ▼             ▼
             APPROVAL       APPROVAL
                  │             │
                  ▼             ▼
                APPLY         APPLY
                  │             │
                  └──────┬──────┘
                         ▼
                    ┌─────────┐
                    │   AWS   │
                    └─────────┘
                         ▲
                         │
                  Terraform State
                         │
                         ▼
              ┌─────────────────────┐
              │ S3                  │
              │ terraform-          │
              │ remote-state26      │
              │                     │
              │ terratest/          │
              │ └── day-1/          │
              │     └── state       │
              └─────────────────────┘
