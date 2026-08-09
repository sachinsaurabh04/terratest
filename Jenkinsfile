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
